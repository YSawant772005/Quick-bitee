import asyncio
from datetime import datetime, timedelta, timezone

from sqlalchemy import select, update

from app.core.config import settings
from app.core.logging import get_logger, setup_logging
from app.db.session import SessionFactory
from app.messaging.connection import get_connection
from app.messaging.publisher import get_publisher_channel, publish_to_queue
from app.models.messaging import RetryJob

logger = get_logger(__name__)


async def run_scheduler() -> None:
    connection = await get_connection()
    channel = await get_publisher_channel()
    logger.info("retry scheduler started")
    while True:
        try:
            now = datetime.now(timezone.utc)
            async with SessionFactory() as session:
                async with session.begin():
                    rows = await session.execute(
                        select(RetryJob)
                        .where(RetryJob.status == "SCHEDULED", RetryJob.next_attempt_at <= now)
                        .order_by(RetryJob.next_attempt_at)
                        .limit(50)
                        .with_for_update(skip_locked=True)
                    )
                    due = rows.scalars().all()
                for job in due:
                    try:
                        await publish_to_queue(
                            channel,
                            job.queue_name,
                            job.envelope,
                            job.envelope.get("correlation_id", ""),
                            headers={"x_attempt": job.attempts + 1},
                        )
                    except Exception as exc:
                        async with session.begin():
                            job.next_attempt_at = now + timedelta(seconds=5)
                        logger.warning(
                            "retry republish failed; will re-attempt",
                            extra={"event_id": job.event_id, "extra": str(exc)},
                        )
                        continue
                    async with session.begin():
                        await session.execute(
                            update(RetryJob)
                            .where(RetryJob.id == job.id)
                            .values(status="DONE", next_attempt_at=now)
                        )
                    logger.info(
                        "retry redelivered",
                        extra={"event_id": job.event_id, "attempt": job.attempts + 1},
                    )
        except Exception:
            logger.exception("scheduler iteration failed")
        await asyncio.sleep(settings.RETRY_SCHEDULER_INTERVAL_SECONDS)


def main() -> None:
    setup_logging()
    try:
        asyncio.run(run_scheduler())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
