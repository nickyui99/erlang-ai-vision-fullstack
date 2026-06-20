from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request, Response, status
from fastapi.responses import JSONResponse, RedirectResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db_session
from app.core.config import settings
from app.core.security import (
    create_oauth_state_token,
    create_session_token,
    generate_oauth_state,
    verify_oauth_state_token,
)
from app.services.auth_service import (
    build_google_authorization_url,
    exchange_google_code_for_profile,
    upsert_firebase_user,
    upsert_google_user,
    verify_firebase_id_token,
)


router = APIRouter(prefix="/auth", tags=["auth"])
OAUTH_STATE_COOKIE = "sentineledge_oauth_state"


@router.get("/google/start")
async def google_start() -> RedirectResponse:
    if not settings.google_oauth_client_id or settings.google_oauth_client_id == "change-me":
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"code": "oauth_not_configured", "message": "Google OAuth client is not configured"},
        )

    state = generate_oauth_state()
    response = RedirectResponse(build_google_authorization_url(state), status_code=status.HTTP_302_FOUND)
    response.set_cookie(
        OAUTH_STATE_COOKIE,
        create_oauth_state_token(state),
        max_age=10 * 60,
        httponly=True,
        secure=settings.app_env == "production",
        samesite="lax",
    )
    return response


@router.get("/google/callback")
async def google_callback(
    request: Request,
    code: str = Query(...),
    state: str = Query(...),
    session: AsyncSession = Depends(get_db_session),
) -> JSONResponse:
    state_cookie = request.cookies.get(OAUTH_STATE_COOKIE)
    if not state_cookie or not verify_oauth_state_token(state_cookie, state):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_oauth_state", "message": "OAuth state is invalid or expired"},
        )

    profile = await exchange_google_code_for_profile(code)
    user = await upsert_google_user(session, profile)
    session_token = create_session_token(user.user_id)

    response = JSONResponse(
        {
            "data": {
                "user_id": user.user_id,
                "email": user.email,
                "email_verified": user.email_verified,
                "display_name": user.display_name,
                "avatar_url": user.avatar_url,
                "role": user.role,
            }
        }
    )
    response.set_cookie(
        settings.session_cookie_name,
        session_token,
        max_age=settings.session_expire_minutes * 60,
        httponly=True,
        secure=settings.app_env == "production",
        samesite="lax",
    )
    response.delete_cookie(OAUTH_STATE_COOKIE)
    return response


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
