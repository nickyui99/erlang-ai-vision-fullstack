from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.schemas._datetime import UTCDatetime


DeviceHealthStatus = Literal["unknown", "online", "degraded", "offline"]


class DeviceCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    location: str | None = Field(default=None, max_length=255)


class CameraPreset(BaseModel):
    label: str = Field(min_length=1, max_length=40)
    pan: int = Field(ge=0, le=180)
    tilt: int = Field(ge=60, le=140)


class DeviceUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    location: str | None = Field(default=None, max_length=255)
    is_favorite: bool = False
    presets: list[CameraPreset] = Field(default_factory=list, max_length=6)
    ptz_correction_pan: int = Field(default=0, ge=-45, le=45)
    ptz_correction_tilt: int = Field(default=0, ge=-45, le=45)


class DeviceHeartbeat(BaseModel):
    health_status: DeviceHealthStatus
    rssi: float | None = None
    fps: float | None = Field(default=None, ge=0)
    current_pan: int = Field(ge=0, le=180)
    # Defaulted for backward compatibility with edges that don't report tilt yet.
    current_tilt: int = Field(default=90, ge=0, le=180)


class DeviceRead(BaseModel):
    device_id: str
    user_id: str
    name: str
    location: str | None = None
    health_status: str
    rssi: float | None = None
    fps: float | None = None
    current_pan: int
    current_tilt: int = 90
    is_favorite: bool = False
    presets: list[CameraPreset] = Field(default_factory=list)
    ptz_correction_pan: int = 0
    ptz_correction_tilt: int = 0
    control_mode: Literal["off", "auto_track", "agent"] = "off"
    last_seen: UTCDatetime | None = None
    created_at: UTCDatetime
    updated_at: UTCDatetime

    @field_validator("presets", mode="before")
    @classmethod
    def _default_presets(cls, value: object) -> object:
        return [] if value is None else value

    model_config = ConfigDict(from_attributes=True)


class DeviceRegistrationRead(BaseModel):
    device: DeviceRead
    edge_token: str


class LiveStreamUrlRead(BaseModel):
    stream_url: str
    expires_at: UTCDatetime
