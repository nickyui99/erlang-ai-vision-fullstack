from datetime import datetime

from sqlalchemy import BigInteger, DateTime, ForeignKey, Index, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Clip(Base):
    __tablename__ = "clips"
    __table_args__ = (
        UniqueConstraint("device_id", "idempotency_key", name="uq_clips_device_idempotency_key"),
        Index("idx_clips_event_id", "event_id"),
        Index("idx_clips_user_id", "user_id"),
        Index("idx_clips_expires_at", "expires_at"),
    )

    clip_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    event_id: Mapped[str] = mapped_column(String(64), ForeignKey("events.event_id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[str] = mapped_column(String(64), ForeignKey("users.user_id", ondelete="CASCADE"), nullable=False)
    device_id: Mapped[str] = mapped_column(String(64), ForeignKey("devices.device_id", ondelete="CASCADE"), nullable=False)
    idempotency_key: Mapped[str | None] = mapped_column(String(255))
    storage_type: Mapped[str] = mapped_column(String(32), nullable=False)
    storage_path: Mapped[str | None] = mapped_column(Text)
    oss_object_key: Mapped[str | None] = mapped_column(Text)
    clip_type: Mapped[str] = mapped_column(String(32), nullable=False, server_default="event")
    duration_seconds: Mapped[int | None] = mapped_column(Integer)
    file_size_bytes: Mapped[int | None] = mapped_column(BigInteger)
    mime_type: Mapped[str | None] = mapped_column(String(255))
    checksum_sha256: Mapped[str | None] = mapped_column(String(64))
    status: Mapped[str] = mapped_column(String(32), nullable=False, server_default="pending_upload")
    upload_id: Mapped[str | None] = mapped_column(String(255))
    upload_started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    upload_completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    upload_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    upload_error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
