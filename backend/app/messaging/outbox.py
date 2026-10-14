from datetime import datetime, timedelta, timezone
import socket
import uuid as uuidlib

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.logging import get_logger
from app.domain.events import EventEnvelope, ROUTING_KEYS
from app.messaging import retries as retry_utils

logger = get_logger(__name__)


async def emit_outbox(session: AsyncSession, envelope: EventEnvelope) -> None:
    from app.models.messaging import OutboxEvent

    session.add(
        OutboxEvent(
            event_type=envelope.event_type,
            routing_key=ROUTING_KEYS[envelope.event_type],
            payload=envelope.to_dict(),
            status="PENDING",
        )
    )


async def dispatch_pending_batch(channel) -> int:
    """Claim a batch of unsent outbox records, publish each with confirms+mandatory,
    and mark them sent. Returns the number dispatched."""
    from app.db.session import SessionFactory
    from app.models.messaging import OutboxEvent

    owner = f"{socket.gethostname()}-{uuidlib.uuid4().hex[:8]}"
    now = datetime.now(timezone.utc)
    async with SessionFactory() as session:
        async with session.begin():
            rows = await session.execute(
                select(OutboxEvent)
                .where(
                    OutboxEvent.status == "PENDING",
                    OutboxEvent.next_retry_at.is_(None) | (OutboxEvent.next_retry_at <= now),
                    OutboxEvent.lease_until.is_(None) | (OutboxEvent.lease_until <= now),
                )
                .order_by(OutboxEvent.created_at)
                .limit(settings.OUTBOX_BATCH_SIZE)
                .with_for_update(skip_locked=True)
            )
            batch = rows.scalars().all()
            for record in batch:
                record.lease_owner = owner
                record.lease_until = now + timedelta(seconds=30)
        ids = [r.id for r in batch]

    for record_id in ids:
        async with SessionFactory() as session:
            async with session.begin():
                row = await session.execute(
                    select(OutboxEvent).where(OutboxEvent.id == record_id).with_for_update()
                )
                record = row.scalar_one_or_none()
                if record is None or record.status == "SENT":
                    continue
                envelope = EventEnvelope.model_validate(record.payload)
                try:
                    from app.messaging.publisher import publish_event

                    await publish_event(channel, record.routing_key, envelope.to_dict(), envelope.correlation_id)
                except Exception as exc:
                    record.attempts += 1
                    delay = min(2 ** record.attempts, 60)
                    record.next_retry_at = datetime.now(timezone.utc) + timedelta(seconds=delay)
                    record.lease_owner = None
                    record.lease_until = None
                    logger.warning(
                        "outbox publish failed; will retry",
                        extra={"event_id": envelope.event_id, "extra": str(exc)},
                    )
                    continue
                record.status = "SENT"
                record.sent_at = datetime.now(timezone.utc)
                record.lease_owner = None
                record.lease_until = None
    return len(ids)


async def run_dispatcher() -> None:
    from app.messaging.connection import get_connection
    from app.messaging.publisher import get_publisher_channel

    connection = await get_connection()
    channel = await get_publisher_channel()
    logger.info("outbox dispatcher started")
    while True:
        try:
            await dispatch_pending_batch(channel)
        except Exception:
            logger.exception("dispatcher iteration failed")
        await __import__("asyncio").sleep(settings.OUTBOX_POLL_INTERVAL_SECONDS)
