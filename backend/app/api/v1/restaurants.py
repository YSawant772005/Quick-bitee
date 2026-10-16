from fastapi import APIRouter, Depends, Query
from sqlalchemy import case, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.sql.selectable import Subquery

from app import promotions
from app.api.dependencies import get_current_user, page_params
from app.catalog.taxonomy import NON_VEGETARIAN_SLUG, VEGETARIAN_SLUG
from app.core.errors import NotFoundError
from app.db.session import get_session
from app.models.catalog import Category, MenuItem, MenuItemCategory, Restaurant
from app.models.orders import Order, OrderItem
from app.models.users import User
from app.schemas.catalog import CategoryTagOut, DishOut, MenuItemOut, RestaurantOut
from app.schemas.common import Paginated, PageParams

router = APIRouter(tags=["catalog"])

# Orders in these states represent realised sales and are counted for the
# "popular" sort. Mirrors the admin revenue definition.
SALES_STATUSES = ("PAID", "CONFIRMED", "DRIVER_ASSIGNED")

#: Diet tags are global categories; every other tag is a cuisine/topic label.
DIET_SLUGS = (VEGETARIAN_SLUG, NON_VEGETARIAN_SLUG)

FOOD_TYPE_PATTERN = "^(all|veg|non_veg)$"
MENU_SORT_PATTERN = "^(name|price_asc|price_desc|popular|newest)$"
RESTAURANT_SORT_PATTERN = "^(name|rating|popular|eta|newest)$"


# ---------------------------------------------------------------------------
# Shared query fragments
# ---------------------------------------------------------------------------


def _dish_sales() -> Subquery:
    """Units sold per menu item (realised orders only)."""
    return (
        select(
            OrderItem.menu_item_id.label("menu_item_id"),
            func.coalesce(func.sum(OrderItem.quantity), 0).label("order_count"),
        )
        .join(Order, Order.id == OrderItem.order_id)
        .where(Order.status.in_(SALES_STATUSES))
        .group_by(OrderItem.menu_item_id)
        .subquery()
    )


def _restaurant_sales() -> Subquery:
    """Units sold per restaurant, aggregated from its menu items."""
    return (
        select(
            MenuItem.restaurant_id.label("restaurant_id"),
            func.coalesce(func.sum(OrderItem.quantity), 0).label("order_count"),
        )
        .join(OrderItem, OrderItem.menu_item_id == MenuItem.id)
        .join(Order, Order.id == OrderItem.order_id)
        .where(Order.status.in_(SALES_STATUSES))
        .group_by(MenuItem.restaurant_id)
        .subquery()
    )


def _dish_ids_with_tag(slug: str):
    """Menu item ids carrying the global/menu category ``slug``."""
    return (
        select(MenuItemCategory.menu_item_id)
        .join(Category, Category.id == MenuItemCategory.category_id)
        .where(Category.slug == slug)
    )


def _restaurant_ids_with_tag(slug: str):
    """Restaurants with at least one dish in the *global* category ``slug``.

    Scoped to global categories so a per-restaurant menu section (whose slug
    is only unique inside one kitchen) never leaks into a platform-wide filter.
    """
    return (
        select(MenuItem.restaurant_id)
        .join(MenuItemCategory, MenuItemCategory.menu_item_id == MenuItem.id)
        .join(Category, Category.id == MenuItemCategory.category_id)
        .where(Category.kind == "global", Category.slug == slug)
    )


def _is_veg(slugs: set[str]) -> bool | None:
    """Diet indicator derived from real tags; ``None`` when nothing is known."""
    if VEGETARIAN_SLUG in slugs and NON_VEGETARIAN_SLUG not in slugs:
        return True
    if NON_VEGETARIAN_SLUG in slugs and VEGETARIAN_SLUG not in slugs:
        return False
    return None


