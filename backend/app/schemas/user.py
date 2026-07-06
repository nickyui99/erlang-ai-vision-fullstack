from pydantic import BaseModel, ConfigDict

from app.schemas._datetime import UTCDatetime


class UserRead(BaseModel):
    user_id: str
    email: str
    email_verified: bool
    display_name: str | None = None
    avatar_url: str | None = None
    role: str
    last_login_at: UTCDatetime | None = None
    created_at: UTCDatetime
    updated_at: UTCDatetime

    model_config = ConfigDict(from_attributes=True)
