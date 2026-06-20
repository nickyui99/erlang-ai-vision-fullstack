from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


DeviceHealthStatus = Literal["unknown", "online", "degraded", "offline"]


class DeviceCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    location: str | None = Field(default=None, max_length=255)


class DeviceUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    location: str | None = Field(default=None, max_length=255)


class DeviceHeartbeat(BaseModel):
    health_status: DeviceHealthStatus
    rssi: float | None = None
    fps: float | None = Field(default=None, ge=0)
    current_pan: int = Field(ge=0, le=180)


class DeviceRead(BaseModel):
    device_id: str
    user_id: str
    name: str
    location: str | None = None
    health_status: str
    rssi: float | None = None
    fps: float | None = None
    current_pan: int
    last_seen: datetime | None = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class DeviceRegistrationRead(BaseModel):
    device: DeviceRead
    edge_token: str
