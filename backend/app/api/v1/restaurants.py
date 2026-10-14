from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user, page_params
from app.db.session import get_session
from app.models.catalog import MenuItem, Restaurant
from app.models.users import User
from app.schemas.catalog import MenuItemOut, RestaurantOut
from app.schemas.common import Paginated, PageParams
from app.core.errors import NotFoundError

router = APIRouter(tags=["catalog"])


@router.get("/restaurants", response_model=Paginated[RestaurantOut])
async def list_restaurants(
    search: str | None = Query(default=None, max_length=120),
    category: str | None = Query(default=None, max_length=60),
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Paginated[RestaurantOut]:
    query = select(Restaurant).where(Restaurant.available.is_(True))
    count_query = select(func.count()).select_from(Restaurant).where(Restaurant.available.is_(True))
    if search:
        like = f"%{search}%"
        query = query.where(Restaurant.name.ilike(like))
        count_query = count_query.where(Restaurant.name.ilike(like))
    if category:
        query = query.where(Restaurant.cuisine == category)
        count_query = count_query.where(Restaurant.cuisine == category)
    total = (await session.execute(count_query)).scalar_one()
    rows = (
        await session.execute(
            query.order_by(Restaurant.name).offset((params.page - 1) * params.page_size).limit(params.page_size)
        )
    ).scalars().all()
    return Paginated(
        items=[RestaurantOut.model_validate(r) for r in rows],
        page=params.page,
        page_size=params.page_size,
        total=total,
    )


@router.get("/restaurants/{restaurant_id}/menu", response_model=Paginated[MenuItemOut])
async def list_menu(
    restaurant_id: str,
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Paginated[MenuItemOut]:
    restaurant = (
        await session.execute(select(Restaurant).where(Restaurant.id == restaurant_id))
    ).scalar_one_or_none()
    if restaurant is None:
        raise NotFoundError("Restaurant not found.")
    total = (
        await session.execute(
            select(func.count()).select_from(MenuItem).where(MenuItem.restaurant_id == restaurant_id)
        )
    ).scalar_one()
    rows = (
        await session.execute(
            select(MenuItem)
            .where(MenuItem.restaurant_id == restaurant_id)
            .order_by(MenuItem.name)
            .offset((params.page - 1) * params.page_size)
            .limit(params.page_size)
        )
    ).scalars().all()
    return Paginated(
        items=[MenuItemOut.model_validate(r) for r in rows],
        page=params.page,
        page_size=params.page_size,
        total=total,
    )
