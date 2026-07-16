from __future__ import annotations

import logging
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.user import User


_logger = logging.getLogger(__name__)

_firebase_initialized = False


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

        return auth.verify_id_token(id_token, clock_skew_seconds=10)
    except Exception as exc:
        _logger.warning(
            "Firebase ID token verification failed: %s: %s",
            exc.__class__.__name__,
            exc,
        )
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

    def _apply(u: User) -> None:
        u.email = email
        u.email_verified = email_verified
        u.display_name = decoded_token.get("name")
        u.avatar_url = decoded_token.get("picture")
        u.last_login_at = now
        u.updated_at = now

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
        _apply(user)

    try:
        await session.commit()
    except IntegrityError:
        # A concurrent first-login for the same google_sub won the insert race
        # (e.g. a double-fired sign-in). Load the row it created and update that
        # one instead of failing this request with a 500.
        await session.rollback()
        result = await session.execute(select(User).where(User.google_sub == firebase_uid))
        user = result.scalar_one_or_none()
        if user is None:
            raise
        _apply(user)
        await session.commit()
    await session.refresh(user)
    return user

