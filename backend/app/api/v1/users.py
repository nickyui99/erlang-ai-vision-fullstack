from fastapi import APIRouter, Depends

from app.api.deps import get_current_user
from app.models.user import User
from app.schemas.user import UserRead


router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me")
async def me(current_user: User = Depends(get_current_user)) -> dict:
    return {"data": UserRead.model_validate(current_user).model_dump(mode="json")}
