import asyncio
import random

from app.core.config import settings
from app.core.logging import get_logger, setup_logging
from app.domain.events import EVENT_ORDER_DRIVER_ASSIGNED, new_envelope
from app.messaging.consumer import EventConsumer
from app.messaging.outbox import emit_outbox
from app.messaging.retries import ProcessFailure
from workers.common import DRIVERS, apply_transition, process_business_event

logger = get_logger(__name__)


async def delivery_effect(session, order, envelope, attempt: int) -> None:
    await asyncio.sleep(settings.SIM_DELIVERY_DELAY_SECONDS)

    if settings.DELIVERY_FAILURE_MODE == "always_fail":
        raise ProcessFailure("Simulated driver assignment failure")

    from app.models.orders import DriverAssignment

    driver_name, vehicle = DRIVERS[random.Random(order.id).randrange(len(DRIVERS))]
    session.add(
        DriverAssignment(order_id=order.id, driver_name=driver_name, vehicle=vehicle, eta_minutes=25)
    )
    await apply_transition(
        session, order, envelope, "DRIVER_ASSIGNED", f"Driver {driver_name} assigned (simulated)"
    )
    await emit_outbox(
        session,
        new_envelope(
            EVENT_ORDER_DRIVER_ASSIGNED,
            order_id=order.id,
            order_version=order.version,
            correlation_id=envelope.correlation_id,
            causation_id=envelope.event_id,
            data={"driver_name": driver_name, "vehicle": vehicle, "eta_minutes": 25},
        ),
    )


async def handle(envelope, attempt: int) -> None:
    await process_business_event("delivery-worker", envelope, attempt, delivery_effect)


def main() -> None:
    setup_logging()
    asyncio.run(EventConsumer("delivery-worker", "delivery.queue", handle).run())


if __name__ == "__main__":
    main()
