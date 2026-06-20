from datetime import datetime

from sqlalchemy import BigInteger, DateTime, ForeignKey, Index, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Recording(Base):
    __tablename__ = "recordings"
    __table_args__ = (
        Index("idx_recordings_user_start", "user_id", "start_time"),
    )

    recording_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(64), ForeignKey("users.user_id", ondelete="CASCADE"), nullable=False)
    device_id: Mapped[str] = mapped_column(String(64), ForeignKey("devices.device_id", ondelete="CASCADE"), nullable=False)
    start_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    end_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    storage_type: Mapped[str] = mapped_column(String(32), nullable=False)
    storage_path: Mapped[str | None] = mapped_column(Text)
    oss_object_key: Mapped[str | None] = mapped_column(Text)
    duration_seconds: Mapped[int | None] = mapped_column(Integer)
    file_size_bytes: Mapped[int | None] = mapped_column(BigInteger)
    mime_type: Mapped[str | None] = mapped_column(String(255))
    checksum_sha256: Mapped[str | None] = mapped_column(String(64))
    status: Mapped[str] = mapped_column(String(32), nullable=False, server_default="local_only")
    upload_id: Mapped[str | None] = mapped_column(String(255))
    upload_started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    upload_completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    upload_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    upload_error: Mapped[str | None] = mapped_column(Text)
    retention_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
