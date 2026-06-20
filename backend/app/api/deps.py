from __future__ import annotations

from collections.abc import AsyncIterator

from fastapi import Cookie, Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import verify_edge_token, verify_session_token
from app.db.session import async_session_factory
from app.models.device import Device
from app.models.user import User


async def get_db_session() -> AsyncIterator[AsyncSession]:
    async with async_session_factory() as session:
        yield session


async def get_current_user(
    session: AsyncSession = Depends(get_db_session),
    session_cookie: str | None = Cookie(default=None, alias=settings.session_cookie_name),
) -> User:
    if not session_cookie:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "not_authenticated", "message": "Authentication required"},
        )

    user_id = verify_session_token(session_cookie)
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_session", "message": "Session is invalid or expired"},
        )

    user = await session.get(User, user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_session", "message": "Session user no longer exists"},
        )

    return user


async def get_edge_device(
    session: AsyncSession = Depends(get_db_session),
    authorization: str | None = Header(default=None),
) -> Device:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "not_authenticated", "message": "Edge token required"},
        )

    raw_token = authorization[7:].strip()
    if not raw_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "not_authenticated", "message": "Edge token required"},
        )

    result = await session.execute(select(Device))
    for device in result.scalars():
        if verify_edge_token(raw_token, device.edge_token_hash):
            return device

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail={"code": "invalid_edge_token", "message": "Edge token is invalid"},
    )
