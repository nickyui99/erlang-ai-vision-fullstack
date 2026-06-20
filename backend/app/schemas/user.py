from datetime import datetime

from pydantic import BaseModel, ConfigDict


class UserRead(BaseModel):
    user_id: str
    email: str
    email_verified: bool
    display_name: str | None = None
    avatar_url: str | None = None
    role: str
    last_login_at: datetime | None = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)
