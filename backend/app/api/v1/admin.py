"""Admin console API.

Everything here is administrator-only (``require_admin``) and additive: the
existing ``GET /admin/orders`` and ``GET /admin/summary`` keep their original
required fields, so older clients keep working.

Design rules applied throughout:
- Revenue counts only "realised sale" statuses (PAID/CONFIRMED/DRIVER_ASSIGNED);
  pending, failed and cancelled orders never contribute revenue.
- Every metric is scoped to the requested period (``date_from``/``date_to``,
  inclusive ISO days) when one is supplied; without a period the metrics are
  all-time, matching the original behaviour.
- Aggregations are grouped in SQL and lookups are joined, not looped over.
"""

from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import page_params, require_admin
from app.core.errors import InvalidRequestError, NotFoundError
from app.db.session import get_session
from app.models.catalog import MenuItem, Restaurant
from app.models.messaging import OutboxEvent, QuarantineRecord, RetryJob
from app.models.orders import (
    DriverAssignment,
    Order,
    OrderItem,
    OrderStatusHistory,
    SimulatedPayment,
)
from app.models.users import User
from app.schemas.admin import (
    AdminAnalyticsOut,
    AdminCustomerOut,
    AdminDeliveryOut,
    AdminMenuItemOut,
    AdminOrderDetailOut,
    AdminOrderListItemOut,
    AdminRestaurantOut,
    AnalyticsBucketOut,
    MenuItemUpdateRequest,
    RestaurantUpdateRequest,
)
from app.schemas.common import Paginated, PageParams
from app.schemas.orders import (
    AdminSummaryOut,
    AttentionItem,
    DailyRevenue,
    DriverOut,
    HistoryEntryOut,
    MetricDelta,
    OrderItemOut,
    PeriodComparison,
    TopDish,
    TopRestaurant,
)
from app.services.catalog_service import item_image_map

router = APIRouter(prefix="/admin", tags=["admin"])

# Orders that represent realised sales (used for revenue and AOV).
SALES_STATUSES = ("PAID", "CONFIRMED", "DRIVER_ASSIGNED")
# Orders that ended without delivering.
FAILED_STATUSES = ("PAYMENT_FAILED", "FAILED")
# Orders that are still moving through the state machine.
NON_TERMINAL_STATUSES = ("PENDING", "PAID", "CONFIRMED")

# Default series length when no period is supplied (kept for compatibility).
DEFAULT_SERIES_DAYS = 14
# Guardrail so a huge custom range cannot build an unbounded series.
MAX_SERIES_DAYS = 366

WEEKDAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

ORDER_SORTS = {
    "created_desc": (Order.created_at.desc(),),
    "created_asc": (Order.created_at.asc(),),
    "total_desc": (Order.total_minor.desc(),),
    "total_asc": (Order.total_minor.asc(),),
}


# --------------------------------------------------------------------------
# Period helpers
# --------------------------------------------------------------------------


def _parse_day(value: str | None, field: str) -> date | None:
    if value is None or value == "":
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        raise InvalidRequestError(f"{field} must be an ISO date (YYYY-MM-DD).")


def _period_bounds(
    date_from: str | None, date_to: str | None
) -> tuple[datetime | None, datetime | None]:
    """Inclusive ISO days -> [start, end) UTC datetimes."""
    start_day = _parse_day(date_from, "date_from")
    end_day = _parse_day(date_to, "date_to")
    if start_day and end_day and end_day < start_day:
        raise InvalidRequestError("date_to must not be before date_from.")
    start = (
        datetime.combine(start_day, datetime.min.time(), tzinfo=timezone.utc)
        if start_day
        else None
    )
    end = (
        datetime.combine(end_day + timedelta(days=1), datetime.min.time(), tzinfo=timezone.utc)
        if end_day
        else None
    )
    return start, end


def _created_filters(start: datetime | None, end: datetime | None) -> list:
    filters: list = []
    if start is not None:
        filters.append(Order.created_at >= start)
    if end is not None:
        filters.append(Order.created_at < end)
    return filters


def _delta(current: int, previous: int) -> MetricDelta:
    # change_pct stays None when there is no previous data, so the UI never
    # shows a fabricated percentage.
    pct = round((current - previous) / previous * 100, 1) if previous > 0 else None
    return MetricDelta(current=current, previous=previous, change_pct=pct)


