"""add restaurant detail columns (address, hours, ETA) + nullable rating

Revision ID: c5a1e2b47d90
Revises: b7d2f9c41a03
Create Date: 2026-10-16 09:00:00.000000

Purely additive: six new columns on ``restaurants``; no existing column or row
is modified except a one-time backfill that fills the new *empty* columns with
sensible demo catalogue values. ``rating`` and ``review_count`` stay NULL —
there is no review data in this platform and none is invented.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "c5a1e2b47d90"
down_revision: Union[str, None] = "b7d2f9c41a03"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

#: Safe, non-real fallbacks: this is a demo platform with no walk-in kitchens
#: and no published addresses, so we say exactly that instead of inventing one.
DEMO_ADDRESS = "Delivery-only demo kitchen - no walk-in address"
DEMO_HOURS = "11:00 AM - 11:00 PM, daily"


def upgrade() -> None:
    op.add_column(
        "restaurants",
        sa.Column("address", sa.String(length=300), nullable=False, server_default=""),
    )
    op.add_column(
        "restaurants",
        sa.Column("opening_hours", sa.String(length=200), nullable=False, server_default=""),
    )
    op.add_column(
        "restaurants",
        sa.Column("eta_minutes_min", sa.Integer(), nullable=False, server_default="25"),
    )
    op.add_column(
        "restaurants",
        sa.Column("eta_minutes_max", sa.Integer(), nullable=False, server_default="45"),
    )
    # Deliberately nullable: no ratings exist yet and none may be fabricated.
    op.add_column("restaurants", sa.Column("rating", sa.Float(), nullable=True))
    op.add_column("restaurants", sa.Column("review_count", sa.Integer(), nullable=True))

    # One-time backfill for rows that predate this migration.
    bind = op.get_bind()
    bind.execute(
        sa.text("UPDATE restaurants SET address = :addr WHERE address = ''"),
        {"addr": DEMO_ADDRESS},
    )
    bind.execute(
        sa.text("UPDATE restaurants SET opening_hours = :hours WHERE opening_hours = ''"),
        {"hours": DEMO_HOURS},
    )
    # Deterministic, name-derived estimate so every kitchen differs slightly but
    # the same run always produces the same numbers (20-35 min, +15 max).
    bind.execute(
        sa.text(
            "UPDATE restaurants "
            "SET eta_minutes_min = 20 + (abs(hashtext(name)) % 4) * 5, "
            "eta_minutes_max = 20 + (abs(hashtext(name)) % 4) * 5 + 15 "
            "WHERE eta_minutes_min = 25 AND eta_minutes_max = 45"
        )
    )


def downgrade() -> None:
    op.drop_column("restaurants", "review_count")
    op.drop_column("restaurants", "rating")
    op.drop_column("restaurants", "eta_minutes_max")
    op.drop_column("restaurants", "eta_minutes_min")
    op.drop_column("restaurants", "opening_hours")
    op.drop_column("restaurants", "address")
