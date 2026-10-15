from datetime import datetime

from pydantic import BaseModel, Field


class OrderItemIn(BaseModel):
    menu_item_id: str = Field(min_length=1)
    quantity: int = Field(ge=1, le=20)


class OrderCreateRequest(BaseModel):
    restaurant_id: str = Field(min_length=1)
    delivery_address: str = Field(min_length=10, max_length=500)
    items: list[OrderItemIn] = Field(min_length=1)


class OrderAcceptedResponse(BaseModel):
    order_id: str
    status: str
    total_minor: int
    currency: str
    message: str


class OrderItemOut(BaseModel):
    menu_item_id: str
    name: str
    unit_price_minor: int
    quantity: int
    line_total_minor: int
    # Resolved from the current menu item so ordered food images render on the
    # tracking screen. Empty when the menu item no longer exists.
    image_url: str = ""

    model_config = {"from_attributes": True}


class DriverOut(BaseModel):
    driver_name: str
    vehicle: str
    eta_minutes: int

    model_config = {"from_attributes": True}


class OrderListItemOut(BaseModel):
    id: str
    status: str
    total_minor: int
    currency: str
    created_at: datetime
    restaurant_name: str = ""
    item_summary: str = ""
    # Image of the first ordered dish, resolved from the menu, so order history
    # rows can show real food photography. Empty when unavailable.
    thumbnail_url: str = ""


class OrderDetailOut(BaseModel):
    id: str
    restaurant_id: str
    restaurant_name: str = ""
    status: str
    total_minor: int
    currency: str
    delivery_address: str
    version: int
    failure_reason: str | None
    driver: DriverOut | None
    items: list[OrderItemOut]
    created_at: datetime
    updated_at: datetime


class HistoryEntryOut(BaseModel):
    status: str
    version: int
    note: str
    created_at: datetime

    model_config = {"from_attributes": True}


class NotificationOut(BaseModel):
    id: str
    order_id: str
    event_type: str
    title: str
    message: str
    created_at: datetime

    model_config = {"from_attributes": True}


class DailyRevenue(BaseModel):
    date: str  # ISO date, YYYY-MM-DD
    orders: int
    revenue_minor: int


class TopDish(BaseModel):
    menu_item_id: str = ""
    name: str
    quantity: int
    revenue_minor: int
    # Added for the admin console's analytical ranking; empty when the menu item
    # no longer exists. Older clients ignore the extra keys.
    image_url: str = ""
    restaurant_name: str = ""


class TopRestaurant(BaseModel):
    restaurant_id: str
    name: str
    image_url: str = ""
    orders: int = 0
    revenue_minor: int = 0


class AttentionItem(BaseModel):
    """One real operational condition that needs a human to look at it."""

    key: str
    label: str
    count: int = 0


class MetricDelta(BaseModel):
    """A metric for the selected period plus the previous equivalent period."""

    current: int = 0
    previous: int = 0
    # Null when the previous period had no data, so the UI never shows a fake %.
    change_pct: float | None = None


class PeriodComparison(BaseModel):
    date_from: str | None = None
    date_to: str | None = None
    orders: MetricDelta = MetricDelta()
    revenue_minor: MetricDelta = MetricDelta()
    active_customers: MetricDelta = MetricDelta()
    avg_order_value_minor: MetricDelta = MetricDelta()


class AdminSummaryOut(BaseModel):
    total_orders: int
    by_status: dict[str, int]
    pending_outbox: int
    retry_backlog: int
    quarantine_count: int
    # --- Analytics (all derived from real rows; defaults keep older clients working) ---
    currency: str = "INR"
    total_revenue_minor: int = 0
    successful_orders: int = 0
    failed_orders: int = 0
    # Distinct customers with at least one order in the selected period.
    active_customers: int = 0
    avg_order_value_minor: int = 0
    revenue_by_day: list[DailyRevenue] = []
    top_dishes: list[TopDish] = []
    # --- Admin console (optional; absent periods mean "all time") ---
    date_from: str | None = None
    date_to: str | None = None
    granularity: str = "day"
    comparison: PeriodComparison | None = None
    attention: list[AttentionItem] = []
    top_restaurants: list[TopRestaurant] = []
    unavailable_menu_items: int = 0
    unavailable_restaurants: int = 0
    total_customers: int = 0
    active_deliveries: int = 0
    payment_failed_orders: int = 0
