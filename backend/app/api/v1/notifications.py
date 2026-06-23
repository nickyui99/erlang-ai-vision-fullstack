from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db_session
from app.models.push_token import PushToken
from app.models.user import User
from app.schemas.notification import PushTokenCreate, PushTokenRead


router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.post("/tokens", status_code=status.HTTP_201_CREATED)
async def register_push_token(
    payload: PushTokenCreate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    """Register (or refresh) an FCM token for the current user.

    Tokens are globally unique. If the token already exists it is re-pointed to
    the current user and touched, so a client re-registering is idempotent.
    """
    now = datetime.now(UTC)
    result = await session.execute(select(PushToken).where(PushToken.token == payload.token))
    token = result.scalar_one_or_none()

    if token is None:
        token = PushToken(
            token_id=f"ptk_{uuid4().hex}",
            user_id=current_user.user_id,
            token=payload.token,
            platform=payload.platform,
            created_at=now,
            updated_at=now,
            last_used_at=now,
        )
        session.add(token)
    else:
        token.user_id = current_user.user_id
        token.platform = payload.platform
        token.updated_at = now
        token.last_used_at = now

    await session.commit()
    await session.refresh(token)
    return {"data": PushTokenRead.model_validate(token).model_dump(mode="json")}


@router.delete("/tokens/{token}", status_code=status.HTTP_204_NO_CONTENT, response_class=Response)
async def deregister_push_token(
    token: str,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> Response:
    """Remove an FCM token (e.g. on logout). No error if it is already gone."""
    result = await session.execute(
        select(PushToken).where(
            PushToken.token == token, PushToken.user_id == current_user.user_id
        )
    )
    existing = result.scalar_one_or_none()
    if existing is not None:
        await session.delete(existing)
        await session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
