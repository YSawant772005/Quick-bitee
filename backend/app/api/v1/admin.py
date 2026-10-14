from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import page_params, require_admin
from app.db.session import get_session
from app.models.catalog import Restaurant
from app.models.messaging import OutboxEvent, QuarantineRecord, RetryJob
from app.models.orders import Order
from app.models.users import User
from app.schemas.common import Paginated, PageParams
from app.schemas.orders import AdminSummaryOut, OrderListItemOut

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/orders", response_model=Paginated[OrderListItemOut])
async def admin_list_orders(
    status_filter: str | None = Query(default=None, alias="status", max_length=30),
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    admin: User = Depends(require_admin),
) -> Paginated[OrderListItemOut]:
    query = select(Order)
    count_query = select(func.count()).select_from(Order)
    if status_filter:
        query = query.where(Order.status == status_filter)
        count_query = count_query.where(Order.status == status_filter)
    total = (await session.execute(count_query)).scalar_one()
    rows = (
        await session.execute(
            query.order_by(Order.created_at.desc())
            .options(selectinload(Order.items))
            .offset((params.page - 1) * params.page_size)
            .limit(params.page_size)
        )
    ).scalars().all()
    items: list[OrderListItemOut] = []
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
            )
        )
    return Paginated(items=items, page=params.page, page_size=params.page_size, total=total)


@router.get("/summary", response_model=AdminSummaryOut)
async def admin_summary(
    session: AsyncSession = Depends(get_session),
    admin: User = Depends(require_admin),
) -> AdminSummaryOut:
    status_rows = (
        await session.execute(select(Order.status, func.count()).group_by(Order.status))
    ).all()
    total_orders = sum(count for _status, count in status_rows)
    pending_outbox = (
        await session.execute(
            select(func.count()).select_from(OutboxEvent).where(OutboxEvent.status == "PENDING")
        )
    ).scalar_one()
    retry_backlog = (
        await session.execute(
            select(func.count()).select_from(RetryJob).where(RetryJob.status == "SCHEDULED")
        )
    ).scalar_one()
    quarantine_count = (
        await session.execute(select(func.count()).select_from(QuarantineRecord))
    ).scalar_one()
    return AdminSummaryOut(
        total_orders=total_orders,
        by_status={status: count for status, count in status_rows},
        pending_outbox=pending_outbox,
        retry_backlog=retry_backlog,
        quarantine_count=quarantine_count,
    )
