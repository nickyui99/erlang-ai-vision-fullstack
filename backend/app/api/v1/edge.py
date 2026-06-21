from __future__ import annotations

from datetime import UTC, datetime, timedelta
import secrets

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db_session, get_edge_device
from app.models.agent import Agent
from app.models.clip import Clip
from app.models.device import Device
from app.models.event import Event
from app.models.recording import Recording
from app.schemas.agent import EdgeAgentConfigRead
from app.schemas.device import DeviceHeartbeat, DeviceRead
from app.schemas.event import EdgeEventCreate, EventRead
from app.schemas.media import (
    ClipRead,
    ClipUploadUrlRead,
    EdgeClipComplete,
    EdgeClipUploadCreate,
    EdgeRecordingCreate,
    RecordingRead,
)
from app.core.config import settings
from app.services.media_url_service import media_url_service


router = APIRouter(prefix="/edge", tags=["edge"])


def _new_event_id() -> str:
    return f"evt_{secrets.token_urlsafe(18)}"


def _new_clip_id() -> str:
    return f"clip_{secrets.token_urlsafe(18)}"


def _new_recording_id() -> str:
    return f"rec_{secrets.token_urlsafe(18)}"


@router.post("/heartbeat")
async def edge_heartbeat(
    payload: DeviceHeartbeat,
    edge_device: Device = Depends(get_edge_device),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    edge_device.health_status = payload.health_status
    edge_device.rssi = payload.rssi
    edge_device.fps = payload.fps
    edge_device.current_pan = payload.current_pan
    edge_device.last_seen = datetime.now(UTC)
    edge_device.updated_at = edge_device.last_seen
    await session.commit()
    await session.refresh(edge_device)
    return {"data": DeviceRead.model_validate(edge_device).model_dump(mode="json")}


@router.get("/agents/active")
async def active_agent_configs(
    edge_device: Device = Depends(get_edge_device),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    result = await session.execute(
        select(Agent)
        .where(
            Agent.device_id == edge_device.device_id,
            Agent.user_id == edge_device.user_id,
            Agent.enabled.is_(True),
            Agent.state == "armed",
        )
        .order_by(Agent.created_at.desc())
    )
    configs = [
        EdgeAgentConfigRead(
            agent_id=agent.agent_id,
            device_id=agent.device_id,
            state="armed",
            compiled_edge_config=agent.compiled_edge_config or {},
        ).model_dump(mode="json")
        for agent in result.scalars()
    ]
    return {"data": configs}


@router.post("/events", status_code=status.HTTP_201_CREATED)
async def create_edge_event(
    payload: EdgeEventCreate,
    response: Response,
    edge_device: Device = Depends(get_edge_device),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    existing = await _get_event_by_idempotency(session, edge_device.device_id, payload.idempotency_key)
    if existing is not None:
        response.status_code = status.HTTP_200_OK
        return {"data": EventRead.model_validate(existing).model_dump(mode="json")}

    agent = await _get_edge_owned_agent(session, edge_device, payload.agent_id)
    event_id = payload.event_id or _new_event_id()
    if await session.get(Event, event_id) is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "event_conflict", "message": "Event ID already exists"},
        )

    now = datetime.now(UTC)
    event = Event(
        event_id=event_id,
        user_id=edge_device.user_id,
        agent_id=agent.agent_id,
        device_id=edge_device.device_id,
        idempotency_key=payload.idempotency_key,
        timestamp=payload.timestamp,
        event_type=payload.event_type,
        stage1_result=payload.stage1_result,
        stage2_verdict=payload.stage2_verdict,
        stage3_verdict=payload.stage3_verdict,
        severity=payload.severity,
        confidence=payload.confidence,
        summary=payload.summary,
        degraded=payload.degraded,
        status=payload.status,
        created_at=now,
        updated_at=now,
    )
    session.add(event)
    await session.commit()
    await session.refresh(event)
    return {"data": EventRead.model_validate(event).model_dump(mode="json")}


@router.post("/clips/upload-url", status_code=status.HTTP_201_CREATED)
async def create_clip_upload_url(
    payload: EdgeClipUploadCreate,
    response: Response,
    edge_device: Device = Depends(get_edge_device),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    event = await _get_edge_owned_event(session, edge_device, payload.event_id)
    existing = await _get_clip_by_idempotency(session, edge_device.device_id, payload.idempotency_key)
    if existing is not None:
        response.status_code = status.HTTP_200_OK
        if not existing.oss_object_key or not existing.upload_expires_at:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={"code": "clip_conflict", "message": "Existing clip is missing upload metadata"},
            )
        upload_url, _ = media_url_service.upload_url(existing.oss_object_key)
        data = ClipUploadUrlRead(
            clip_id=existing.clip_id,
            upload_url=upload_url,
            oss_object_key=existing.oss_object_key,
            upload_expires_at=existing.upload_expires_at,
            clip=ClipRead.model_validate(existing),
        )
        return {"data": data.model_dump(mode="json")}

    now = datetime.now(UTC)
    clip_id = _new_clip_id()
    oss_object_key = media_url_service.event_clip_object_key(
        user_id=edge_device.user_id,
        device_id=edge_device.device_id,
        event_id=event.event_id,
        clip_id=clip_id,
        mime_type=payload.mime_type,
        clip_type=payload.clip_type,
    )
    upload_url, upload_expires_at = media_url_service.upload_url(oss_object_key)
    clip = Clip(
        clip_id=clip_id,
        event_id=event.event_id,
        user_id=edge_device.user_id,
        device_id=edge_device.device_id,
        idempotency_key=payload.idempotency_key,
        storage_type="pending_upload",
        oss_object_key=oss_object_key,
        clip_type=payload.clip_type,
        duration_seconds=payload.duration_seconds,
        file_size_bytes=payload.file_size_bytes,
        mime_type=payload.mime_type,
        checksum_sha256=payload.checksum_sha256,
        status="pending_upload",
        upload_id=f"upl_{secrets.token_urlsafe(18)}",
        upload_started_at=now,
        upload_expires_at=upload_expires_at,
        expires_at=now + timedelta(days=settings.media_retention_days),
        created_at=now,
        updated_at=now,
    )
    session.add(clip)
    await session.commit()
    await session.refresh(clip)
    data = ClipUploadUrlRead(
        clip_id=clip.clip_id,
        upload_url=upload_url,
        oss_object_key=oss_object_key,
        upload_expires_at=upload_expires_at,
        clip=ClipRead.model_validate(clip),
    )
    return {"data": data.model_dump(mode="json")}


@router.post("/clips/{clip_id}/complete")
async def complete_clip_upload(
    clip_id: str,
    payload: EdgeClipComplete,
    edge_device: Device = Depends(get_edge_device),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    result = await session.execute(
        select(Clip).where(
            Clip.clip_id == clip_id,
            Clip.device_id == edge_device.device_id,
            Clip.user_id == edge_device.user_id,
        )
    )
    clip = result.scalar_one_or_none()
    if clip is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Clip was not found"},
        )
    if clip.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Clip was not found"},
        )

    now = datetime.now(UTC)
    clip.file_size_bytes = payload.file_size_bytes if payload.file_size_bytes is not None else clip.file_size_bytes
    clip.checksum_sha256 = payload.checksum_sha256 or clip.checksum_sha256
    clip.storage_type = "oss"
    clip.status = "available"
    clip.upload_completed_at = now
    clip.updated_at = now
    await session.commit()
    await session.refresh(clip)
    return {"data": ClipRead.model_validate(clip).model_dump(mode="json")}


