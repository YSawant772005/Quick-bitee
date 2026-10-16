import uuid

from sqlalchemy import (
    Boolean,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Restaurant(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "restaurants"

    name: Mapped[str] = mapped_column(String(120), unique=True)
    description: Mapped[str] = mapped_column(Text, default="")
    cuisine: Mapped[str] = mapped_column(String(60), default="")
    image_url: Mapped[str] = mapped_column(String(500), default="")
    available: Mapped[bool] = mapped_column(Boolean, default=True)

    #: Demo catalogue details. The platform publishes no walk-in addresses, so
    #: the seeder stores an explicit "delivery-only" note rather than a made-up
    #: street. Never blank on seeded rows; the API still treats "" as missing.
    address: Mapped[str] = mapped_column(String(300), default="")
    opening_hours: Mapped[str] = mapped_column(String(200), default="")
    #: Estimated delivery window in minutes (seeded catalogue value).
    eta_minutes_min: Mapped[int] = mapped_column(Integer, default=25)
    eta_minutes_max: Mapped[int] = mapped_column(Integer, default=45)
    #: Star rating and review count — NULL while no review data exists.
    #: These are never fabricated; the API omits them when unset.
    rating: Mapped[float | None] = mapped_column(nullable=True)
    review_count: Mapped[int | None] = mapped_column(Integer, nullable=True)

    menu_items: Mapped[list["MenuItem"]] = relationship(back_populates="restaurant")

    #: Menu sections only (`kind == "menu"`), ordered for display.
    menu_categories: Mapped[list["Category"]] = relationship(
        back_populates="restaurant",
        cascade="all, delete-orphan",
        foreign_keys="Category.restaurant_id",
        order_by="Category.sort_order",
    )


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

    #: Every category this dish belongs to — its restaurant's menu section
    #: (exactly one, `kind == "menu"`) plus any number of global food
    #: categories (`kind == "global"`), e.g. Beverages + Smoothies + Vegetarian.
    categories: Mapped[list["Category"]] = relationship(
        secondary=lambda: MenuItemCategory.__table__,
        back_populates="items",
    )


class Category(UUIDMixin, TimestampMixin, Base):
    """A menu section (``kind="menu"``) or a global food category (``kind="global"``).

    ``restaurant_id`` is set for menu sections and NULL for global categories,
    which keeps both taxonomies in one table while still allowing a dish to
    carry multiple global categories without duplicating the dish row.
    """

    __tablename__ = "categories"
    __table_args__ = (
        Index(
            "uq_categories_global_slug",
            "kind",
            "slug",
            unique=True,
            postgresql_where=text("kind = 'global'"),
        ),
        Index(
            "uq_categories_menu_slug",
            "kind",
            "restaurant_id",
            "slug",
            unique=True,
            postgresql_where=text("kind = 'menu'"),
        ),
    )

    kind: Mapped[str] = mapped_column(String(16), default="global", index=True)
    slug: Mapped[str] = mapped_column(String(80), index=True)
    name: Mapped[str] = mapped_column(String(80))
    description: Mapped[str] = mapped_column(Text, default="")
    image_url: Mapped[str] = mapped_column(String(500), default="")
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    restaurant_id: Mapped[str | None] = mapped_column(
        ForeignKey("restaurants.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )

    restaurant: Mapped[Restaurant | None] = relationship(
        back_populates="menu_categories"
    )
    items: Mapped[list[MenuItem]] = relationship(
        secondary=lambda: MenuItemCategory.__table__,
        back_populates="categories",
    )

    @staticmethod
    def deterministic_id(kind: str, slug: str, restaurant_id: str | None = None) -> str:
        """Stable primary key so re-seeding upserts instead of duplicating."""
        return str(uuid.uuid5(uuid.NAMESPACE_URL, f"quickbite:category:{kind}:{restaurant_id or ''}:{slug}"))


class MenuItemCategory(Base):
    """Dish ↔ category membership (associative entity)."""

    __tablename__ = "menu_item_categories"
    __table_args__ = (Index("ix_menu_item_categories_category_id", "category_id"),)

    menu_item_id: Mapped[str] = mapped_column(
        ForeignKey("menu_items.id", ondelete="CASCADE"), primary_key=True
    )
    category_id: Mapped[str] = mapped_column(
        ForeignKey("categories.id", ondelete="CASCADE"), primary_key=True
    )