def _bucket_days(rows: list[DailyRevenue], granularity: str) -> list[DailyRevenue]:
    """Roll daily rows up into week/month buckets (in Python, over <=366 rows).

    Day-granularity rows are returned unchanged, so the default response shape
    is identical to the original endpoint.
    """
    if granularity == "day" or not rows:
        return rows
    buckets: dict[str, list[int]] = {}
    for row in rows:
        try:
            day = date.fromisoformat(row.date)
        except ValueError:
            continue
        if granularity == "week":
            key = (day - timedelta(days=day.weekday())).isoformat()
        else:
            key = day.replace(day=1).isoformat()
        agg = buckets.setdefault(key, [0, 0])
        agg[0] += row.orders
        agg[1] += row.revenue_minor
    return [
        DailyRevenue(date=key, orders=value[0], revenue_minor=value[1])
        for key, value in sorted(buckets.items())
    ]


async def _revenue_series(
    session: AsyncSession,
    granularity: str,
    start: datetime | None,
    end: datetime | None,
) -> list[DailyRevenue]:
    """Real daily revenue for realised-sale orders, bucketed as requested."""
    if start is None and end is None:
        # Backward-compatible default: a rolling window of recent days.
        start = datetime.now(timezone.utc) - timedelta(days=DEFAULT_SERIES_DAYS - 1)
    if start is not None and end is not None:
        span_days = (end - start).days
        if span_days > MAX_SERIES_DAYS:
            raise InvalidRequestError(f"Requested range is longer than {MAX_SERIES_DAYS} days.")

    day_rows = (
        await session.execute(
            select(
                func.date(Order.created_at).label("day"),
                func.count().label("orders"),
                func.coalesce(func.sum(Order.total_minor), 0).label("revenue"),
            )
            .where(Order.status.in_(SALES_STATUSES), *_created_filters(start, end))
            .group_by(func.date(Order.created_at))
        )
    ).all()
    by_day = {str(row.day): (row.orders, int(row.revenue)) for row in day_rows}

    if end is None:
        last_day = date.today()
    else:
        last_day = (end - timedelta(days=1)).date()
    if start is None:
        first_day = last_day - timedelta(days=DEFAULT_SERIES_DAYS - 1)
    else:
        first_day = start.date()
    if last_day < first_day:
        return []

    keys = [
        (first_day + timedelta(days=offset)).isoformat()
        for offset in range((last_day - first_day).days + 1)
    ]
    series = [
        DailyRevenue(
            date=key,
            orders=by_day.get(key, (0, 0))[0],
            revenue_minor=by_day.get(key, (0, 0))[1],
        )
        for key in keys
    ]
    return _bucket_days(series, granularity)


# --------------------------------------------------------------------------
# Shared row builders
# --------------------------------------------------------------------------


async def _restaurant_stats(
    session: AsyncSession, restaurant_ids: list[str]
) -> dict[str, tuple[int, int]]:
    """restaurant_id -> (order_count, revenue) on realised-sale orders."""
    if not restaurant_ids:
        return {}
    rows = (
        await session.execute(
            select(
                Order.restaurant_id,
                func.count(Order.id),
                func.coalesce(func.sum(Order.total_minor), 0),
            )
            .where(Order.restaurant_id.in_(restaurant_ids), Order.status.in_(SALES_STATUSES))
            .group_by(Order.restaurant_id)
        )
    ).all()
    return {rid: (int(count), int(revenue)) for rid, count, revenue in rows}


async def _menu_stats(
    session: AsyncSession, menu_item_ids: list[str]
) -> dict[str, tuple[int, int]]:
    """menu_item_id -> (units_sold, revenue) on realised-sale orders."""
    if not menu_item_ids:
        return {}
    rows = (
        await session.execute(
            select(
                OrderItem.menu_item_id,
                func.coalesce(func.sum(OrderItem.quantity), 0),
                func.coalesce(func.sum(OrderItem.line_total_minor), 0),
            )
            .join(Order, Order.id == OrderItem.order_id)
            .where(OrderItem.menu_item_id.in_(menu_item_ids), Order.status.in_(SALES_STATUSES))
            .group_by(OrderItem.menu_item_id)
        )
    ).all()
    return {mid: (int(qty), int(revenue)) for mid, qty, revenue in rows}


async def _menu_item_counts(
    session: AsyncSession, restaurant_ids: list[str]
) -> dict[str, tuple[int, int]]:
    """restaurant_id -> (menu_item_count, available_item_count)."""
    if not restaurant_ids:
        return {}
    rows = (
        await session.execute(
            select(
                MenuItem.restaurant_id,
                func.count(MenuItem.id),
                func.count(MenuItem.id).filter(MenuItem.available.is_(True)),
            )
            .where(MenuItem.restaurant_id.in_(restaurant_ids))
            .group_by(MenuItem.restaurant_id)
        )
    ).all()
    return {rid: (int(total), int(available)) for rid, total, available in rows}


