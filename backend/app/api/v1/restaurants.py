from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user, page_params
from app.db.session import get_session
from app.models.catalog import MenuItem, Restaurant
from app.models.orders import Order, OrderItem
from app.models.users import User
from app.schemas.catalog import DishOut, MenuItemOut, RestaurantOut
from app.schemas.common import Paginated, PageParams
from app.core.errors import NotFoundError

router = APIRouter(tags=["catalog"])

# Orders in these states represent realised sales and are counted for the
# "popular" dish sort. Mirrors the admin revenue definition.
SALES_STATUSES = ("PAID", "CONFIRMED", "DRIVER_ASSIGNED")


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


@router.get("/dishes", response_model=Paginated[DishOut])
async def list_dishes(
    search: str | None = Query(default=None, max_length=120),
    category: str | None = Query(default=None, max_length=60),
    restaurant_id: str | None = Query(default=None, max_length=36),
    sort: str = Query(default="popular", pattern="^(popular|name|price_asc|price_desc|newest)$"),
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Paginated[DishOut]:
    """Dish-first browsing across every restaurant.

    ``sort=popular`` orders by real units sold (successful orders only) and
    falls back to name when nothing has been ordered yet.
    """
    sales = (
        select(
            OrderItem.menu_item_id.label("menu_item_id"),
            func.coalesce(func.sum(OrderItem.quantity), 0).label("order_count"),
        )
        .join(Order, Order.id == OrderItem.order_id)
        .where(Order.status.in_(SALES_STATUSES))
        .group_by(OrderItem.menu_item_id)
        .subquery()
    )

    from app.models.catalog import Category, MenuItemCategory

    filters = [MenuItem.available.is_(True), Restaurant.available.is_(True)]
    if search:
        like = f"%{search}%"
        filters.append((MenuItem.name.ilike(like)) | (Restaurant.name.ilike(like)))
    if category:
        # Filter by global category tag via menu_item_categories -> categories
        filters.append(
            MenuItem.id.in_(
                select(MenuItemCategory.menu_item_id)
                .join(Category, Category.id == MenuItemCategory.category_id)
                .where(Category.kind == "global", Category.slug == category)
            )
        )
    if restaurant_id:
        filters.append(MenuItem.restaurant_id == restaurant_id)

    count_query = (
        select(func.count())
        .select_from(MenuItem)
        .join(Restaurant, Restaurant.id == MenuItem.restaurant_id)
        .where(*filters)
    )
    total = (await session.execute(count_query)).scalar_one()

    query = (
        select(
            MenuItem,
            Restaurant.name.label("restaurant_name"),
            func.coalesce(sales.c.order_count, 0).label("order_count"),
        )
        .join(Restaurant, Restaurant.id == MenuItem.restaurant_id)
        .outerjoin(sales, sales.c.menu_item_id == MenuItem.id)
        .where(*filters)
    )
    if sort == "popular":
        query = query.order_by(func.coalesce(sales.c.order_count, 0).desc(), MenuItem.name)
    elif sort == "price_asc":
        query = query.order_by(MenuItem.price_minor.asc(), MenuItem.name)
    elif sort == "price_desc":
        query = query.order_by(MenuItem.price_minor.desc(), MenuItem.name)
    elif sort == "newest":
        query = query.order_by(MenuItem.created_at.desc(), MenuItem.name)
    else:
        query = query.order_by(MenuItem.name)

    rows = (
        await session.execute(
            query.offset((params.page - 1) * params.page_size).limit(params.page_size)
        )
    ).all()

    items = [
        DishOut(
            id=item.id,
            restaurant_id=item.restaurant_id,
            name=item.name,
            description=item.description,
            price_minor=item.price_minor,
            currency=item.currency,
            image_url=item.image_url,
            available=item.available,
            restaurant_name=restaurant_name,
            order_count=int(order_count or 0),
        )
        for item, restaurant_name, order_count in rows
    ]
    return Paginated(
        items=items,
        page=params.page,
        page_size=params.page_size,
        total=total,
    )
