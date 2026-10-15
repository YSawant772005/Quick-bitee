"""add categories + menu_item_categories (dish <-> category membership)

Revision ID: b7d2f9c41a03
Revises: 1c0436e4498f
Create Date: 2026-10-15 09:00:00.000000

Purely additive: no existing table, column, or row is touched, so current
restaurants, menu items, orders, and order_items keep their references.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "b7d2f9c41a03"
down_revision: Union[str, None] = "1c0436e4498f"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "categories",
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("slug", sa.String(length=80), nullable=False),
        sa.Column("name", sa.String(length=80), nullable=False),
        sa.Column("description", sa.Text(), nullable=False, server_default=""),
        sa.Column("image_url", sa.String(length=500), nullable=False, server_default=""),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("restaurant_id", sa.String(), nullable=True),
        sa.Column("id", sa.String(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["restaurant_id"], ["restaurants.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_categories_kind", "categories", ["kind"], unique=False)
    op.create_index("ix_categories_slug", "categories", ["slug"], unique=False)
    op.create_index(
        "ix_categories_restaurant_id", "categories", ["restaurant_id"], unique=False
    )
    # A global slug is globally unique...
    op.create_index(
        "uq_categories_global_slug",
        "categories",
        ["kind", "slug"],
        unique=True,
        postgresql_where=sa.text("kind = 'global'"),
    )
    # ...while a menu slug is unique only inside its own restaurant.
    op.create_index(
        "uq_categories_menu_slug",
        "categories",
        ["kind", "restaurant_id", "slug"],
        unique=True,
        postgresql_where=sa.text("kind = 'menu'"),
    )

    op.create_table(
        "menu_item_categories",
        sa.Column("menu_item_id", sa.String(), nullable=False),
        sa.Column("category_id", sa.String(), nullable=False),
        sa.ForeignKeyConstraint(
            ["menu_item_id"], ["menu_items.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["category_id"], ["categories.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("menu_item_id", "category_id"),
    )
    op.create_index(
        "ix_menu_item_categories_category_id",
        "menu_item_categories",
        ["category_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_menu_item_categories_category_id", table_name="menu_item_categories"
    )
    op.drop_table("menu_item_categories")
    op.drop_index("uq_categories_menu_slug", table_name="categories")
    op.drop_index("uq_categories_global_slug", table_name="categories")
    op.drop_index("ix_categories_restaurant_id", table_name="categories")
    op.drop_index("ix_categories_slug", table_name="categories")
    op.drop_index("ix_categories_kind", table_name="categories")
    op.drop_table("categories")
