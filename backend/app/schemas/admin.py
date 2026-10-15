"""Admin-console response/request models.

These extend the public catalog/order schemas with operational fields (customer,
payment state, catalogue stats) that are only ever returned to an administrator.
Existing public contracts are untouched — every new field has a default.
"""

from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.catalog import MenuItemOut, RestaurantOut
from app.schemas.orders import HistoryEntryOut, OrderDetailOut, OrderListItemOut


class AdminOrderListItemOut(OrderListItemOut):
    customer_id: str = ""
    customer_email: str = ""
    payment_status: str | None = None
    payment_attempts: int = 0
    item_count: int = 0
    updated_at: datetime | None = None


class AdminOrderDetailOut(OrderDetailOut):
    customer_id: str = ""
    customer_email: str = ""
    payment_status: str | None = None
    payment_attempts: int = 0
    payment_failure_reason: str | None = None
    timeline: list[HistoryEntryOut] = []


class AdminRestaurantOut(RestaurantOut):
    menu_item_count: int = 0
    available_item_count: int = 0
    order_count: int = 0
    revenue_minor: int = 0


class AdminMenuItemOut(MenuItemOut):
    restaurant_name: str = ""
    units_sold: int = 0
    revenue_minor: int = 0


class AdminCustomerOut(BaseModel):
    id: str
    email: str
    role: str
    registered_at: datetime
    total_orders: int = 0
    successful_orders: int = 0
    # Orders that have not reached a terminal state yet.
    active_orders: int = 0
    last_order_at: datetime | None = None
    total_spent_minor: int = 0
    currency: str = "INR"


class AdminDeliveryOut(BaseModel):
    order_id: str
    driver_name: str
    vehicle: str
    eta_minutes: int
    order_status: str
    restaurant_name: str = ""
    customer_email: str = ""
    total_minor: int
    currency: str
    created_at: datetime
    delivery_address: str = ""


class RestaurantUpdateRequest(BaseModel):
    available: bool | None = None
    name: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=2000)
    cuisine: str | None = Field(default=None, max_length=60)
    image_url: str | None = Field(default=None, max_length=500)


class MenuItemUpdateRequest(BaseModel):
    available: bool | None = None
    price_minor: int | None = Field(default=None, ge=0, le=10_000_000)
    name: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=2000)
    image_url: str | None = Field(default=None, max_length=500)


class AnalyticsBucketOut(BaseModel):
    label: str
    count: int = 0
    revenue_minor: int = 0


class AdminAnalyticsOut(BaseModel):
    """Deeper reporting for the Analytics page (all real aggregations)."""

    currency: str = "INR"
    date_from: str | None = None
    date_to: str | None = None
    granularity: str = "day"
    total_orders: int = 0
    total_revenue_minor: int = 0
    successful_orders: int = 0
    failed_orders: int = 0
    avg_order_value_minor: int = 0
    active_customers: int = 0
    avg_items_per_order: float = 0.0
    # revenue_by_day buckets are DailyRevenue (labelled by period start).
    revenue_by_day: list = []
    revenue_by_restaurant: list = []
    orders_by_weekday: list[AnalyticsBucketOut] = []
    orders_by_hour: list[AnalyticsBucketOut] = []
    orders_by_status: dict[str, int] = {}
