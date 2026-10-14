import asyncio

from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.core.config import settings
from app.core.logging import get_logger, setup_logging
from app.domain.events import EventEnvelope
from app.messaging.consumer import EventConsumer
from app.messaging.retries import ProcessFailure
from workers.common import process_business_event

logger = get_logger(__name__)

NOTIFICATION_TEMPLATES = {
    "order.created": ("Order received", "Your order {order} was accepted and is being processed."),
    "order.paid": ("Payment successful", "Payment for order {order} was captured."),
    "order.payment.failed": ("Payment failed", "We could not process payment for order {order}."),
    "order.confirmed": ("Restaurant confirmed", "The restaurant confirmed your order {order}."),
    "order.driver.assigned": ("Driver on the way", "A driver has been assigned to your order {order}."),
    "order.failed": ("Order failed", "Unfortunately order {order} could not be completed."),
}


async def notification_effect(session, order, envelope: EventEnvelope, attempt: int) -> None:
    await asyncio.sleep(settings.SIM_NOTIFICATION_DELAY_SECONDS)
    if settings.NOTIFICATION_FAILURE_MODE == "always_fail":
        raise ProcessFailure("Simulated notification persistence failure")

    from app.models.orders import Notification

    title, message = NOTIFICATION_TEMPLATES[envelope.event_type]
    short_id = order.id[:8]
    await session.execute(
        pg_insert(Notification)
        .values(
            user_id=order.customer_id,
            order_id=order.id,
            event_type=envelope.event_type,
            title=title,
            message=message.format(order=short_id),
        )
        .on_conflict_do_nothing(index_elements=["order_id", "event_type"])
    )
    # Notification failures must never change business status: no order mutation here.


async def handle(envelope, attempt: int) -> None:
    await process_business_event("notification-worker", envelope, attempt, notification_effect)


def main() -> None:
    setup_logging()
    asyncio.run(EventConsumer("notification-worker", "notification.queue", handle).run())


if __name__ == "__main__":
    main()
