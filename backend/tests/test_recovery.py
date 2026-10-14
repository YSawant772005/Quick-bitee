"""Outbox dispatch, retry scheduling, and quarantine — against the real broker."""

import asyncio
import json
import uuid
from pathlib import Path

import aio_pika
from httpx import AsyncClient
from sqlalchemy import select

from app.domain.events import EVENT_ORDER_CREATED, new_envelope, parse_envelope
from app.messaging.outbox import dispatch_pending_batch, emit_outbox
from app.messaging.retries import schedule_retry

from .conftest import auth, login, new_idem_key

APP_ROOT = Path(__file__).resolve().parents[1]

POLL_TIMEOUT_SECONDS = 20
POLL_INTERVAL_SECONDS = 0.25


async def _await_value(producer, predicate, timeout: float = POLL_TIMEOUT_SECONDS):
    """Bounded polling: repeat `producer` until `predicate` holds."""
    deadline = asyncio.get_running_loop().time() + timeout
    value = await producer()
    while not predicate(value):
        if asyncio.get_running_loop().time() > deadline:
            raise AssertionError(f"condition not met within {timeout}s; last value: {value!r}")
        await asyncio.sleep(POLL_INTERVAL_SECONDS)
        value = await producer()
    return value


async def _await_message(queue, timeout: float = POLL_TIMEOUT_SECONDS):
    """Bounded polling for a (redelivered) message on `queue`."""
    deadline = asyncio.get_running_loop().time() + timeout
    while True:
        message = await queue.get(fail=False, no_ack=False)
        if message is not None:
            return message
        if asyncio.get_running_loop().time() > deadline:
            raise AssertionError(f"no message redelivered within {timeout}s")
        await asyncio.sleep(POLL_INTERVAL_SECONDS)


async def _delete_queue(connection, queue_name: str) -> None:
    try:
        channel = await connection.channel()
        queue = await channel.declare_queue(queue_name, durable=True, passive=True)
        await queue.delete(if_unused=False, if_empty=False)
        await channel.close()
    except Exception:  # pragma: no cover - best-effort cleanup
        pass


async def _make_pending_outbox(order_id: str) -> None:
    from app.db.session import SessionFactory

    async with SessionFactory() as session:
        async with session.begin():
            await emit_outbox(
                session,
                new_envelope(
                    EVENT_ORDER_CREATED,
                    order_id=order_id,
                    order_version=1,
                    correlation_id=str(uuid.uuid4()),
                ),
            )


async def _outbox_status() -> dict:
    from app.db.session import SessionFactory
    from app.models.messaging import OutboxEvent

    async with SessionFactory() as session:
        rows = (await session.execute(select(OutboxEvent))).scalars().all()
        return {r.id: r.status for r in rows}


async def test_outbox_dispatch_publishes_and_marks_sent(clean):
    order_id = uuid.uuid4().hex
    await _make_pending_outbox(order_id)

    from app.core.config import settings

    connection = await aio_pika.connect_robust(settings.AMQP_URL)
    try:
        channel = await connection.channel(publisher_confirms=True)
        from app.messaging.topology import declare_topology

        await declare_topology(channel)
        # bind a temp queue to catch the published message
        tmp = await channel.declare_queue(f"test.catch.{uuid.uuid4().hex}", exclusive=True)
        exchange = await channel.get_exchange("quickbite.orders")
        await tmp.bind(exchange, routing_key="order.created")

        sent = await dispatch_pending_batch(channel)
        assert sent == 1

        message = await asyncio.wait_for(tmp.get(), timeout=5)
        async with message.process():
            body = message.body.decode()
            assert order_id in body
    finally:
        await connection.close()

    statuses = await _outbox_status()
    assert all(s == "SENT" for s in statuses.values())


