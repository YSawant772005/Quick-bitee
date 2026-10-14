from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import get_current_user, page_params, require_admin
from app.db.session import get_session
from app.models.catalog import Restaurant
from app.models.messaging import OutboxEvent, QuarantineRecord, RetryJob
from app.models.orders import Notification, Order
from app.models.users import User
from app.schemas.common import Paginated, PageParams
from app.schemas.orders import AdminSummaryOut, NotificationOut, OrderListItemOut

router = APIRouter(tags=["notifications"])


@router.get("/notifications", response_model=Paginated[NotificationOut])
async def list_notifications(
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Paginated[NotificationOut]:
    total = (
        await session.execute(
            select(func.count()).select_from(Notification).where(Notification.user_id == current_user.id)
        )
    ).scalar_one()
    rows = (
        await session.execute(
            select(Notification)
            .where(Notification.user_id == current_user.id)
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
