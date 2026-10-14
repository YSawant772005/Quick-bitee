import os
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.logging import get_logger
from app.db.session import SessionFactory
from app.domain import order_state_machine as sm
from app.domain.events import EventEnvelope
from app.messaging.outbox import emit_outbox
from app.messaging.retries import MalformedEvent, ProcessFailure, record_processed
from app.models.orders import Order, OrderStatusHistory

logger = get_logger(__name__)

DRIVERS = [
    ("Ravi Kumar", "KA-05-MH-4821, Honda Activa"),
    ("Priya Sharma", "KA-01-AB-9927, TVS Jupiter"),
    ("Amit Patel", "KA-03-CD-3310, Suzuki Access"),
    ("Neha Singh", "KA-07-EF-7654, Honda Dio"),
]


def maybe_crash(point: str, event_id: str) -> None:
    if settings.WORKER_CRASH_POINT == point:
        logger.error("injected crash at %s", point, extra={"event_id": event_id})
        os._exit(1)


async def apply_transition(
    session: AsyncSession,
    order: Order,
    envelope: EventEnvelope,
    new_status: str,
    note: str,
) -> None:
    sm.assert_transition(order.status, new_status)
    order.status = new_status
    order.version += 1
    order.updated_at = datetime.now(timezone.utc)
    if new_status in (sm.STATUS_PAYMENT_FAILED, sm.STATUS_FAILED):
        order.failure_reason = note
    session.add(
        OrderStatusHistory(order_id=order.id, status=new_status, version=order.version, note=note)
    )


async def load_order_for_event(session: AsyncSession, envelope: EventEnvelope) -> Order:
    row = await session.execute(
        select(Order).where(Order.id == envelope.order_id).with_for_update()
    )
    order = row.scalar_one_or_none()
    if order is None:
        raise MalformedEvent(f"Order {envelope.order_id} not found for event {envelope.event_id}")
    return order


async def process_business_event(
    consumer_name: str,
    envelope: EventEnvelope,
    attempt: int,
    effect,
) -> None:
    """Shared worker core:
    1. dedupe via processed_events (consumer_name, event_id)
    2. lock the order row
    3. validate status/version
    4. run the worker effect inside the same transaction
    5. single commit (caller acks after this returns)
    """
    maybe_crash("before_tx", envelope.event_id)
    async with SessionFactory() as session:
        async with session.begin():
            is_new = await record_processed(session, consumer_name, envelope.event_id)
            if not is_new:
                logger.info(
                    "duplicate event acknowledged",
                    extra={"consumer": consumer_name, "event_id": envelope.event_id},
                )
                return
            order = await load_order_for_event(session, envelope)
            if order.version != envelope.order_version:
                raise ProcessFailure(
                    f"Order version mismatch: have {order.version}, event expects {envelope.order_version}"
                )
            await effect(session, order, envelope, attempt)
    maybe_crash("after_tx", envelope.event_id)
