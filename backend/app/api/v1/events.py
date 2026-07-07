from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db_session
from app.models.clip import Clip
from app.models.event import Event
from app.models.tool_audit import ToolAudit
from app.models.user import User
from app.schemas.event import EventRead
from app.schemas.media import ClipRead
from app.schemas.tool import ToolAuditRead


router = APIRouter(prefix="/events", tags=["events"])


@router.get("")
async def list_events(
    device_id: str | None = None,
    agent_id: str | None = None,
    status_filter: str | None = Query(default=None, alias="status"),
    severity: str | None = None,
    limit: int = Query(default=50, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    query = select(Event).where(Event.user_id == current_user.user_id)
    if device_id:
        query = query.where(Event.device_id == device_id)
    if agent_id:
        query = query.where(Event.agent_id == agent_id)
    if status_filter:
        query = query.where(Event.status == status_filter)
    if severity:
        query = query.where(Event.severity == severity)

    result = await session.execute(query.order_by(Event.timestamp.desc()).limit(limit))
    events = [EventRead.model_validate(event).model_dump(mode="json") for event in result.scalars()]
    return {"data": events}


@router.get("/{event_id}")
async def get_event(
    event_id: str,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    event = await _get_owned_event(session, current_user.user_id, event_id)
    return {"data": EventRead.model_validate(event).model_dump(mode="json")}


@router.get("/{event_id}/clips")
async def list_event_clips(
    event_id: str,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    await _get_owned_event(session, current_user.user_id, event_id)
    result = await session.execute(
        select(Clip)
        .where(Clip.event_id == event_id, Clip.user_id == current_user.user_id, Clip.deleted_at.is_(None))
        .order_by(Clip.created_at.desc())
    )
    clips = [ClipRead.model_validate(clip).model_dump(mode="json") for clip in result.scalars()]
    return {"data": clips}


@router.get("/{event_id}/audit")
async def list_event_audit(
    event_id: str,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    """Tool-call trail for an event — e.g. the AI agent's snapshot/pan/read
    actions during verification. Ordered oldest-first to read as a timeline."""
    await _get_owned_event(session, current_user.user_id, event_id)
    result = await session.execute(
        select(ToolAudit)
        .where(ToolAudit.event_id == event_id, ToolAudit.user_id == current_user.user_id)
        .order_by(ToolAudit.timestamp.asc())
    )
    audits = [ToolAuditRead.model_validate(audit).model_dump(mode="json") for audit in result.scalars()]
    return {"data": audits}


async def _get_owned_event(session: AsyncSession, user_id: str, event_id: str) -> Event:
    result = await session.execute(select(Event).where(Event.event_id == event_id, Event.user_id == user_id))
    event = result.scalar_one_or_none()
    if event is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Event was not found"},
        )
    return event