def _restaurant_out(
    restaurant: Restaurant,
    menu_count: int = 0,
    available_count: int = 0,
    order_count: int = 0,
    revenue: int = 0,
) -> AdminRestaurantOut:
    return AdminRestaurantOut(
        id=restaurant.id,
        name=restaurant.name,
        description=restaurant.description,
        cuisine=restaurant.cuisine,
        image_url=restaurant.image_url,
        available=restaurant.available,
        menu_item_count=menu_count,
        available_item_count=available_count,
        order_count=order_count,
        revenue_minor=revenue,
    )


def _menu_item_out(
    item: MenuItem,
    restaurant_name: str = "",
    units_sold: int = 0,
    revenue: int = 0,
) -> AdminMenuItemOut:
    return AdminMenuItemOut(
        id=item.id,
        restaurant_id=item.restaurant_id,
        name=item.name,
        description=item.description,
        price_minor=item.price_minor,
        currency=item.currency,
        image_url=item.image_url,
        available=item.available,
        restaurant_name=restaurant_name,
        units_sold=units_sold,
        revenue_minor=revenue,
    )


# --------------------------------------------------------------------------
# Orders
# --------------------------------------------------------------------------


@router.get("/orders", response_model=Paginated[AdminOrderListItemOut])
async def admin_list_orders(
    status_filter: str | None = Query(default=None, alias="status", max_length=30),
    search: str | None = Query(default=None, max_length=120),
    date_from: str | None = Query(default=None),
    date_to: str | None = Query(default=None),
    sort: str = Query(default="created_desc"),
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    admin: User = Depends(require_admin),
) -> Paginated[AdminOrderListItemOut]:
    if sort not in ORDER_SORTS:
        raise InvalidRequestError(f"Unsupported sort '{sort}'.")

    start, end = _period_bounds(date_from, date_to)
    filters = _created_filters(start, end)
    if status_filter:
        filters.append(Order.status == status_filter)
    if search:
        like = f"%{search.lower()}%"
        filters.append(func.lower(Order.id).like(like) | func.lower(User.email).like(like))

    total = (
        await session.execute(
            select(func.count())
            .select_from(Order)
            .outerjoin(User, User.id == Order.customer_id)
            .where(*filters)
        )
    ).scalar_one()

    rows = (
        await session.execute(
            select(
                Order,
                User.email.label("customer_email"),
                SimulatedPayment.status.label("payment_status"),
                SimulatedPayment.attempts.label("payment_attempts"),
                Restaurant.name.label("restaurant_name"),
            )
            .outerjoin(User, User.id == Order.customer_id)
            .outerjoin(SimulatedPayment, SimulatedPayment.order_id == Order.id)
            .outerjoin(Restaurant, Restaurant.id == Order.restaurant_id)
            .where(*filters)
            .order_by(*ORDER_SORTS[sort])
            .offset((params.page - 1) * params.page_size)
            .limit(params.page_size)
            .options(selectinload(Order.items))
        )
    ).all()

    items: list[AdminOrderListItemOut] = []
    for order, customer_email, payment_status, payment_attempts, restaurant_name in rows:
        names = ", ".join(item.name_snapshot for item in order.items[:3])
        if len(order.items) > 3:
            names += f" +{len(order.items) - 3} more"
        items.append(
            AdminOrderListItemOut(
                id=order.id,
                status=order.status,
                total_minor=order.total_minor,
                currency=order.currency,
                created_at=order.created_at,
                restaurant_name=restaurant_name or "",
                item_summary=names,
                customer_id=order.customer_id,
                customer_email=customer_email or "",
                payment_status=payment_status,
                payment_attempts=payment_attempts or 0,
                item_count=len(order.items),
                updated_at=order.updated_at,
            )
        )
    return Paginated(items=items, page=params.page, page_size=params.page_size, total=total)


