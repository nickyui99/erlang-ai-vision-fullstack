from __future__ import annotations

import asyncio
import time
from collections.abc import AsyncIterator

from fastapi import Cookie, Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import verify_edge_token, verify_session_token
from app.db.session import async_session_factory
from app.models.device import Device
from app.models.user import User


# Edge-token auth verifies a token against every device row with pbkdf2 (210k
# iterations) — ~0.4 s/row, several seconds across all devices. The edge calls this
# on every heartbeat (~2 s), and doing it inline on the single event loop froze the
# whole backend (command POSTs queued behind it -> multi-second latency). Cache the
# token->device_id mapping with a short TTL so steady-state auth is O(1), and run
# the cold-path scan off the event loop so even a miss doesn't block other requests.
_EDGE_AUTH_TTL_S = 300.0
_edge_auth_cache: dict[str, tuple[str, float]] = {}


def _match_edge_token(raw_token: str, rows: list[tuple[str, str]]) -> str | None:
    for device_id, token_hash in rows:
        if verify_edge_token(raw_token, token_hash):
            return device_id
    return None


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
    return await get_edge_device_from_authorization(session, authorization)


async def get_edge_device_from_authorization(session: AsyncSession, authorization: str | None) -> Device:
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

    now = time.monotonic()
    cached = _edge_auth_cache.get(raw_token)
    if cached is not None and cached[1] > now:
        device = await session.get(Device, cached[0])
        if device is not None:
            return device
        _edge_auth_cache.pop(raw_token, None)  # device gone -> drop stale entry

    # Cold path: scan rows, but run the pbkdf2 verification off the event loop so it
    # cannot block other requests (commands, the video stream, other heartbeats).
    rows = (await session.execute(select(Device.device_id, Device.edge_token_hash))).all()
    device_id = await asyncio.to_thread(_match_edge_token, raw_token, [tuple(r) for r in rows])
    if device_id is not None:
        _edge_auth_cache[raw_token] = (device_id, now + _EDGE_AUTH_TTL_S)
        device = await session.get(Device, device_id)
        if device is not None:
            return device

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail={"code": "invalid_edge_token", "message": "Edge token is invalid"},
    )
