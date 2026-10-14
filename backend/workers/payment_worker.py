import asyncio

from app.core.config import settings
from app.core.logging import get_logger, setup_logging
from app.domain.events import EVENT_ORDER_CREATED, EVENT_ORDER_PAID, new_envelope
from app.messaging.consumer import EventConsumer
from app.messaging.outbox import emit_outbox
from app.messaging.retries import ProcessFailure
from app.models.orders import SimulatedPayment
from workers.common import apply_transition, process_business_event

logger = get_logger(__name__)


async def payment_effect(session, order, envelope, attempt: int) -> None:
    await asyncio.sleep(settings.SIM_PAYMENT_DELAY_SECONDS)

    mode = settings.PAYMENT_FAILURE_MODE
    if mode == "always_fail" or (mode == "twice_then_succeed" and attempt < 3):
        raise ProcessFailure(f"Simulated payment failure (attempt {attempt})")

    session.add(SimulatedPayment(order_id=order.id, status="SUCCESS", attempts=attempt))
    await apply_transition(session, order, envelope, "PAID", "Payment captured (simulated)")
    await emit_outbox(
        session,
        new_envelope(
            EVENT_ORDER_PAID,
            order_id=order.id,
            order_version=order.version,
            correlation_id=envelope.correlation_id,
            causation_id=envelope.event_id,
            data={"amount_minor": order.total_minor, "currency": order.currency},
        ),
    )


async def handle(envelope, attempt: int) -> None:
    await process_business_event("payment-worker", envelope, attempt, payment_effect)


def main() -> None:
    setup_logging()
    asyncio.run(
        EventConsumer("payment-worker", "payment.queue", handle).run()
    )


if __name__ == "__main__":
    main()
