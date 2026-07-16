from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, JSON, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class ToolAudit(Base):
    __tablename__ = "tool_audit"
    __table_args__ = (
        Index("idx_tool_audit_user_timestamp", "user_id", "timestamp"),
        Index("idx_tool_audit_event_user_timestamp", "event_id", "user_id", "timestamp"),
    )

    audit_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    event_id: Mapped[str | None] = mapped_column(String(64), ForeignKey("events.event_id", ondelete="SET NULL"))
    user_id: Mapped[str] = mapped_column(String(64), ForeignKey("users.user_id", ondelete="CASCADE"), nullable=False)
    device_id: Mapped[str | None] = mapped_column(String(64), ForeignKey("devices.device_id", ondelete="SET NULL"))
    tool_name: Mapped[str] = mapped_column(String(128), nullable=False)
    arguments: Mapped[dict | None] = mapped_column(JSON)
    result: Mapped[dict | None] = mapped_column(JSON)
    called_by: Mapped[str] = mapped_column(String(64), nullable=False)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