@router.get("/orders/{order_id}", response_model=AdminOrderDetailOut)
async def admin_get_order(
    order_id: str,
    session: AsyncSession = Depends(get_session),
    admin: User = Depends(require_admin),
) -> AdminOrderDetailOut:
    order = (
        await session.execute(
            select(Order).where(Order.id == order_id).options(selectinload(Order.items))
        )
    ).scalar_one_or_none()
    if order is None:
        raise NotFoundError("Order not found.")

    customer = (
        await session.execute(select(User).where(User.id == order.customer_id))
    ).scalar_one_or_none()
    restaurant = (
        await session.execute(select(Restaurant).where(Restaurant.id == order.restaurant_id))
    ).scalar_one_or_none()
    payment = (
        await session.execute(
            select(SimulatedPayment).where(SimulatedPayment.order_id == order.id)
        )
    ).scalar_one_or_none()
    driver = (
        await session.execute(select(DriverAssignment).where(DriverAssignment.order_id == order.id))
    ).scalar_one_or_none()
    timeline = (
        await session.execute(
            select(OrderStatusHistory)
            .where(OrderStatusHistory.order_id == order.id)
            .order_by(OrderStatusHistory.version)
        )
    ).scalars().all()
    image_by_item = await item_image_map(session, [item.menu_item_id for item in order.items])

    return AdminOrderDetailOut(
        id=order.id,
        restaurant_id=order.restaurant_id,
        restaurant_name=restaurant.name if restaurant else "",
        status=order.status,
        total_minor=order.total_minor,
        currency=order.currency,
        delivery_address=order.delivery_address,
        version=order.version,
        failure_reason=order.failure_reason,
        driver=(
            DriverOut(
                driver_name=driver.driver_name,
                vehicle=driver.vehicle,
                eta_minutes=driver.eta_minutes,
            )
            if driver
            else None
        ),
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
        customer_id=order.customer_id,
        customer_email=customer.email if customer else "",
        payment_status=payment.status if payment else None,
        payment_attempts=payment.attempts if payment else 0,
        payment_failure_reason=payment.failure_reason if payment else None,
        timeline=[
            HistoryEntryOut(
                status=row.status,
                version=row.version,
                note=row.note,
                created_at=row.created_at,
            )
            for row in timeline
        ],
    )


# --------------------------------------------------------------------------
# Summary / analytics
# --------------------------------------------------------------------------


