from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


AgentState = Literal["armed", "disarmed"]


class AgentCreate(BaseModel):
    device_id: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=255)
    location: str | None = Field(default=None, max_length=255)
    nl_rule: str = Field(min_length=1)


class AgentUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    location: str | None = Field(default=None, max_length=255)
    nl_rule: str = Field(min_length=1)


class AgentRead(BaseModel):
    agent_id: str
    user_id: str
    device_id: str
    name: str
    location: str | None = None
    nl_rule: str
    compiled_prompt: str | None = None
    compiled_edge_config: dict[str, Any] | None = None
    state: str
    enabled: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class EdgeAgentConfigRead(BaseModel):
    agent_id: str
    device_id: str
    state: AgentState
    compiled_edge_config: dict[str, Any]
