"""Outbox dispatch, retry scheduling, and quarantine — against the real broker."""

import asyncio
import uuid

import aio_pika
from sqlalchemy import select

from app.domain.events import EVENT_ORDER_CREATED, new_envelope
from app.messaging.outbox import dispatch_pending_batch, emit_outbox
from app.messaging.retries import schedule_retry


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
