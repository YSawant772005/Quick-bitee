import asyncio

from app.core.config import settings
from app.core.logging import get_logger, setup_logging
from app.domain.events import EVENT_ORDER_CONFIRMED, new_envelope
from app.messaging.consumer import EventConsumer
from app.messaging.outbox import emit_outbox
from app.messaging.retries import ProcessFailure
from workers.common import apply_transition, process_business_event

logger = get_logger(__name__)


async def restaurant_effect(session, order, envelope, attempt: int) -> None:
    await asyncio.sleep(settings.SIM_RESTAURANT_DELAY_SECONDS)

    if settings.RESTAURANT_FAILURE_MODE == "always_fail":
        raise ProcessFailure("Simulated restaurant confirmation failure")

    await apply_transition(session, order, envelope, "CONFIRMED", "Restaurant confirmed the order (simulated)")
    await emit_outbox(
        session,
        new_envelope(
            EVENT_ORDER_CONFIRMED,
            order_id=order.id,
            order_version=order.version,
            correlation_id=envelope.correlation_id,
            causation_id=envelope.event_id,
            data={"restaurant_id": order.restaurant_id},
        ),
    )


async def handle(envelope, attempt: int) -> None:
    await process_business_event("restaurant-worker", envelope, attempt, restaurant_effect)


def main() -> None:
    setup_logging()
    asyncio.run(EventConsumer("restaurant-worker", "restaurant.queue", handle).run())


if __name__ == "__main__":
    main()
