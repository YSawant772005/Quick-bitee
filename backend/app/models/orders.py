from datetime import datetime

from sqlalchemy import CHAR, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Order(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "orders"

    customer_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    restaurant_id: Mapped[str] = mapped_column(ForeignKey("restaurants.id"))
    status: Mapped[str] = mapped_column(String(30), default="PENDING", index=True)
    total_minor: Mapped[int] = mapped_column(Integer)
    currency: Mapped[str] = mapped_column(CHAR(3), default="INR")
    delivery_address: Mapped[str] = mapped_column(Text)
    version: Mapped[int] = mapped_column(Integer, default=1)
    failure_reason: Mapped[str | None] = mapped_column(String(500), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    items: Mapped[list["OrderItem"]] = relationship(
        back_populates="order", cascade="all, delete-orphan", lazy="selectin"
    )


class OrderItem(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "order_items"

    order_id: Mapped[str] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"), index=True
    )
    menu_item_id: Mapped[str] = mapped_column(ForeignKey("menu_items.id"))
    name_snapshot: Mapped[str] = mapped_column(String(120))
    unit_price_minor: Mapped[int] = mapped_column(Integer)
    quantity: Mapped[int] = mapped_column(Integer)
    line_total_minor: Mapped[int] = mapped_column(Integer)

    order: Mapped[Order] = relationship(back_populates="items")


class OrderStatusHistory(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "order_status_history"
    __table_args__ = (UniqueConstraint("order_id", "version", name="uq_history_order_version"),)

    order_id: Mapped[str] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"), index=True
    )
    status: Mapped[str] = mapped_column(String(30))
    version: Mapped[int] = mapped_column(Integer)
    note: Mapped[str] = mapped_column(String(500), default="")


class SimulatedPayment(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "simulated_payments"

    order_id: Mapped[str] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"), unique=True, index=True
    )
    status: Mapped[str] = mapped_column(String(20))  # SUCCESS | FAILED
    attempts: Mapped[int] = mapped_column(Integer, default=1)
    failure_reason: Mapped[str | None] = mapped_column(String(500), nullable=True)


class DriverAssignment(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "driver_assignments"

    order_id: Mapped[str] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"), unique=True, index=True
    )
    driver_name: Mapped[str] = mapped_column(String(120))
    vehicle: Mapped[str] = mapped_column(String(120), default="")
    eta_minutes: Mapped[int] = mapped_column(Integer, default=25)


class Notification(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "notifications"
    __table_args__ = (UniqueConstraint("order_id", "event_type", name="uq_notification_logical"),)

    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    order_id: Mapped[str] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"), index=True
    )
    event_type: Mapped[str] = mapped_column(String(60))
    title: Mapped[str] = mapped_column(String(200))
    message: Mapped[str] = mapped_column(Text)


class IdempotencyRecord(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "idempotency_records"
    __table_args__ = (UniqueConstraint("customer_id", "idem_key", name="uq_idem_customer_key"),)

    customer_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    idem_key: Mapped[str] = mapped_column(String(80))
    payload_hash: Mapped[str] = mapped_column(String(64))
    order_id: Mapped[str] = mapped_column(ForeignKey("orders.id"))
    response: Mapped[str] = mapped_column(Text)
