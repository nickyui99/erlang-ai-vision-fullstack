from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict


class ToolAuditRead(BaseModel):
    """One audited tool call (e.g. the AI agent's actions during verification)."""

    audit_id: str
    event_id: str | None = None
    device_id: str | None = None
    tool_name: str
    arguments: dict[str, Any] | None = None
    result: dict[str, Any] | None = None
    called_by: str
    timestamp: datetime

    model_config = ConfigDict(from_attributes=True)
