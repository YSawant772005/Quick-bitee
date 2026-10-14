from datetime import datetime

from sqlalchemy import JSON, DateTime, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDMixin


class ProcessedEvent(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "processed_events"
    __table_args__ = (UniqueConstraint("consumer_name", "event_id", name="uq_processed_consumer_event"),)

    consumer_name: Mapped[str] = mapped_column(String(120))
    event_id: Mapped[str] = mapped_column(String(64), index=True)


class OutboxEvent(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "outbox_events"

    event_type: Mapped[str] = mapped_column(String(60), index=True)
    routing_key: Mapped[str] = mapped_column(String(60))
    payload: Mapped[dict] = mapped_column(JSON)
    status: Mapped[str] = mapped_column(String(20), default="PENDING", index=True)  # PENDING | SENT
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    next_retry_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    lease_owner: Mapped[str | None] = mapped_column(String(80), nullable=True)
    lease_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class RetryJob(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "retry_jobs"

    event_id: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    queue_name: Mapped[str] = mapped_column(String(120))
    routing_key: Mapped[str] = mapped_column(String(60), default="")
    envelope: Mapped[dict] = mapped_column(JSON)
    attempts: Mapped[int] = mapped_column(Integer, default=0)  # redeliveries after initial
    max_attempts: Mapped[int] = mapped_column(Integer, default=3)
    next_attempt_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    status: Mapped[str] = mapped_column(String(20), default="SCHEDULED", index=True)  # SCHEDULED | DONE | EXHAUSTED


class QuarantineRecord(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "quarantine_records"

    event_id: Mapped[str] = mapped_column(String(64), index=True)
    queue_name: Mapped[str] = mapped_column(String(120), default="")
    reason: Mapped[str] = mapped_column(String(200))
    envelope: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    raw_payload: Mapped[str | None] = mapped_column(Text, nullable=True)
