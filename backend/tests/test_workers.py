import uuid

import pytest
from httpx import AsyncClient
from sqlalchemy import select

from .conftest import auth, login, new_idem_key
from app.domain.events import (
    EVENT_ORDER_CONFIRMED,
    EVENT_ORDER_CREATED,
    new_envelope,
)
from app.messaging.retries import ProcessFailure
from workers.common import process_business_event
from workers.delivery_worker import delivery_effect
from workers.notification_worker import notification_effect
from workers.payment_worker import payment_effect
from workers.restaurant_worker import restaurant_effect


async def _place_order(client: AsyncClient, seeded) -> dict:
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    payload = {
        "restaurant_id": seeded["restaurant_id"],
        "delivery_address": "1 Worker Way",
        "items": [
            {"menu_item_id": seeded["menu_item_ids"][0], "quantity": 1},
            {"menu_item_id": seeded["menu_item_ids"][1], "quantity": 2},
        ],
    }
    resp = await client.post(
        "/api/v1/orders",
        json=payload,
        headers={**auth(token), "Idempotency-Key": new_idem_key()},
    )
    assert resp.status_code == 202
    return resp.json()


async def _load_order(order_id: str):
    from app.db.session import SessionFactory
    from app.models.orders import Order

    async with SessionFactory() as session:
        return (await session.execute(select(Order).where(Order.id == order_id))).scalar_one()


async def _count_outbox(order_id: str, event_type: str) -> int:
    from app.db.session import SessionFactory
    from app.models.messaging import OutboxEvent

    async with SessionFactory() as session:
        rows = await session.execute(
            select(OutboxEvent).where(
                OutboxEvent.event_type == event_type,
                OutboxEvent.payload["order_id"].as_string() == order_id,
            )
        )
        return len(rows.scalars().all())


async def _full_pipeline(client, seeded):
    """Drive PENDING -> PAID -> CONFIRMED -> DRIVER_ASSIGNED in-process."""
    accepted = await _place_order(client, seeded)
    order_id = accepted["order_id"]

    created = new_envelope(
        EVENT_ORDER_CREATED, order_id=order_id, order_version=1, correlation_id=str(uuid.uuid4())
    )
    await process_business_event("payment-worker", created, 1, payment_effect)
    order = await _load_order(order_id)
    assert order.status == "PAID"
    assert order.version == 2
    assert await _count_outbox(order_id, "order.paid") == 1

    paid = new_envelope(
        "order.paid",
        order_id=order_id,
        order_version=2,
        correlation_id=created.correlation_id,
        causation_id=created.event_id,
    )
    await process_business_event("restaurant-worker", paid, 1, restaurant_effect)
    order = await _load_order(order_id)
    assert order.status == "CONFIRMED"
    assert order.version == 3

    confirmed = new_envelope(
        EVENT_ORDER_CONFIRMED,
        order_id=order_id,
        order_version=3,
        correlation_id=created.correlation_id,
        causation_id=paid.event_id,
    )
    await process_business_event("delivery-worker", confirmed, 1, delivery_effect)
    order = await _load_order(order_id)
    assert order.status == "DRIVER_ASSIGNED"
    assert order.version == 4
    return created


async def test_full_pipeline_happy_path(client: AsyncClient, seeded):
    await _full_pipeline(client, seeded)


async def test_worker_processing_is_idempotent(client: AsyncClient, seeded):
    created = new_envelope(
        EVENT_ORDER_CREATED,
        order_id=(await _place_order(client, seeded))["order_id"],
        order_version=1,
        correlation_id=str(uuid.uuid4()),
    )
    await process_business_event("payment-worker", created, 1, payment_effect)
    # duplicate delivery of the same event must not change state again
    await process_business_event("payment-worker", created, 1, payment_effect)
    order = await _load_order(created.order_id)
    assert order.status == "PAID"
    assert order.version == 2
    assert await _count_outbox(created.order_id, "order.paid") == 1


async def test_version_mismatch_raises_process_failure(client: AsyncClient, seeded):
    accepted = await _place_order(client, seeded)
    stale = new_envelope(
        EVENT_ORDER_CREATED,
        order_id=accepted["order_id"],
        order_version=99,
        correlation_id=str(uuid.uuid4()),
    )
    with pytest.raises(ProcessFailure):
        await process_business_event("payment-worker", stale, 1, payment_effect)
    order = await _load_order(accepted["order_id"])
    assert order.status == "PENDING"


async def test_payment_always_fail_then_retry_exhaustion(client: AsyncClient, seeded, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "PAYMENT_FAILURE_MODE", "always_fail")
    accepted = await _place_order(client, seeded)
    order_id = accepted["order_id"]
    correlation = str(uuid.uuid4())
    delays = settings.retry_delays  # [1, 1, 1]

    for attempt in (1, 2, 3):
        envelope = new_envelope(
            EVENT_ORDER_CREATED, order_id=order_id, order_version=1, correlation_id=correlation
        )
        with pytest.raises(ProcessFailure):
            await process_business_event("payment-worker", envelope, attempt, payment_effect)
        if attempt <= len(delays):
            from app.messaging.retries import schedule_retry

            await schedule_retry("payment-worker", envelope, "payment.queue", attempt, delays)
    order = await _load_order(order_id)
    assert order.status == "PENDING"

    # 4th failure exceeds the retry budget -> quarantine + terminal status
    envelope = new_envelope(
        EVENT_ORDER_CREATED, order_id=order_id, order_version=1, correlation_id=correlation
    )
    with pytest.raises(ProcessFailure):
        await process_business_event("payment-worker", envelope, 4, payment_effect)
    await schedule_retry("payment-worker", envelope, "payment.queue", 4, delays)

    order = await _load_order(order_id)
    assert order.status == "PAYMENT_FAILED"
    assert order.failure_reason
    assert await _count_outbox(order_id, "order.payment.failed") == 1


async def test_notification_worker_never_changes_business_status(client: AsyncClient, seeded):
    created = await _full_pipeline(client, seeded)
    final = new_envelope(
        "order.driver.assigned",
        order_id=created.order_id,
        order_version=4,
        correlation_id=created.correlation_id,
    )
    await process_business_event("notification-worker", final, 1, notification_effect)
    order = await _load_order(created.order_id)
    assert order.status == "DRIVER_ASSIGNED"
    assert order.version == 4

    from app.db.session import SessionFactory
    from app.models.orders import Notification

    async with SessionFactory() as session:
        rows = await session.execute(
            select(Notification).where(Notification.order_id == order.id)
        )
        assert len(rows.scalars().all()) >= 1