async def _tag_map(
    session: AsyncSession, menu_item_ids: list[str]
) -> dict[str, list[CategoryTagOut]]:
    """Batch-load category tags for a page of dishes (one query, no N+1)."""
    if not menu_item_ids:
        return {}
    rows = (
        await session.execute(
            select(
                MenuItemCategory.menu_item_id,
                Category.slug,
                Category.name,
                Category.kind,
            )
            .join(Category, Category.id == MenuItemCategory.category_id)
            .where(MenuItemCategory.menu_item_id.in_(menu_item_ids))
            .order_by(Category.kind.asc(), Category.name.asc())
        )
    ).all()
    tags: dict[str, list[CategoryTagOut]] = {}
    for menu_item_id, slug, name, kind in rows:
        tags.setdefault(menu_item_id, []).append(
            CategoryTagOut(slug=slug, name=name, kind=kind)
        )
    return tags


async def _dish_order_counts(
    session: AsyncSession, menu_item_ids: list[str]
) -> dict[str, int]:
    if not menu_item_ids:
        return {}
    sales = _dish_sales()
    rows = (
        await session.execute(
            select(sales.c.menu_item_id, sales.c.order_count).where(
                sales.c.menu_item_id.in_(menu_item_ids)
            )
        )
    ).all()
    return {menu_item_id: int(count or 0) for menu_item_id, count in rows}


async def _enrich_menu_items(
    session: AsyncSession, rows: list[MenuItem]
) -> list[MenuItemOut]:
    ids = [r.id for r in rows]
    tags = await _tag_map(session, ids)
    counts = await _dish_order_counts(session, ids)
    items: list[MenuItemOut] = []
    for row in rows:
        dish_tags = tags.get(row.id, [])
        items.append(
            MenuItemOut(
                id=row.id,
                restaurant_id=row.restaurant_id,
                name=row.name,
                description=row.description,
                price_minor=row.price_minor,
                currency=row.currency,
                image_url=row.image_url,
                available=row.available,
                is_veg=_is_veg({t.slug for t in dish_tags}),
                tags=dish_tags,
                order_count=counts.get(row.id, 0),
            )
        )
    return items


async def _enrich_restaurants(
    session: AsyncSession, rows: list[Restaurant]
) -> list[RestaurantOut]:
    """Attach real popularity, category labels and configured offers."""
    ids = [r.id for r in rows]
    dish_counts: dict[str, int] = {}
    order_counts: dict[str, int] = {}
    labels: dict[str, list[str]] = {}

    if ids:
        dish_counts = dict(
            (
                await session.execute(
                    select(MenuItem.restaurant_id, func.count())
                    .where(
                        MenuItem.restaurant_id.in_(ids),
                        MenuItem.available.is_(True),
                    )
                    .group_by(MenuItem.restaurant_id)
                )
            ).all()
        )
        order_counts = dict(
            (
                await session.execute(
                    select(
                        MenuItem.restaurant_id,
                        func.coalesce(func.sum(OrderItem.quantity), 0),
                    )
                    .join(OrderItem, OrderItem.menu_item_id == MenuItem.id)
                    .join(Order, Order.id == OrderItem.order_id)
                    .where(
                        MenuItem.restaurant_id.in_(ids),
                        Order.status.in_(SALES_STATUSES),
                    )
                    .group_by(MenuItem.restaurant_id)
                )
            ).all()
        )
        label_rows = (
            await session.execute(
                select(
                    MenuItem.restaurant_id,
                    Category.name,
                    Category.slug,
                    func.count().label("dish_count"),
                )
                .join(
                    MenuItemCategory,
                    MenuItemCategory.menu_item_id == MenuItem.id,
                )
                .join(Category, Category.id == MenuItemCategory.category_id)
                .where(
                    MenuItem.restaurant_id.in_(ids),
                    Category.kind == "global",
                )
                .group_by(MenuItem.restaurant_id, Category.name, Category.slug)
                .order_by(
                    MenuItem.restaurant_id,
                    # Diet labels are already covered by the veg/non-veg pill,
                    # so real cuisine/topic tags always win the 3 label slots.
                    case((Category.slug.in_(DIET_SLUGS), 1), else_=0),
                    func.count().desc(),
                    Category.name.asc(),
                )
            )
        ).all()
        for restaurant_id, name, _slug, _n in label_rows:
            bucket = labels.setdefault(restaurant_id, [])
            if len(bucket) < 3:
                bucket.append(name)

    return [
        RestaurantOut(
            id=r.id,
            name=r.name,
            description=r.description,
            cuisine=r.cuisine,
            image_url=r.image_url,
            available=r.available,
            address=r.address or "",
            opening_hours=r.opening_hours or "",
            eta_minutes_min=r.eta_minutes_min,
            eta_minutes_max=r.eta_minutes_max,
            rating=r.rating,
            review_count=r.review_count,
            order_count=int(order_counts.get(r.id, 0)),
            dish_count=int(dish_counts.get(r.id, 0)),
            categories=labels.get(r.id, []),
            offers=[o["title"] for o in promotions.offers_for_restaurant(r.id)],
        )
        for r in rows
    ]


