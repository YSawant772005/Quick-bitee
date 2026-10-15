from fastapi import APIRouter, Depends, Header, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import get_current_user, page_params
from app.core.errors import ForbiddenError, InvalidRequestError, NotFoundError
from app.db.session import get_session
from app.models.catalog import Restaurant
from app.models.orders import DriverAssignment, Order, OrderStatusHistory, Notification
from app.models.users import User
from app.schemas.common import Paginated, PageParams
from app.schemas.orders import (
    HistoryEntryOut,
    NotificationOut,
    OrderAcceptedResponse,
    OrderCreateRequest,
    OrderDetailOut,
    OrderItemOut,
    OrderListItemOut,
)
from app.services.catalog_service import item_image_map as _item_image_map
from app.services.order_service import create_order

router = APIRouter(tags=["orders"])


async def _owned_order(
    session: AsyncSession, order_id: str, user: User
) -> Order:
    order = (
        await session.execute(
            select(Order).where(Order.id == order_id).options(selectinload(Order.items))
        )
    ).scalar_one_or_none()
    if order is None or (order.customer_id != user.id and user.role != "admin"):
        raise NotFoundError("Order not found.")
    return order


@router.post(
    "/orders",
    response_model=OrderAcceptedResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
async def place_order(
    payload: OrderCreateRequest,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> OrderAcceptedResponse:
    if current_user.role != "customer":
        raise ForbiddenError("Only customers can place orders.")
    if not idempotency_key or len(idempotency_key) < 8 or len(idempotency_key) > 80:
        raise InvalidRequestError("A valid Idempotency-Key header (8-80 chars) is required.")
    result = await create_order(session, current_user.id, payload, idempotency_key)
    await session.commit()
    return result


@router.get("/orders", response_model=Paginated[OrderListItemOut])
async def list_orders(
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Paginated[OrderListItemOut]:
    base = select(Order).where(Order.customer_id == current_user.id)
    from sqlalchemy import func

    total = (
        await session.execute(
            select(func.count()).select_from(Order).where(Order.customer_id == current_user.id)
        )
    ).scalar_one()
    rows = (
        await session.execute(
            base.order_by(Order.created_at.desc())
            .options(selectinload(Order.items))
            .offset((params.page - 1) * params.page_size)
            .limit(params.page_size)
        )
    ).scalars().all()
    items: list[OrderListItemOut] = []
    image_by_item = await _item_image_map(
        session, [i.menu_item_id for order in rows for i in order.items]
    )
    for order in rows:
        restaurant = (
            await session.execute(select(Restaurant).where(Restaurant.id == order.restaurant_id))
        ).scalar_one_or_none()
        names = ", ".join(item.name_snapshot for item in order.items[:3])
        if len(order.items) > 3:
            names += f" +{len(order.items) - 3} more"
        items.append(
            OrderListItemOut(
                id=order.id,
                status=order.status,
                total_minor=order.total_minor,
                currency=order.currency,
                created_at=order.created_at,
                restaurant_name=restaurant.name if restaurant else "",
                item_summary=names,
                thumbnail_url=(
                    image_by_item.get(order.items[0].menu_item_id, "") if order.items else ""
                ),
            )
        )
    return Paginated(items=items, page=params.page, page_size=params.page_size, total=total)


@router.get("/orders/{order_id}", response_model=OrderDetailOut)
async def get_order(
    order_id: str,
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> OrderDetailOut:
    order = await _owned_order(session, order_id, current_user)
    restaurant = (
        await session.execute(select(Restaurant).where(Restaurant.id == order.restaurant_id))
    ).scalar_one_or_none()
    driver = (
        await session.execute(select(DriverAssignment).where(DriverAssignment.order_id == order.id))
    ).scalar_one_or_none()
    image_by_item = await _item_image_map(session, [item.menu_item_id for item in order.items])
    return OrderDetailOut(
        id=order.id,
        restaurant_id=order.restaurant_id,
        restaurant_name=restaurant.name if restaurant else "",
        status=order.status,
        total_minor=order.total_minor,
        currency=order.currency,
        delivery_address=order.delivery_address,
        version=order.version,
        failure_reason=order.failure_reason,
        driver=driver,
        items=[
            OrderItemOut(
                menu_item_id=item.menu_item_id,
                name=item.name_snapshot,
                unit_price_minor=item.unit_price_minor,
                quantity=item.quantity,
                line_total_minor=item.line_total_minor,
                image_url=image_by_item.get(item.menu_item_id, ""),
            )
            for item in order.items
        ],
        created_at=order.created_at,
        updated_at=order.updated_at,
    )


@router.get("/orders/{order_id}/history", response_model=Paginated[HistoryEntryOut])
async def get_order_history(
    order_id: str,
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Paginated[HistoryEntryOut]:
    await _owned_order(session, order_id, current_user)
    from sqlalchemy import func

    total = (
        await session.execute(
            select(func.count())
            .select_from(OrderStatusHistory)
            .where(OrderStatusHistory.order_id == order_id)
        )
    ).scalar_one()
    rows = (
        await session.execute(
            select(OrderStatusHistory)
            .where(OrderStatusHistory.order_id == order_id)
            .order_by(OrderStatusHistory.version)
            .offset((params.page - 1) * params.page_size)
            .limit(params.page_size)
        )
    ).scalars().all()
    return Paginated(
        items=[HistoryEntryOut.model_validate(r) for r in rows],
        page=params.page,
        page_size=params.page_size,
        total=total,
    )


@router.get("/orders/{order_id}/notifications", response_model=Paginated[NotificationOut])
async def get_order_notifications(
    order_id: str,
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Paginated[NotificationOut]:
    await _owned_order(session, order_id, current_user)
    from sqlalchemy import func

    total = (
        await session.execute(
            select(func.count()).select_from(Notification).where(Notification.order_id == order_id)
        )
    ).scalar_one()
    rows = (
        await session.execute(
            select(Notification)
            .where(Notification.order_id == order_id)
            .order_by(Notification.created_at.desc())
            .offset((params.page - 1) * params.page_size)
            .limit(params.page_size)
        )
    ).scalars().all()
    return Paginated(
        items=[NotificationOut.model_validate(r) for r in rows],
        page=params.page,
        page_size=params.page_size,
        total=total,
    )
