import uuid
from datetime import datetime, timezone
from typing import Any

from pydantic import BaseModel, Field

from app.core.errors import InvalidRequestError

EXCHANGE_NAME = "quickbite.orders"
QUARANTINE_EXCHANGE = "quickbite.quarantine"
QUARANTINE_QUEUE = "quarantine.queue"
QUARANTINE_ROUTING_KEY = "quarantine"

EVENT_ORDER_CREATED = "order.created"
EVENT_ORDER_PAID = "order.paid"
EVENT_ORDER_PAYMENT_FAILED = "order.payment.failed"
EVENT_ORDER_CONFIRMED = "order.confirmed"
EVENT_ORDER_DRIVER_ASSIGNED = "order.driver.assigned"
EVENT_ORDER_FAILED = "order.failed"

SCHEMA_VERSION = "1"

# event_type -> routing key (topic). notification queue binds order.#
ROUTING_KEYS: dict[str, str] = {
    EVENT_ORDER_CREATED: "order.created",
    EVENT_ORDER_PAID: "order.paid",
    EVENT_ORDER_PAYMENT_FAILED: "order.payment.failed",
    EVENT_ORDER_CONFIRMED: "order.confirmed",
    EVENT_ORDER_DRIVER_ASSIGNED: "order.driver.assigned",
    EVENT_ORDER_FAILED: "order.failed",
}

WORKER_BINDINGS: list[tuple[str, str, str]] = [
    ("payment.queue", EVENT_ORDER_CREATED, "order.created"),
    ("restaurant.queue", EVENT_ORDER_PAID, "order.paid"),
    ("delivery.queue", EVENT_ORDER_CONFIRMED, "order.confirmed"),
    ("notification.queue", "order.#", "order.#"),
]

SUPPORTED_EVENT_TYPES = set(ROUTING_KEYS)


class EventEnvelope(BaseModel):
    event_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    schema_version: str = SCHEMA_VERSION
    event_type: str
    order_id: str
    order_version: int
    occurred_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    correlation_id: str
    causation_id: str | None = None
    data: dict[str, Any] = Field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return self.model_dump()


def parse_envelope(raw: bytes) -> EventEnvelope:
    try:
        envelope = EventEnvelope.model_validate_json(raw)
    except Exception as exc:
        raise InvalidRequestError(f"Malformed event envelope: {exc}") from exc
    if envelope.event_type not in SUPPORTED_EVENT_TYPES:
        raise InvalidRequestError(f"Unsupported event type: {envelope.event_type}")
    return envelope


def new_envelope(
    event_type: str,
    order_id: str,
    order_version: int,
    correlation_id: str,
    causation_id: str | None = None,
    data: dict[str, Any] | None = None,
) -> EventEnvelope:
    return EventEnvelope(
        event_type=event_type,
        order_id=order_id,
        order_version=order_version,
        correlation_id=correlation_id,
        causation_id=causation_id,
        data=data or {},
    )