@router.get("/summary", response_model=AdminSummaryOut)
async def admin_summary(
    date_from: str | None = Query(default=None),
    date_to: str | None = Query(default=None),
    granularity: str = Query(default="day", pattern="^(day|week|month)$"),
    session: AsyncSession = Depends(get_session),
    admin: User = Depends(require_admin),
) -> AdminSummaryOut:
    start, end = _period_bounds(date_from, date_to)
    period_filters = _created_filters(start, end)

    status_rows = (
        await session.execute(
            select(Order.status, func.count()).where(*period_filters).group_by(Order.status)
        )
    ).all()
    by_status = {status: count for status, count in status_rows}
    total_orders = sum(by_status.values())

    total_revenue = (
        await session.execute(
            select(func.coalesce(func.sum(Order.total_minor), 0)).where(
                Order.status.in_(SALES_STATUSES), *period_filters
            )
        )
    ).scalar_one()
    successful_orders = (
        await session.execute(
            select(func.count())
            .select_from(Order)
            .where(Order.status.in_(SALES_STATUSES), *period_filters)
        )
    ).scalar_one()
    failed_orders = (
        await session.execute(
            select(func.count())
            .select_from(Order)
            .where(Order.status.in_(FAILED_STATUSES), *period_filters)
        )
    ).scalar_one()
    # "Active" = distinct customers with at least one order inside the period.
    active_customers = (
        await session.execute(
            select(func.count(func.distinct(Order.customer_id))).where(*period_filters)
        )
    ).scalar_one()
    avg_order_value = int(total_revenue // successful_orders) if successful_orders else 0

    # --- Previous-period comparison (only when an explicit period is set) ---
    comparison: PeriodComparison | None = None
    if start is not None and end is not None:
        span = end - start
        prev_start, prev_end = start - span, start
        prev_filters = [Order.created_at >= prev_start, Order.created_at < prev_end]
        prev_revenue = (
            await session.execute(
                select(func.coalesce(func.sum(Order.total_minor), 0)).where(
                    Order.status.in_(SALES_STATUSES), *prev_filters
                )
            )
        ).scalar_one()
        prev_orders = (
            await session.execute(select(func.count()).select_from(Order).where(*prev_filters))
        ).scalar_one()
        prev_customers = (
            await session.execute(
                select(func.count(func.distinct(Order.customer_id))).where(*prev_filters)
            )
        ).scalar_one()
        prev_aov = int(prev_revenue // prev_orders) if prev_orders else 0
        comparison = PeriodComparison(
            date_from=start.date().isoformat(),
            date_to=(end - timedelta(days=1)).date().isoformat(),
            orders=_delta(total_orders, prev_orders),
            revenue_minor=_delta(int(total_revenue), int(prev_revenue)),
            active_customers=_delta(active_customers, prev_customers),
            avg_order_value_minor=_delta(avg_order_value, prev_aov),
        )

    # --- Series, rankings, catalogue and messaging state ---
    revenue_by_day = await _revenue_series(session, granularity, start, end)

    dish_rows = (
        await session.execute(
            select(
                OrderItem.menu_item_id,
                OrderItem.name_snapshot,
                func.coalesce(func.sum(OrderItem.quantity), 0).label("quantity"),
                func.coalesce(func.sum(OrderItem.line_total_minor), 0).label("revenue"),
                Restaurant.name.label("restaurant_name"),
                MenuItem.image_url,
            )
            .join(Order, Order.id == OrderItem.order_id)
            .join(Restaurant, Restaurant.id == Order.restaurant_id)
            .outerjoin(MenuItem, MenuItem.id == OrderItem.menu_item_id)
            .where(Order.status.in_(SALES_STATUSES), *period_filters)
            .group_by(
                OrderItem.menu_item_id,
                OrderItem.name_snapshot,
                Restaurant.name,
                MenuItem.image_url,
            )
            .order_by(func.coalesce(func.sum(OrderItem.quantity), 0).desc())
            .limit(8)
        )
    ).all()
    top_dishes = [
        TopDish(
            menu_item_id=menu_item_id,
            name=name,
            quantity=int(quantity),
            revenue_minor=int(revenue),
            image_url=image_url or "",
            restaurant_name=restaurant_name or "",
        )
        for menu_item_id, name, quantity, revenue, restaurant_name, image_url in dish_rows
    ]

    rest_rows = (
        await session.execute(
            select(
                Restaurant.id,
                Restaurant.name,
                Restaurant.image_url,
                func.count(Order.id).label("orders"),
                func.coalesce(func.sum(Order.total_minor), 0).label("revenue"),
            )
            .join(Order, Order.restaurant_id == Restaurant.id)
            .where(Order.status.in_(SALES_STATUSES), *period_filters)
            .group_by(Restaurant.id, Restaurant.name, Restaurant.image_url)
            .order_by(func.coalesce(func.sum(Order.total_minor), 0).desc())
            .limit(8)
        )
    ).all()
    top_restaurants = [
        TopRestaurant(
            restaurant_id=rid,
            name=name,
            image_url=image_url or "",
            orders=int(orders),
            revenue_minor=int(revenue),
        )
        for rid, name, image_url, orders, revenue in rest_rows
    ]

    unavailable_restaurants = (
        await session.execute(
            select(func.count()).select_from(Restaurant).where(Restaurant.available.is_(False))
        )
    ).scalar_one()
    unavailable_menu_items = (
        await session.execute(
            select(func.count()).select_from(MenuItem).where(MenuItem.available.is_(False))
        )
    ).scalar_one()
    total_customers = (
        await session.execute(
            select(func.count()).select_from(User).where(User.role == "customer")
        )
    ).scalar_one()
    active_deliveries = (
        await session.execute(
            select(func.count())
            .select_from(Order)
            .where(Order.status == "DRIVER_ASSIGNED", *period_filters)
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
    pending_outbox = (
        await session.execute(
            select(func.count()).select_from(OutboxEvent).where(OutboxEvent.status == "PENDING")
        )
    ).scalar_one()

    # Only real, non-zero conditions are listed so the panel stays calm otherwise.
    attention: list[AttentionItem] = []
    for key, label, count in [
        ("awaiting_payment", "Orders awaiting payment confirmation", by_status.get("PENDING", 0)),
        ("awaiting_confirmation", "Paid orders awaiting restaurant confirmation", by_status.get("PAID", 0)),
        ("awaiting_driver", "Confirmed orders awaiting a driver", by_status.get("CONFIRMED", 0)),
        ("out_for_delivery", "Out for delivery", by_status.get("DRIVER_ASSIGNED", 0)),
        ("payment_failed", "Payment failures to review", by_status.get("PAYMENT_FAILED", 0)),
        ("cancelled", "Cancelled orders to review", by_status.get("FAILED", 0)),
        ("unavailable_menu_items", "Menu items marked unavailable", unavailable_menu_items),
        ("unavailable_restaurants", "Restaurants closed", unavailable_restaurants),
        ("quarantine", "Messaging events quarantined", quarantine_count),
        ("retry_backlog", "Message retries scheduled", retry_backlog),
    ]:
        if count:
            attention.append(AttentionItem(key=key, label=label, count=int(count)))

    return AdminSummaryOut(
        total_orders=total_orders,
        by_status=by_status,
        pending_outbox=pending_outbox,
        retry_backlog=retry_backlog,
        quarantine_count=quarantine_count,
        currency="INR",
        total_revenue_minor=int(total_revenue),
        successful_orders=successful_orders,
        failed_orders=failed_orders,
        active_customers=active_customers,
        avg_order_value_minor=avg_order_value,
        revenue_by_day=revenue_by_day,
        top_dishes=top_dishes,
        date_from=start.date().isoformat() if start else None,
        date_to=(end - timedelta(days=1)).date().isoformat() if end else None,
        granularity=granularity,
        comparison=comparison,
        attention=attention,
        top_restaurants=top_restaurants,
        unavailable_menu_items=unavailable_menu_items,
        unavailable_restaurants=unavailable_restaurants,
        total_customers=total_customers,
        active_deliveries=active_deliveries,
        payment_failed_orders=by_status.get("PAYMENT_FAILED", 0),
    )


@router.get("/analytics", response_model=AdminAnalyticsOut)
async def admin_analytics(
    date_from: str | None = Query(default=None),
    date_to: str | None = Query(default=None),
    granularity: str = Query(default="day", pattern="^(day|week|month)$"),
    session: AsyncSession = Depends(get_session),
    admin: User = Depends(require_admin),
) -> AdminAnalyticsOut:
    start, end = _period_bounds(date_from, date_to)
    period_filters = _created_filters(start, end)

    status_rows = (
        await session.execute(
            select(Order.status, func.count()).where(*period_filters).group_by(Order.status)
        )
    ).all()
    by_status = {status: count for status, count in status_rows}

    total_revenue = (
        await session.execute(
            select(func.coalesce(func.sum(Order.total_minor), 0)).where(
                Order.status.in_(SALES_STATUSES), *period_filters
            )
        )
    ).scalar_one()
    successful = (
        by_status.get("PAID", 0) + by_status.get("CONFIRMED", 0) + by_status.get("DRIVER_ASSIGNED", 0)
    )
    failed = by_status.get("PAYMENT_FAILED", 0) + by_status.get("FAILED", 0)
    total_orders = sum(by_status.values())
    active_customers = (
        await session.execute(
            select(func.count(func.distinct(Order.customer_id))).where(*period_filters)
        )
    ).scalar_one()

    qty_sub = (
        select(
            OrderItem.order_id.label("oid"),
            func.sum(OrderItem.quantity).label("qty"),
        )
        .join(Order, Order.id == OrderItem.order_id)
        .where(*period_filters)
        .group_by(OrderItem.order_id)
        .subquery()
    )
    avg_items = (await session.execute(select(func.avg(qty_sub.c.qty)))).scalar() or 0

    weekday_rows = (
        await session.execute(
            select(
                func.extract("dow", Order.created_at).label("dow"),
                func.count().label("orders"),
                func.coalesce(func.sum(Order.total_minor), 0).label("revenue"),
            )
            .where(*period_filters)
            .group_by(func.extract("dow", Order.created_at))
        )
    ).all()
    orders_by_weekday = [
        AnalyticsBucketOut(
            label=WEEKDAY_LABELS[int(dow)],
            count=int(orders),
            revenue_minor=int(revenue),
        )
        for dow, orders, revenue in sorted(weekday_rows, key=lambda r: int(r[0]))
    ]

    hour_rows = (
        await session.execute(
            select(
                func.extract("hour", Order.created_at).label("hour"),
                func.count().label("orders"),
                func.coalesce(func.sum(Order.total_minor), 0).label("revenue"),
            )
            .where(*period_filters)
            .group_by(func.extract("hour", Order.created_at))
        )
    ).all()
    orders_by_hour = [
        AnalyticsBucketOut(
            label=f"{int(hour):02d}:00",
            count=int(orders),
            revenue_minor=int(revenue),
        )
        for hour, orders, revenue in sorted(hour_rows, key=lambda r: int(r[0]))
    ]

    rest_rows = (
        await session.execute(
            select(
                Restaurant.id,
                Restaurant.name,
                Restaurant.image_url,
                func.count(Order.id).label("orders"),
                func.coalesce(func.sum(Order.total_minor), 0).label("revenue"),
            )
            .join(Order, Order.restaurant_id == Restaurant.id)
            .where(Order.status.in_(SALES_STATUSES), *period_filters)
            .group_by(Restaurant.id, Restaurant.name, Restaurant.image_url)
            .order_by(func.coalesce(func.sum(Order.total_minor), 0).desc())
        )
    ).all()

    revenue_by_day = await _revenue_series(session, granularity, start, end)

    return AdminAnalyticsOut(
        currency="INR",
        date_from=start.date().isoformat() if start else None,
        date_to=(end - timedelta(days=1)).date().isoformat() if end else None,
        granularity=granularity,
        total_orders=total_orders,
        total_revenue_minor=int(total_revenue),
        successful_orders=successful,
        failed_orders=failed,
        avg_order_value_minor=int(total_revenue // successful) if successful else 0,
        active_customers=active_customers,
        avg_items_per_order=round(float(avg_items), 2),
        revenue_by_day=revenue_by_day,
        revenue_by_restaurant=[
            TopRestaurant(
                restaurant_id=rid,
                name=name,
                image_url=image_url or "",
                orders=int(orders),
                revenue_minor=int(revenue),
            )
            for rid, name, image_url, orders, revenue in rest_rows
        ],
        orders_by_weekday=orders_by_weekday,
        orders_by_hour=orders_by_hour,
        orders_by_status=by_status,
    )


# --------------------------------------------------------------------------
# Catalogue management
# --------------------------------------------------------------------------


@router.get("/restaurants", response_model=Paginated[AdminRestaurantOut])
async def admin_list_restaurants(
    search: str | None = Query(default=None, max_length=120),
    available: bool | None = Query(default=None),
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    admin: User = Depends(require_admin),
) -> Paginated[AdminRestaurantOut]:
    filters = []
    if search:
        like = f"%{search}%"
        filters.append(Restaurant.name.ilike(like) | Restaurant.cuisine.ilike(like))
    if available is not None:
        filters.append(Restaurant.available.is_(available))

    total = (
        await session.execute(select(func.count()).select_from(Restaurant).where(*filters))
    ).scalar_one()
    rows = (
        await session.execute(
            select(Restaurant)
            .where(*filters)
            .order_by(Restaurant.name)
            .offset((params.page - 1) * params.page_size)
            .limit(params.page_size)
        )
    ).scalars().all()

    ids = [r.id for r in rows]
    menu_counts = await _menu_item_counts(session, ids)
    stats = await _restaurant_stats(session, ids)

    items = []
    for r in rows:
        menu_count, available_count = menu_counts.get(r.id, (0, 0))
        order_count, revenue = stats.get(r.id, (0, 0))
        items.append(_restaurant_out(r, menu_count, available_count, order_count, revenue))

    return Paginated(items=items, page=params.page, page_size=params.page_size, total=total)


@router.patch("/restaurants/{restaurant_id}", response_model=AdminRestaurantOut)
async def admin_update_restaurant(
    restaurant_id: str,
    payload: RestaurantUpdateRequest,
    session: AsyncSession = Depends(get_session),
    admin: User = Depends(require_admin),
) -> AdminRestaurantOut:
    restaurant = (
        await session.execute(select(Restaurant).where(Restaurant.id == restaurant_id))
    ).scalar_one_or_none()
    if restaurant is None:
        raise NotFoundError("Restaurant not found.")

    data = payload.model_dump(exclude_unset=True)
    if "name" in data:
        clash = (
            await session.execute(
                select(Restaurant).where(
                    Restaurant.name == data["name"], Restaurant.id != restaurant_id
                )
            )
        ).scalar_one_or_none()
        if clash is not None:
            raise InvalidRequestError("Another restaurant already uses that name.")
    for field, value in data.items():
        setattr(restaurant, field, value)
    await session.commit()

    counts = await _menu_item_counts(session, [restaurant_id])
    menu_count, available_count = counts.get(restaurant_id, (0, 0))
    stats = await _restaurant_stats(session, [restaurant_id])
    order_count, revenue = stats.get(restaurant_id, (0, 0))
    return _restaurant_out(restaurant, menu_count, available_count, order_count, revenue)


@router.get("/menu-items", response_model=Paginated[AdminMenuItemOut])
async def admin_list_menu_items(
    search: str | None = Query(default=None, max_length=120),
    restaurant_id: str | None = Query(default=None),
    available: bool | None = Query(default=None),
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    admin: User = Depends(require_admin),
) -> Paginated[AdminMenuItemOut]:
    filters = []
    if search:
        filters.append(MenuItem.name.ilike(f"%{search}%"))
    if restaurant_id:
        filters.append(MenuItem.restaurant_id == restaurant_id)
    if available is not None:
        filters.append(MenuItem.available.is_(available))

    total = (
        await session.execute(select(func.count()).select_from(MenuItem).where(*filters))
    ).scalar_one()
    rows = (
        await session.execute(
            select(MenuItem, Restaurant.name.label("restaurant_name"))
            .outerjoin(Restaurant, Restaurant.id == MenuItem.restaurant_id)
            .where(*filters)
            .order_by(Restaurant.name, MenuItem.name)
            .offset((params.page - 1) * params.page_size)
            .limit(params.page_size)
        )
    ).all()

    stats = await _menu_stats(session, [item.id for item, _ in rows])
    items = []
    for item, restaurant_name in rows:
        units, revenue = stats.get(item.id, (0, 0))
        items.append(_menu_item_out(item, restaurant_name or "", units, revenue))

    return Paginated(items=items, page=params.page, page_size=params.page_size, total=total)


@router.patch("/menu-items/{item_id}", response_model=AdminMenuItemOut)
async def admin_update_menu_item(
    item_id: str,
    payload: MenuItemUpdateRequest,
    session: AsyncSession = Depends(get_session),
    admin: User = Depends(require_admin),
) -> AdminMenuItemOut:
    item = (
        await session.execute(select(MenuItem).where(MenuItem.id == item_id))
    ).scalar_one_or_none()
    if item is None:
        raise NotFoundError("Menu item not found.")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, field, value)
    await session.commit()

    restaurant = (
        await session.execute(select(Restaurant).where(Restaurant.id == item.restaurant_id))
    ).scalar_one_or_none()
    stats = await _menu_stats(session, [item.id])
    units, revenue = stats.get(item.id, (0, 0))
    return _menu_item_out(item, restaurant.name if restaurant else "", units, revenue)


# --------------------------------------------------------------------------
# Customers & deliveries
# --------------------------------------------------------------------------


@router.get("/customers", response_model=Paginated[AdminCustomerOut])
async def admin_list_customers(
    search: str | None = Query(default=None, max_length=120),
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    admin: User = Depends(require_admin),
) -> Paginated[AdminCustomerOut]:
    agg = (
        select(
            Order.customer_id.label("customer_id"),
            func.count(Order.id).label("total_orders"),
            func.count(Order.id)
            .filter(Order.status.in_(SALES_STATUSES))
            .label("successful_orders"),
            func.count(Order.id)
            .filter(Order.status.in_(NON_TERMINAL_STATUSES))
            .label("active_orders"),
            func.max(Order.created_at).label("last_order_at"),
            func.coalesce(
                func.sum(Order.total_minor).filter(Order.status.in_(SALES_STATUSES)), 0
            ).label("total_spent"),
        )
        .group_by(Order.customer_id)
        .subquery()
    )

    filters = [User.role == "customer"]
    if search:
        filters.append(User.email.ilike(f"%{search}%"))

    total = (
        await session.execute(select(func.count()).select_from(User).where(*filters))
    ).scalar_one()
    rows = (
        await session.execute(
            select(
                User,
                agg.c.total_orders,
                agg.c.successful_orders,
                agg.c.active_orders,
                agg.c.last_order_at,
                agg.c.total_spent,
            )
            .outerjoin(agg, agg.c.customer_id == User.id)
            .where(*filters)
            .order_by(User.created_at.desc())
            .offset((params.page - 1) * params.page_size)
            .limit(params.page_size)
        )
    ).all()

    items = [
        AdminCustomerOut(
            id=user.id,
            email=user.email,
            role=user.role,
            registered_at=user.created_at,
            total_orders=int(total_orders or 0),
            successful_orders=int(successful or 0),
            active_orders=int(active or 0),
            last_order_at=last_order_at,
            total_spent_minor=int(spent or 0),
        )
        for user, total_orders, successful, active, last_order_at, spent in rows
    ]
    return Paginated(items=items, page=params.page, page_size=params.page_size, total=total)


@router.get("/deliveries", response_model=Paginated[AdminDeliveryOut])
async def admin_list_deliveries(
    search: str | None = Query(default=None, max_length=120),
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    admin: User = Depends(require_admin),
) -> Paginated[AdminDeliveryOut]:
    """Live driver assignments (read-only).

    The backend has no delivery-partner registry and no assignment endpoint —
    assignments are created by the delivery worker — so this surface is
    intentionally read-only and shows the assignments that actually exist.
    """
    filters = []
    if search:
        like = f"%{search}%"
        filters.append(
            DriverAssignment.driver_name.ilike(like)
            | func.lower(Order.id).like(like.lower())
            | Restaurant.name.ilike(like)
        )

    total = (
        await session.execute(
            select(func.count())
            .select_from(DriverAssignment)
            .join(Order, Order.id == DriverAssignment.order_id)
            .outerjoin(Restaurant, Restaurant.id == Order.restaurant_id)
            .where(*filters)
        )
    ).scalar_one()

    rows = (
        await session.execute(
            select(
                DriverAssignment,
                Order.status.label("order_status"),
                Order.total_minor,
                Order.currency,
                Order.created_at,
                Order.delivery_address,
                Restaurant.name.label("restaurant_name"),
                User.email.label("customer_email"),
            )
            .join(Order, Order.id == DriverAssignment.order_id)
            .outerjoin(Restaurant, Restaurant.id == Order.restaurant_id)
            .outerjoin(User, User.id == Order.customer_id)
            .where(*filters)
            .order_by(Order.created_at.desc())
            .offset((params.page - 1) * params.page_size)
            .limit(params.page_size)
        )
    ).all()

    items = [
        AdminDeliveryOut(
            order_id=assignment.order_id,
            driver_name=assignment.driver_name,
            vehicle=assignment.vehicle,
            eta_minutes=assignment.eta_minutes,
            order_status=order_status,
            restaurant_name=restaurant_name or "",
            customer_email=customer_email or "",
            total_minor=total_minor,
            currency=currency,
            created_at=created_at,
            delivery_address=delivery_address or "",
        )
        for (
            assignment,
            order_status,
            total_minor,
            currency,
            created_at,
            delivery_address,
            restaurant_name,
            customer_email,
        ) in rows
    ]
    return Paginated(items=items, page=params.page, page_size=params.page_size, total=total)
