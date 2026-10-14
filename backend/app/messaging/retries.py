import asyncio
import socket
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import get_logger
from app.db.session import SessionFactory
from app.models.messaging import ProcessedEvent, QuarantineRecord, RetryJob
from app.domain.events import (
    QUARANTINE_EXCHANGE,
    QUARANTINE_ROUTING_KEY,
    EventEnvelope,
)

logger = get_logger(__name__)


class ProcessFailure(Exception):
    """Known, retryable processing failure."""


class MalformedEvent(Exception):
    """Event can never be processed (bad schema, unknown type, missing order)."""


async def record_processed(session: AsyncSession, consumer_name: str, event_id: str) -> bool:
    """Insert dedupe record. Returns False when the event was already processed."""
    result = await session.execute(
        pg_insert(ProcessedEvent)
        .values(consumer_name=consumer_name, event_id=event_id)
        .on_conflict_do_nothing(index_elements=["consumer_name", "event_id"])
    )
    return result.rowcount > 0


async def schedule_retry(
    consumer_name: str,
    envelope: EventEnvelope,
    queue_name: str,
    attempt: int,
    delays: list[float],
) -> None:
    """Persist a durable retry job. attempt is 1-based processing attempt that failed."""
    if attempt <= len(delays):
        next_attempt_at = datetime.now(timezone.utc) + timedelta(seconds=delays[attempt - 1])
        async with SessionFactory() as session:
            async with session.begin():
                await session.execute(
                    pg_insert(RetryJob)
                    .values(
                        event_id=envelope.event_id,
                        queue_name=queue_name,
                        routing_key="",
                        envelope=envelope.to_dict(),
                        attempts=attempt,
                        max_attempts=len(delays),
                        next_attempt_at=next_attempt_at,
                        status="SCHEDULED",
                    )
                    .on_conflict_do_update(
                        index_elements=["event_id"],
                        set_={
                            "attempts": attempt,
                            "next_attempt_at": next_attempt_at,
                            "status": "SCHEDULED",
                        },
                    )
                )
        logger.warning(
            "retry scheduled",
            extra={"consumer": consumer_name, "event_id": envelope.event_id, "attempt": attempt},
        )
    else:
        logger.error(
            "attempts exhausted, quarantining",
            extra={"consumer": consumer_name, "event_id": envelope.event_id},
        )
        await quarantine_event(
            consumer_name=consumer_name,
            event_id=envelope.event_id,
            queue_name=queue_name,
            reason="attempts_exhausted",
            envelope=envelope.to_dict(),
            apply_terminal=True,
        )


async def quarantine_event(
    consumer_name: str,
    event_id: str,
    queue_name: str,
    reason: str,
    envelope: dict | None = None,
    raw_payload: str | None = None,
    apply_terminal: bool = False,
) -> None:
    """Persist quarantine record; optionally apply terminal order effects and publish
    the quarantine envelope through the durable dead-letter exchange."""
    from app.messaging.publisher import get_publisher_channel
    import json as _json

    await _apply_terminal_effects(queue_name, envelope, reason)

    async with SessionFactory() as session:
        async with session.begin():
            session.add(
                QuarantineRecord(
                    event_id=event_id,
                    queue_name=queue_name,
                    reason=reason,
                    envelope=envelope,
                    raw_payload=raw_payload,
                )
            )

    if envelope is not None:
        try:
            channel = await get_publisher_channel()
            exchange = await channel.declare_exchange(QUARANTINE_EXCHANGE, aio_pika.ExchangeType.TOPIC, durable=True)
            await exchange.publish(
                aio_pika.Message(
                    body=_json.dumps(envelope).encode("utf-8"),
                    content_type="application/json",
                    delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
                    correlation_id=envelope.get("correlation_id", ""),
                ),
                routing_key=QUARANTINE_ROUTING_KEY,
                mandatory=True,
            )
            await channel.close()
        except Exception as exc:  # DB record already preserved; DLX publish is best effort
            logger.error("quarantine publish failed", extra={"event_id": event_id, "extra": str(exc)})


async def _apply_terminal_effects(queue_name: str, envelope: dict | None, reason: str) -> None:
    """Exhausted payment -> PAYMENT_FAILED + order.payment.failed; exhausted restaurant or
    delivery -> FAILED + order.failed. Notification failures never change business status."""
    from app.domain import order_state_machine as sm
    from app.domain.events import (
        EVENT_ORDER_FAILED,
        EVENT_ORDER_PAYMENT_FAILED,
        new_envelope,
    )
    from app.models.orders import Order, OrderStatusHistory
    from app.messaging.outbox import emit_outbox
    from sqlalchemy import select

    if envelope is None:
        return
    target: str | None = None
    terminal_event: str | None = None
    if queue_name == "payment.queue":
        target, terminal_event = sm.STATUS_PAYMENT_FAILED, EVENT_ORDER_PAYMENT_FAILED
    elif queue_name in ("restaurant.queue", "delivery.queue"):
        target, terminal_event = sm.STATUS_FAILED, EVENT_ORDER_FAILED
    else:
        return

    event = EventEnvelope.model_validate(envelope)
    async with SessionFactory() as session:
        async with session.begin():
            row = await session.execute(select(Order).where(Order.id == event.order_id).with_for_update())
            order = row.scalar_one_or_none()
            if order is None or not sm.can_transition(order.status, target):
                return
            order.status = target
            order.version += 1
            order.failure_reason = reason
            order.updated_at = datetime.now(timezone.utc)
            session.add(
                OrderStatusHistory(order_id=order.id, status=target, version=order.version, note=reason)
            )
            outgoing = new_envelope(
                terminal_event,
                order_id=order.id,
                order_version=order.version,
                correlation_id=event.correlation_id,
                causation_id=event.event_id,
                data={"reason": reason},
            )
            await emit_outbox(session, outgoing)


def lease_owner() -> str:
    return f"{socket.gethostname()}-{uuid.uuid4().hex[:8]}"


async def sleep_until_cancelled() -> None:
    while True:
        await asyncio.sleep(3600)
