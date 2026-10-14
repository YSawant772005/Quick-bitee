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


class AdminSummaryOut(BaseModel):
    total_orders: int
    by_status: dict[str, int]
    pending_outbox: int
    retry_backlog: int
    quarantine_count: int
