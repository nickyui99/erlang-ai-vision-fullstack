from typing import Any, Literal

from pydantic import BaseModel, Field


class DevicePanCommand(BaseModel):
    # Pan spans the full servo range (firmware SERVO_PAN_MIN/MAX_DEG = 0..180).
    angle: int = Field(ge=0, le=180)


class DeviceTiltCommand(BaseModel):
    # Tilt is mechanically limited to 60..140 on the rig (firmware SERVO_TILT_MIN/MAX_DEG);
    # match it here so the API never accepts a value the device will silently clamp.
    # The app's tilt control should constrain its slider to this range too.
    angle: int = Field(ge=60, le=140)


class DeviceControlCommand(BaseModel):
    action: Literal[
        "recording",
        "audio_mute",
        "talk",
        "alarm",
        "fill_light",
        "resolution",
    ]
    enabled: bool | None = None
    resolution: Literal["auto", "360p", "720p", "1080p"] | None = None

    def command_payload(self) -> dict[str, Any]:
        payload: dict[str, Any] = {"action": self.action}
        if self.enabled is not None:
            payload["enabled"] = self.enabled
        if self.resolution is not None:
            payload["resolution"] = self.resolution
        return payload


class DeviceControlModeCommand(BaseModel):
    # Per-camera autonomous-control mode. Kept in lockstep with the edge's CONTROL_MODES and the
    # Device.control_mode column. Mutually exclusive: only one controller owns the servo at a time.
    mode: Literal["off", "auto_track", "agent"]


class DeviceCommandResult(BaseModel):
    request_id: str
    status: str
    payload: dict[str, Any] = Field(default_factory=dict)

