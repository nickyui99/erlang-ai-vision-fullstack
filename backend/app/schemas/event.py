from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

from app.schemas._datetime import UTCDatetime


EventSeverity = Literal["low", "medium", "high", "critical"]
EventStatus = Literal["candidate", "verified", "dismissed", "false_positive"]


class EdgeEventCreate(BaseModel):
    event_id: str | None = Field(default=None, max_length=64)
    agent_id: str = Field(min_length=1, max_length=64)
    timestamp: UTCDatetime
    event_type: str = Field(min_length=1, max_length=64)
    stage1_result: dict[str, Any] | None = None
    stage2_verdict: dict[str, Any] | None = None
    stage3_verdict: dict[str, Any] | None = None
    severity: EventSeverity
    confidence: float | None = Field(default=None, ge=0, le=1)
    summary: str | None = None
    degraded: bool = False
    idempotency_key: str = Field(min_length=1, max_length=255)
    status: EventStatus = "candidate"


class EventRead(BaseModel):
    event_id: str
    user_id: str
    agent_id: str
    device_id: str
    idempotency_key: str
    timestamp: UTCDatetime
    event_type: str
    stage1_result: dict[str, Any] | None = None
    stage2_verdict: dict[str, Any] | None = None
    stage3_verdict: dict[str, Any] | None = None
    severity: str
    confidence: float | None = None
    summary: str | None = None
    degraded: bool
    status: str
    created_at: UTCDatetime
    updated_at: UTCDatetime

    model_config = ConfigDict(from_attributes=True)
