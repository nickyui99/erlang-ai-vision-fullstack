from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class PushTokenCreate(BaseModel):
    token: str = Field(min_length=1, max_length=512)
    platform: Literal["web", "android", "ios"] = "web"


class PushTokenRead(BaseModel):
    token_id: str
    platform: str
    created_at: datetime
    updated_at: datetime
    last_used_at: datetime | None = None

    model_config = ConfigDict(from_attributes=True)
