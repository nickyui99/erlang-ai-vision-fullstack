from datetime import datetime

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Index, JSON, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Event(Base):
    __tablename__ = "events"
    __table_args__ = (
        UniqueConstraint("device_id", "idempotency_key", name="uq_events_device_idempotency_key"),
        Index("idx_events_user_timestamp", "user_id", "timestamp"),
        Index("idx_events_device_timestamp", "device_id", "timestamp"),
        Index("idx_events_status", "status"),
    )

    event_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(64), ForeignKey("users.user_id", ondelete="CASCADE"), nullable=False)
    agent_id: Mapped[str] = mapped_column(String(64), ForeignKey("agents.agent_id", ondelete="CASCADE"), nullable=False)
    device_id: Mapped[str] = mapped_column(String(64), ForeignKey("devices.device_id", ondelete="CASCADE"), nullable=False)
    idempotency_key: Mapped[str] = mapped_column(String(255), nullable=False)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    event_type: Mapped[str] = mapped_column(String(64), nullable=False)
    stage1_result: Mapped[dict | None] = mapped_column(JSON)
    stage2_verdict: Mapped[dict | None] = mapped_column(JSON)
    stage3_verdict: Mapped[dict | None] = mapped_column(JSON)
    severity: Mapped[str] = mapped_column(String(32), nullable=False)
    confidence: Mapped[float | None] = mapped_column(Float)
    summary: Mapped[str | None] = mapped_column(Text)
    degraded: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="0")
    status: Mapped[str] = mapped_column(String(32), nullable=False, server_default="candidate")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
