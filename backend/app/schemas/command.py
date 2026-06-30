from typing import Any

from pydantic import BaseModel, Field


class DevicePanCommand(BaseModel):
    # Pan spans the full servo range (firmware SERVO_PAN_MIN/MAX_DEG = 0..180).
    angle: int = Field(ge=0, le=180)


class DeviceTiltCommand(BaseModel):
    # Tilt is mechanically limited to 60..140 on the rig (firmware SERVO_TILT_MIN/MAX_DEG);
    # match it here so the API never accepts a value the device will silently clamp.
    # The app's tilt control should constrain its slider to this range too.
    angle: int = Field(ge=60, le=140)


class DeviceCommandResult(BaseModel):
    request_id: str
    status: str
    payload: dict[str, Any] = Field(default_factory=dict)

