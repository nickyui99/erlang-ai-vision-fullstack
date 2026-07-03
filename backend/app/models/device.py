from datetime import datetime

from sqlalchemy import JSON, Boolean, CheckConstraint, DateTime, Float, ForeignKey, Index, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Device(Base):
    __tablename__ = "devices"
    __table_args__ = (
        CheckConstraint("current_pan >= 0 AND current_pan <= 180", name="ck_devices_current_pan_range"),
        CheckConstraint("current_tilt >= 0 AND current_tilt <= 180", name="ck_devices_current_tilt_range"),
        Index("idx_devices_user_id", "user_id"),
    )

    device_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(64), ForeignKey("users.user_id", ondelete="CASCADE"), nullable=False)
    edge_token_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    location: Mapped[str | None] = mapped_column(String(255))
    health_status: Mapped[str] = mapped_column(String(32), nullable=False, server_default="unknown")
    rssi: Mapped[float | None] = mapped_column(Float)
    fps: Mapped[float | None] = mapped_column(Float)
    # SG90 two-axis gimbal: pan (horizontal servo) and tilt (vertical servo),
    # each 0–180°, centered at 90°.
    current_pan: Mapped[int] = mapped_column(Integer, nullable=False, server_default="90")
    current_tilt: Mapped[int] = mapped_column(Integer, nullable=False, server_default="90")
    is_favorite: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="0")
    presets: Mapped[list[dict] | None] = mapped_column(JSON, default=list)
    ptz_correction_pan: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    ptz_correction_tilt: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    last_seen: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())