# ---------------------------------------------------------------------------
# Catalogue
# ---------------------------------------------------------------------------


@router.get("/restaurants", response_model=Paginated[RestaurantOut])
async def list_restaurants(
    search: str | None = Query(default=None, max_length=120),
    category: str | None = Query(default=None, max_length=60),
    food_type: str | None = Query(default=None, pattern=FOOD_TYPE_PATTERN),
    sort: str = Query(default="name", pattern=RESTAURANT_SORT_PATTERN),
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Paginated[RestaurantOut]:
    """Restaurant listing with discovery filters and real popularity data.

    ``category`` matches the kitchen's cuisine *or* a global category its
    dishes carry (so "pizza" finds pizza specialists whatever they call
    themselves). ``sort=popular``/``rating``/``eta`` order by real data —
    rating stays NULL until genuine review data exists and then sorts last.
    """
    filters = [Restaurant.available.is_(True)]
    if search:
        filters.append(Restaurant.name.ilike(f"%{search}%"))
    if category:
        filters.append(
            Restaurant.cuisine.ilike(category)
            | Restaurant.id.in_(_restaurant_ids_with_tag(category))
        )
    if food_type == "veg":
        filters.append(Restaurant.id.in_(_restaurant_ids_with_tag(VEGETARIAN_SLUG)))
    elif food_type == "non_veg":
        filters.append(
            Restaurant.id.in_(_restaurant_ids_with_tag(NON_VEGETARIAN_SLUG))
        )

    total = (
        await session.execute(
            select(func.count()).select_from(Restaurant).where(*filters)
        )
    ).scalar_one()

    query = select(Restaurant).where(*filters)
    if sort == "popular":
        sales = _restaurant_sales()
        query = (
            query.outerjoin(sales, sales.c.restaurant_id == Restaurant.id).order_by(
                func.coalesce(sales.c.order_count, 0).desc(), Restaurant.name.asc()
            )
        )
    elif sort == "rating":
        # Unrated kitchens sort last instead of pretending to a score.
        query = query.order_by(
            func.coalesce(Restaurant.rating, -1).desc(), Restaurant.name.asc()
        )
    elif sort == "eta":
        query = query.order_by(Restaurant.eta_minutes_min.asc(), Restaurant.name.asc())
    elif sort == "newest":
        query = query.order_by(Restaurant.created_at.desc(), Restaurant.name.asc())
    else:
        query = query.order_by(Restaurant.name.asc())

    rows = (
        (
            await session.execute(
                query.offset((params.page - 1) * params.page_size).limit(
                    params.page_size
                )
            )
        )
        .scalars()
        .all()
    )
    items = await _enrich_restaurants(session, list(rows))
    return Paginated(
        items=items, page=params.page, page_size=params.page_size, total=total
    )


@router.get("/restaurants/{restaurant_id}", response_model=RestaurantOut)
async def get_restaurant(
    restaurant_id: str,
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> RestaurantOut:
    """Full detail payload for one restaurant (open or closed)."""
    restaurant = await session.scalar(
        select(Restaurant).where(Restaurant.id == restaurant_id)
    )
    if restaurant is None:
        raise NotFoundError("Restaurant not found.")
    return (await _enrich_restaurants(session, [restaurant]))[0]


@router.get("/restaurants/{restaurant_id}/menu", response_model=Paginated[MenuItemOut])
async def list_menu(
    restaurant_id: str,
    search: str | None = Query(default=None, max_length=120),
    food_type: str = Query(default="all", pattern=FOOD_TYPE_PATTERN),
    category: str | None = Query(default=None, max_length=60),
    sort: str = Query(default="name", pattern=MENU_SORT_PATTERN),
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Paginated[MenuItemOut]:
    """One restaurant's menu with filters that combine.

    ``search`` + ``food_type`` + ``category`` narrow the set together;
    ``sort`` orders it (``popular`` = realised units sold). Every item carries
    its category tags, a veg/non-veg indicator when the data says so (never a
    guess) and its real order count.
    """
    restaurant = (
        await session.execute(select(Restaurant).where(Restaurant.id == restaurant_id))
    ).scalar_one_or_none()
    if restaurant is None:
        raise NotFoundError("Restaurant not found.")

    filters = [MenuItem.restaurant_id == restaurant_id]
    if search:
        like = f"%{search}%"
        filters.append(
            (MenuItem.name.ilike(like)) | (MenuItem.description.ilike(like))
        )
    if food_type == "veg":
        filters.append(MenuItem.id.in_(_dish_ids_with_tag(VEGETARIAN_SLUG)))
    elif food_type == "non_veg":
        filters.append(MenuItem.id.in_(_dish_ids_with_tag(NON_VEGETARIAN_SLUG)))
    if category:
        filters.append(MenuItem.id.in_(_dish_ids_with_tag(category)))

    total = (
        await session.execute(
            select(func.count()).select_from(MenuItem).where(*filters)
        )
    ).scalar_one()

    query = select(MenuItem).where(*filters)
    if sort == "popular":
        sales = _dish_sales()
        query = query.outerjoin(sales, sales.c.menu_item_id == MenuItem.id).order_by(
            func.coalesce(sales.c.order_count, 0).desc(), MenuItem.name.asc()
        )
    elif sort == "price_asc":
        query = query.order_by(MenuItem.price_minor.asc(), MenuItem.name.asc())
    elif sort == "price_desc":
        query = query.order_by(MenuItem.price_minor.desc(), MenuItem.name.asc())
    elif sort == "newest":
        query = query.order_by(MenuItem.created_at.desc(), MenuItem.name.asc())
    else:
        query = query.order_by(MenuItem.name.asc())

    rows = (
        (
            await session.execute(
                query.offset((params.page - 1) * params.page_size).limit(
                    params.page_size
                )
            )
        )
        .scalars()
        .all()
    )
    items = await _enrich_menu_items(session, list(rows))
    return Paginated(
        items=items, page=params.page, page_size=params.page_size, total=total
    )


@router.get("/dishes", response_model=Paginated[DishOut])
async def list_dishes(
    search: str | None = Query(default=None, max_length=120),
    category: str | None = Query(default=None, max_length=60),
    food_type: str = Query(default="all", pattern=FOOD_TYPE_PATTERN),
    restaurant_id: str | None = Query(default=None, max_length=36),
    sort: str = Query(default="popular", pattern=MENU_SORT_PATTERN),
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Paginated[DishOut]:
    """Dish-first browsing across every restaurant.

    ``sort=popular`` orders by real units sold (successful orders only) and
    falls back to name when nothing has been ordered yet.
    """
    sales = _dish_sales()

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
    if food_type == "veg":
        filters.append(MenuItem.id.in_(_dish_ids_with_tag(VEGETARIAN_SLUG)))
    elif food_type == "non_veg":
        filters.append(MenuItem.id.in_(_dish_ids_with_tag(NON_VEGETARIAN_SLUG)))
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

    item_ids = [item.id for item, _restaurant_name, _count in rows]
    tag_map = await _tag_map(session, item_ids)

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
            tags=tag_map.get(item.id, []),
            is_veg=_is_veg({t.slug for t in tag_map.get(item.id, [])}),
        )
        for item, restaurant_name, order_count in rows
    ]
    return Paginated(
        items=items,
        page=params.page,
        page_size=params.page_size,
        total=total,
    )
