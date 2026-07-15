from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

from app.schemas._datetime import UTCDatetime


AgentState = Literal["armed", "disarmed"]


class AgentCreate(BaseModel):
    # Agents are device-independent rules; the device is bound when the agent
    # is armed. device_id remains accepted for backward compatibility.
    device_id: str | None = Field(default=None, max_length=64)
    name: str = Field(min_length=1, max_length=255)
    location: str | None = Field(default=None, max_length=255)
    nl_rule: str = Field(min_length=1)


class AgentUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    location: str | None = Field(default=None, max_length=255)
    nl_rule: str = Field(min_length=1)


class AgentAssign(BaseModel):
    device_id: str = Field(min_length=1, max_length=64)


class AgentBuilderTurn(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=4000)


class AgentBuilderRequest(BaseModel):
    messages: list[AgentBuilderTurn] = Field(min_length=1, max_length=40)


class AgentRead(BaseModel):
    agent_id: str
    user_id: str
    device_id: str | None = None
    parent_agent_id: str | None = None
    name: str
    location: str | None = None
    nl_rule: str
    compiled_prompt: str | None = None
    compiled_edge_config: dict[str, Any] | None = None
    state: str
    enabled: bool
    created_at: UTCDatetime
    updated_at: UTCDatetime

    model_config = ConfigDict(from_attributes=True)


class EdgeAgentConfigRead(BaseModel):
    agent_id: str
    device_id: str
    name: str
    nl_rule: str
    compiled_prompt: str
    state: AgentState
    compiled_edge_config: dict[str, Any]
