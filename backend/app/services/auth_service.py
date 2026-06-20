from __future__ import annotations

import json
from datetime import datetime, timezone
from urllib import parse, request
from uuid import uuid4

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.user import User


GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
GOOGLE_TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"
_firebase_initialized = False


def build_google_authorization_url(state: str) -> str:
    query = parse.urlencode(
        {
            "client_id": settings.google_oauth_client_id,
            "redirect_uri": settings.google_oauth_redirect_uri,
            "response_type": "code",
            "scope": "openid email profile",
            "state": state,
            "access_type": "offline",
            "prompt": "select_account",
        }
    )
    return f"{GOOGLE_AUTH_URL}?{query}"


def _post_form_json(url: str, data: dict[str, str]) -> dict:
    encoded_data = parse.urlencode(data).encode("utf-8")
    req = request.Request(
        url,
        data=encoded_data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with request.urlopen(req, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def _get_json(url: str, params: dict[str, str]) -> dict:
    full_url = f"{url}?{parse.urlencode(params)}"
    with request.urlopen(full_url, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


async def exchange_google_code_for_profile(code: str) -> dict:
    try:
        token_response = _post_form_json(
            GOOGLE_TOKEN_URL,
            {
                "code": code,
                "client_id": settings.google_oauth_client_id,
                "client_secret": settings.google_oauth_client_secret,
                "redirect_uri": settings.google_oauth_redirect_uri,
                "grant_type": "authorization_code",
            },
        )
        id_token = token_response.get("id_token")
        if not isinstance(id_token, str) or not id_token:
            raise ValueError("Google token response did not include an ID token")

        profile = _get_json(GOOGLE_TOKENINFO_URL, {"id_token": id_token})
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "google_oauth_failed", "message": "Google OAuth verification failed"},
        ) from exc

    audience = profile.get("aud")
    if audience != settings.google_oauth_client_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_google_token", "message": "Google token audience mismatch"},
        )

    if profile.get("email_verified") not in ("true", True):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "email_not_verified", "message": "Google email must be verified"},
        )

    return profile


async def upsert_google_user(session: AsyncSession, profile: dict) -> User:
    google_sub = str(profile["sub"])
    email = str(profile["email"])
    now = datetime.now(timezone.utc)

    result = await session.execute(select(User).where(User.google_sub == google_sub))
    user = result.scalar_one_or_none()

    if user is None:
        user = User(
            user_id=f"usr_{uuid4().hex}",
            google_sub=google_sub,
            email=email,
            email_verified=True,
            display_name=profile.get("name"),
            avatar_url=profile.get("picture"),
            role="user",
            last_login_at=now,
            created_at=now,
            updated_at=now,
        )
        session.add(user)
    else:
        user.email = email
        user.email_verified = True
        user.display_name = profile.get("name")
        user.avatar_url = profile.get("picture")
        user.last_login_at = now
        user.updated_at = now

    await session.commit()
    await session.refresh(user)
    return user


def _initialize_firebase_admin() -> None:
    global _firebase_initialized
    if _firebase_initialized:
        return

    if not settings.firebase_project_id or settings.firebase_project_id == "change-me":
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"code": "firebase_not_configured", "message": "Firebase project is not configured"},
        )

    credentials_path = settings.google_application_credentials
    if not credentials_path or credentials_path == r"C:\path\to\firebase-service-account.json":
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"code": "firebase_not_configured", "message": "Firebase credentials are not configured"},
        )

    try:
        import firebase_admin
        from firebase_admin import credentials

        if not firebase_admin._apps:
            cred = credentials.Certificate(credentials_path)
            firebase_admin.initialize_app(cred, {"projectId": settings.firebase_project_id})
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"code": "firebase_init_failed", "message": "Firebase Admin SDK could not be initialized"},
        ) from exc

    _firebase_initialized = True


def verify_firebase_id_token(id_token: str) -> dict:
    _initialize_firebase_admin()

    try:
        from firebase_admin import auth

        return auth.verify_id_token(id_token)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_firebase_token", "message": "Firebase ID token is invalid or expired"},
        ) from exc


async def upsert_firebase_user(session: AsyncSession, decoded_token: dict) -> User:
    firebase_uid = str(decoded_token["uid"])
    email = decoded_token.get("email")
    if not isinstance(email, str) or not email:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "email_required", "message": "Firebase user must have an email"},
        )

    email_verified = bool(decoded_token.get("email_verified", False))
    if not email_verified:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "email_not_verified", "message": "Firebase email must be verified"},
        )

    now = datetime.now(timezone.utc)
    result = await session.execute(select(User).where(User.google_sub == firebase_uid))
    user = result.scalar_one_or_none()

    if user is None:
        user = User(
            user_id=f"usr_{uuid4().hex}",
            google_sub=firebase_uid,
            email=email,
            email_verified=email_verified,
            display_name=decoded_token.get("name"),
            avatar_url=decoded_token.get("picture"),
            role="user",
            last_login_at=now,
            created_at=now,
            updated_at=now,
        )
        session.add(user)
    else:
        user.email = email
        user.email_verified = email_verified
        user.display_name = decoded_token.get("name")
        user.avatar_url = decoded_token.get("picture")
        user.last_login_at = now
        user.updated_at = now

    await session.commit()
    await session.refresh(user)
    return user
