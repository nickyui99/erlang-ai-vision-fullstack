from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from app.schemas._datetime import UTCDatetime


class PushTokenCreate(BaseModel):
    token: str = Field(min_length=1, max_length=512)
    platform: Literal["web", "android", "ios"] = "web"


class PushTokenRead(BaseModel):
    token_id: str
    platform: str
    created_at: UTCDatetime
    updated_at: UTCDatetime
    last_used_at: UTCDatetime | None = None

    model_config = ConfigDict(from_attributes=True)
