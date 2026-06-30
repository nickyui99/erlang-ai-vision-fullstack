"""Milestone 9 — schemas for Qwen Cloud event verification.

``VerificationRequest`` is what the backend hands the model; ``VerificationVerdict``
is the validated structure we persist into ``events.stage3_verdict``.
"""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


VerificationSeverity = Literal["low", "medium", "high", "critical"]


class VerificationRequest(BaseModel):
    """Everything the verification model needs to judge one event."""

    event_id: str
    rule: str
    compiled_prompt: str | None = None
    event_type: str
    severity: str
    summary: str | None = None
    confidence: float | None = None
    stage1_result: dict[str, Any] | None = None
    stage2_verdict: dict[str, Any] | None = None
    device_name: str
    device_location: str | None = None
    recent_events: list[dict[str, Any]] = Field(default_factory=list)
    # Reserved for 9B/9C: a base64 JPEG keyframe for multimodal verification.
    keyframe_b64: str | None = None


class VerificationVerdict(BaseModel):
    """Validated model verdict. Stored verbatim in ``events.stage3_verdict``.

    Fields are intentionally lenient (``recommended_action`` is a free string)
    so a slightly-off model reply can be repaired rather than rejected; the
    verification service normalises raw output before constructing this.
    """

    model_config = ConfigDict(extra="ignore")

    verified: bool
    confidence: float = Field(ge=0, le=1)
    severity: VerificationSeverity
    summary: str
    recommended_action: str = "notify"
    tool_requests: list[dict[str, Any]] = Field(default_factory=list)