async def test_crash_after_commit_before_ack_redelivers_without_duplicate_effects(
    client: AsyncClient, seeded, tmp_path
):
    """Assignment §17 scenario 2: a worker that dies after committing its
    transaction but before acknowledging the message must, on redelivery,
    produce no duplicate business effect.

    The crash point (`WORKER_CRASH_POINT=after_tx`) calls `os._exit(1)`, so the
    crash has to happen in a real child process. The message is published to a
    dedicated, uniquely named queue so the Docker workers - which consume the
    production queues - cannot race the test.
    """
    import os
    import subprocess
    import sys

    from app.core.config import settings
    from app.db.session import SessionFactory
    from app.messaging.topology import declare_topology
    from app.models.messaging import OutboxEvent, ProcessedEvent
    from app.models.orders import Order, SimulatedPayment
    from sqlalchemy import func, select
    from workers.common import process_business_event
    from workers.payment_worker import payment_effect

    # --- an order to process -------------------------------------------
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    resp = await client.post(
        "/api/v1/orders",
        json={
            "restaurant_id": seeded["restaurant_id"],
            "delivery_address": "1 Crash Lane",
            "items": [{"menu_item_id": seeded["menu_item_ids"][0], "quantity": 1}],
        },
        headers={**auth(token), "Idempotency-Key": new_idem_key()},
    )
    assert resp.status_code == 202
    order_id = resp.json()["order_id"]

    envelope = new_envelope(
        EVENT_ORDER_CREATED, order_id=order_id, order_version=1, correlation_id=str(uuid.uuid4())
    )
    queue_name = f"test.crash.{uuid.uuid4().hex}"

    # --- child worker: publish, consume, crash before ack ---------------
    child = tmp_path / "crash_worker.py"
    child.write_text(
        """
import asyncio, json, os, sys
import aio_pika
from app.core.config import settings
from app.domain.events import parse_envelope
from app.messaging.consumer import EventConsumer
from app.messaging.topology import declare_topology
from workers.payment_worker import payment_effect
from workers.common import process_business_event

QUEUE, BODY = sys.argv[1], sys.argv[2]


async def handle(envelope, attempt):
    await process_business_event("payment-worker", envelope, attempt, payment_effect)


async def main():
    connection = await aio_pika.connect_robust(settings.AMQP_URL)
    channel = await connection.channel()
    await declare_topology(channel)
    queue = await channel.declare_queue(QUEUE, durable=True)
    exchange = await channel.get_exchange("quickbite.orders")
    await queue.bind(exchange, routing_key="order.created")
    await exchange.publish(
        aio_pika.Message(
            body=BODY.encode(),
            delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
        ),
        routing_key="order.created",
    )
    consumer = EventConsumer("payment-worker", QUEUE, handle)
    await consumer.run()   # dies inside handle, at after_tx, before ack


asyncio.run(main())
""",
        encoding="utf-8",
    )

    env = {**os.environ, "WORKER_CRASH_POINT": "after_tx", "PYTHONPATH": str(APP_ROOT)}
    try:
        proc = subprocess.run(
            [sys.executable, str(child), queue_name, json.dumps(envelope.to_dict())],
            cwd=str(APP_ROOT),
            env=env,
            capture_output=True,
            timeout=120,
        )
        # os._exit(1) in maybe_crash -> the child never reaches the ack in
        # EventConsumer._on_message.
        assert proc.returncode == 1, (proc.returncode, proc.stdout[-2000:], proc.stderr[-2000:])

        async def order_state():
            async with SessionFactory() as session:
                row = await session.execute(select(Order).where(Order.id == order_id))
                order = row.scalar_one()
                return order.status, order.version

        # --- the commit survived the crash ------------------------------
        status, version = await _await_value(order_state, lambda s: s[0] == "PAID")
        assert (status, version) == ("PAID", 2)

        # --- redelivery: the broker hands the unacked message back ------
        connection = await aio_pika.connect_robust(settings.AMQP_URL)
        try:
            channel = await connection.channel()
            queue = await channel.declare_queue(queue_name, durable=True)

            message = await _await_message(queue)
            redelivered = parse_envelope(message.body)
            assert redelivered.event_id == envelope.event_id

            # Replay the delivery exactly as the consumer would.
            await process_business_event("payment-worker", redelivered, 1, payment_effect)
            await message.ack()
        finally:
            await connection.close()

        # --- no duplicated business effects -----------------------------
        assert await order_state() == ("PAID", 2), "redelivery changed order state again"

        async with SessionFactory() as session:
            payments = await session.execute(
                select(func.count())
                .select_from(SimulatedPayment)
                .where(SimulatedPayment.order_id == order_id)
            )
            processed = await session.execute(
                select(func.count())
                .select_from(ProcessedEvent)
                .where(
                    ProcessedEvent.consumer_name == "payment-worker",
                    ProcessedEvent.event_id == envelope.event_id,
                )
            )
            outbox = await session.execute(
                select(func.count())
                .select_from(OutboxEvent)
                .where(
                    OutboxEvent.event_type == "order.paid",
                    OutboxEvent.payload["order_id"].as_string() == order_id,
                )
            )
            assert payments.scalar_one() == 1, "redelivery captured the payment twice"
            assert processed.scalar_one() == 1, "redelivery wrote a duplicate processed_events row"
            assert outbox.scalar_one() == 1, "redelivery published order.paid twice"
    finally:
        cleanup = await aio_pika.connect_robust(settings.AMQP_URL)
        try:
            await _delete_queue(cleanup, queue_name)
        finally:
            await cleanup.close()


async def test_retry_job_scheduled_and_updates(clean):
    from app.core.config import settings

    order_id = uuid.uuid4().hex
    envelope = new_envelope(
        EVENT_ORDER_CREATED, order_id=order_id, order_version=1, correlation_id=str(uuid.uuid4())
    )
    delays = settings.retry_delays

    await schedule_retry("payment-worker", envelope, "payment.queue", 1, delays)
    await schedule_retry("payment-worker", envelope, "payment.queue", 2, delays)

    from app.db.session import SessionFactory
    from app.models.messaging import RetryJob

    async with SessionFactory() as session:
        rows = (await session.execute(select(RetryJob))).scalars().all()
        assert len(rows) == 1
        job = rows[0]
        assert job.attempts == 2
        assert job.status == "SCHEDULED"
        assert job.max_attempts == len(delays)
