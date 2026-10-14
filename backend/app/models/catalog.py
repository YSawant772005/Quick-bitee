from sqlalchemy import Boolean, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Restaurant(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "restaurants"

    name: Mapped[str] = mapped_column(String(120), unique=True)
    description: Mapped[str] = mapped_column(Text, default="")
    cuisine: Mapped[str] = mapped_column(String(60), default="")
    image_url: Mapped[str] = mapped_column(String(500), default="")
    available: Mapped[bool] = mapped_column(Boolean, default=True)

    menu_items: Mapped[list["MenuItem"]] = relationship(back_populates="restaurant")


class MenuItem(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "menu_items"

    restaurant_id: Mapped[str] = mapped_column(
        ForeignKey("restaurants.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(120))
    description: Mapped[str] = mapped_column(Text, default="")
    price_minor: Mapped[int] = mapped_column(Integer)
    currency: Mapped[str] = mapped_column(String(3), default="INR")
    image_url: Mapped[str] = mapped_column(String(500), default="")
    available: Mapped[bool] = mapped_column(Boolean, default=True)

    restaurant: Mapped[Restaurant] = relationship(back_populates="menu_items")
