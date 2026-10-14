import hashlib
import json

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import ConflictError, InvalidRequestError, NotFoundError
from app.core.logging import get_logger
from app.domain.events import EVENT_ORDER_CREATED, new_envelope
from app.messaging.outbox import emit_outbox
from app.models.catalog import MenuItem, Restaurant
from app.models.orders import (
    IdempotencyRecord,
    Order,
    OrderItem,
    OrderStatusHistory,
)
from app.schemas.orders import OrderAcceptedResponse, OrderCreateRequest

logger = get_logger(__name__)


def canonical_payload_hash(payload: OrderCreateRequest) -> str:
    raw = json.dumps(payload.model_dump(), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


async def create_order(
    session: AsyncSession,
    customer_id: str,
    payload: OrderCreateRequest,
    idempotency_key: str,
) -> OrderAcceptedResponse:
    payload_hash = canonical_payload_hash(payload)

    existing = await session.execute(
        select(IdempotencyRecord)
        .where(
            IdempotencyRecord.customer_id == customer_id,
            IdempotencyRecord.idem_key == idempotency_key,
        )
        .with_for_update()
    )
    record = existing.scalar_one_or_none()
    if record is not None:
        return _replay(record, payload_hash)

    restaurant = (
        await session.execute(
            select(Restaurant).where(
                Restaurant.id == payload.restaurant_id, Restaurant.available.is_(True)
            )
        )
    ).scalar_one_or_none()
    if restaurant is None:
        raise NotFoundError("Restaurant not found or unavailable.")

    item_ids = [item.menu_item_id for item in payload.items]
    if len(set(item_ids)) != len(item_ids):
        raise InvalidRequestError("Duplicate menu items in request; merge quantities instead.")

    rows = (
        await session.execute(
            select(MenuItem)
            .where(MenuItem.id.in_(item_ids), MenuItem.restaurant_id == payload.restaurant_id)
            .with_for_update()
        )
    ).scalars().all()
    by_id = {item.id: item for item in rows}
    missing = [i for i in item_ids if i not in by_id]
    if missing:
        raise InvalidRequestError("Some menu items do not belong to this restaurant.", {"ids": missing})

    order = Order(
        customer_id=customer_id,
        restaurant_id=payload.restaurant_id,
        status="PENDING",
        total_minor=0,
        currency="INR",
        delivery_address=payload.delivery_address,
        version=1,
    )
    session.add(order)
    await session.flush()

    total = 0
    for line in payload.items:
        menu_item = by_id[line.menu_item_id]
        if not menu_item.available:
            raise InvalidRequestError(f"Menu item '{menu_item.name}' is currently unavailable.")
        line_total = menu_item.price_minor * line.quantity
        total += line_total
        session.add(
            OrderItem(
                order_id=order.id,
                menu_item_id=menu_item.id,
                name_snapshot=menu_item.name,
                unit_price_minor=menu_item.price_minor,
                quantity=line.quantity,
                line_total_minor=line_total,
            )
        )
    order.total_minor = total
    session.add(OrderStatusHistory(order_id=order.id, status="PENDING", version=1, note="Order accepted"))

    response = OrderAcceptedResponse(
        order_id=order.id,
        status="PENDING",
        total_minor=total,
        currency="INR",
        message="Order accepted and queued for processing.",
    )
    session.add(
        IdempotencyRecord(
            customer_id=customer_id,
            idem_key=idempotency_key,
            payload_hash=payload_hash,
            order_id=order.id,
            response=response.model_dump_json(),
        )
    )

    envelope = new_envelope(
        EVENT_ORDER_CREATED,
        order_id=order.id,
        order_version=1,
        correlation_id=order.id,
        data={
            "restaurant_id": payload.restaurant_id,
            "total_minor": total,
            "currency": "INR",
            "item_count": len(payload.items),
        },
    )
    await emit_outbox(session, envelope)

    try:
        await session.flush()
    except IntegrityError:
        # Concurrent submission with the same key won the unique constraint.
        await session.rollback()
        existing = await session.execute(
            select(IdempotencyRecord)
            .where(
                IdempotencyRecord.customer_id == customer_id,
                IdempotencyRecord.idem_key == idempotency_key,
            )
        )
        record = existing.scalar_one()
        return _replay(record, payload_hash)

    logger.info("order created", extra={"order_id": order.id})
    return response


def _replay(record: IdempotencyRecord, payload_hash: str) -> OrderAcceptedResponse:
    if record.payload_hash != payload_hash:
        raise ConflictError(
            "Idempotency key was already used with a different payload.",
            {"idempotency_key": record.idem_key},
        )
    return OrderAcceptedResponse.model_validate_json(record.response)