@router.post("/recordings", status_code=status.HTTP_201_CREATED)
async def create_edge_recording(
    payload: EdgeRecordingCreate,
    edge_device: Device = Depends(get_edge_device),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    recording_id = payload.recording_id or _new_recording_id()
    if await session.get(Recording, recording_id) is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "recording_conflict", "message": "Recording ID already exists"},
        )
    now = datetime.now(UTC)
    recording = Recording(
        recording_id=recording_id,
        user_id=edge_device.user_id,
        device_id=edge_device.device_id,
        start_time=payload.start_time,
        end_time=payload.end_time,
        storage_type=payload.storage_type,
        storage_path=payload.storage_path,
        oss_object_key=payload.oss_object_key,
        duration_seconds=payload.duration_seconds,
        file_size_bytes=payload.file_size_bytes,
        mime_type=payload.mime_type,
        checksum_sha256=payload.checksum_sha256,
        status=payload.status,
        retention_until=now + timedelta(hours=settings.daily_recording_retention_hours),
        created_at=now,
        updated_at=now,
    )
    session.add(recording)
    await session.commit()
    await session.refresh(recording)
    return {"data": RecordingRead.model_validate(recording).model_dump(mode="json")}


async def _get_edge_owned_agent(session: AsyncSession, edge_device: Device, agent_id: str) -> Agent:
    result = await session.execute(
        select(Agent).where(
            Agent.agent_id == agent_id,
            Agent.device_id == edge_device.device_id,
            Agent.user_id == edge_device.user_id,
        )
    )
    agent = result.scalar_one_or_none()
    if agent is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Agent was not found"},
        )
    return agent


async def _get_edge_owned_event(session: AsyncSession, edge_device: Device, event_id: str) -> Event:
    result = await session.execute(
        select(Event).where(
            Event.event_id == event_id,
            Event.device_id == edge_device.device_id,
            Event.user_id == edge_device.user_id,
        )
    )
    event = result.scalar_one_or_none()
    if event is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Event was not found"},
        )
    return event


async def _get_event_by_idempotency(session: AsyncSession, device_id: str, idempotency_key: str) -> Event | None:
    result = await session.execute(
        select(Event).where(Event.device_id == device_id, Event.idempotency_key == idempotency_key)
    )
    return result.scalar_one_or_none()


async def _get_clip_by_idempotency(session: AsyncSession, device_id: str, idempotency_key: str) -> Clip | None:
    result = await session.execute(select(Clip).where(Clip.device_id == device_id, Clip.idempotency_key == idempotency_key))
    return result.scalar_one_or_none()
