from typing import Any

from pydantic import BaseModel, Field


class DevicePanCommand(BaseModel):
    angle: int = Field(ge=0, le=180)


class DeviceTiltCommand(BaseModel):
    angle: int = Field(ge=0, le=180)


class DeviceCommandResult(BaseModel):
    request_id: str
    status: str
    payload: dict[str, Any] = Field(default_factory=dict)

