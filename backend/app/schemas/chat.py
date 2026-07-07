from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from app.schemas._datetime import UTCDatetime


ChatRole = Literal["user", "assistant", "system"]


class ChatSessionCreate(BaseModel):
    # Optionally seed the conversation with the user's first message. When
    # provided, the session title is derived from it.
    first_message: str | None = Field(default=None, min_length=1)


class ChatSendRequest(BaseModel):
    content: str = Field(min_length=1)


class ChatMessageRead(BaseModel):
    message_id: str
    session_id: str
    role: ChatRole
    content: str
    created_at: UTCDatetime

    model_config = ConfigDict(from_attributes=True)


class ChatSessionRead(BaseModel):
    session_id: str
    user_id: str
    title: str
    created_at: UTCDatetime
    updated_at: UTCDatetime

    model_config = ConfigDict(from_attributes=True)
