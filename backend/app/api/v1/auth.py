from fastapi import APIRouter, Depends, Header, HTTPException, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db_session
from app.core.config import settings
from app.core.security import create_session_token
from app.services.auth_service import (
    upsert_firebase_user,
    verify_firebase_id_token,
)


router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/firebase/login")
async def firebase_login(
    response: Response,
    authorization: str | None = Header(default=None),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "not_authenticated", "message": "Firebase ID token required"},
        )

    id_token = authorization[7:].strip()
    if not id_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "not_authenticated", "message": "Firebase ID token required"},
        )

    decoded_token = verify_firebase_id_token(id_token)
    user = await upsert_firebase_user(session, decoded_token)
    session_token = create_session_token(user.user_id)
    response.set_cookie(
        settings.session_cookie_name,
        session_token,
        max_age=settings.session_expire_minutes * 60,
        httponly=True,
        secure=settings.app_env == "production",
        samesite="lax",
    )
    return {
        "data": {
            "user_id": user.user_id,
            "email": user.email,
            "email_verified": user.email_verified,
            "display_name": user.display_name,
            "avatar_url": user.avatar_url,
            "role": user.role,
        }
    }


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(response: Response) -> None:
    response.delete_cookie(settings.session_cookie_name)
