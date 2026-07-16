from __future__ import annotations

from datetime import UTC, datetime, timedelta
import secrets

from fastapi import APIRouter, BackgroundTasks, Body, Depends, Header, HTTPException, Response, WebSocket, WebSocketDisconnect, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db_session, get_edge_device, get_edge_device_from_authorization
from app.db.session import async_session_factory
from app.models.agent import Agent
from app.models.clip import Clip
from app.models.device import Device
from app.models.event import Event
from app.models.recording import Recording
from app.models.tool_audit import ToolAudit
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
from app.services import alert_service
from app.services import verification_service
from app.services.camera_control_service import decide_camera_control
from app.services.media_url_service import media_url_service
from app.services.edge_command_hub import edge_command_hub
from app.services.realtime_bus import realtime_bus
from app.services.video_stream_broker import video_stream_broker


router = APIRouter(prefix="/edge", tags=["edge"])


def _new_event_id() -> str:
    return f"evt_{secrets.token_urlsafe(18)}"


def _new_clip_id() -> str:
    return f"clip_{secrets.token_urlsafe(18)}"


def _new_recording_id() -> str:
    return f"rec_{secrets.token_urlsafe(18)}"


def _new_audit_id() -> str:
    return f"aud_{secrets.token_urlsafe(18)}"


@router.websocket("/ws")
async def edge_websocket(
    websocket: WebSocket,
    authorization: str | None = Header(default=None),
) -> None:
    # Authenticate with a short-lived session, released immediately — a WS lives
    # for hours, and holding the pooled connection open (idle-in-transaction) for
    # that whole time would exhaust the small pool once a few cameras connect.
    try:
        async with async_session_factory() as session:
            edge_device = await get_edge_device_from_authorization(session, authorization)
    except HTTPException:
        await websocket.close(code=1008)
        return

    await websocket.accept()
    await edge_command_hub.connect(edge_device.device_id, websocket)
    try:
        while True:
            message = await websocket.receive_json()
            if message.get("type") == "response.command_result":
                await edge_command_hub.handle_result(message)
    except WebSocketDisconnect:
        pass
    except ValueError:
        await websocket.close(code=1003)
    finally:
        # Always drop the hub entry, even on an unexpected error, so a stale
        # connection can't linger and misroute commands.
        await edge_command_hub.disconnect(edge_device.device_id, websocket)


@router.websocket("/stream")
async def edge_stream_ingest(
    websocket: WebSocket,
    authorization: str | None = Header(default=None),
) -> None:
    """Receive a push video stream from an edge device as binary JPEG frames.

    Each WebSocket message is one full JPEG frame. The frames are fanned out to
    browser viewers as MJPEG by the device stream endpoint.
    """
    # Short-lived auth session (see edge_websocket): a stream socket is long-lived,
    # so it must not pin a pooled DB connection for its whole lifetime.
    try:
        async with async_session_factory() as session:
            edge_device = await get_edge_device_from_authorization(session, authorization)
    except HTTPException:
        await websocket.close(code=1008)
        return

    await websocket.accept()
    await video_stream_broker.start_publishing(edge_device.device_id)
    try:
        while True:
            frame = await websocket.receive_bytes()
            if frame:
                await video_stream_broker.publish(edge_device.device_id, frame)
    except WebSocketDisconnect:
        pass
    except KeyError:
        # receive_bytes raises KeyError on a non-binary frame; reject it.
        await websocket.close(code=1003)
    finally:
        await video_stream_broker.stop_publishing(edge_device.device_id)


@router.post("/heartbeat")
async def edge_heartbeat(
    payload: DeviceHeartbeat,
    edge_device: Device = Depends(get_edge_device),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    previous = {
        "health_status": edge_device.health_status,
        "rssi": edge_device.rssi,
        "fps": edge_device.fps,
        "current_pan": edge_device.current_pan,
        "current_tilt": edge_device.current_tilt,
    }
    edge_device.health_status = payload.health_status
    edge_device.rssi = payload.rssi
    edge_device.fps = payload.fps
    edge_device.current_pan = payload.current_pan
    edge_device.current_tilt = payload.current_tilt
    edge_device.last_seen = datetime.now(UTC)
    edge_device.updated_at = edge_device.last_seen
    await session.commit()
    await session.refresh(edge_device)
    current = {
        "health_status": edge_device.health_status,
        "rssi": edge_device.rssi,
        "fps": edge_device.fps,
        "current_pan": edge_device.current_pan,
        "current_tilt": edge_device.current_tilt,
    }
    if current != previous:
        await realtime_bus.publish(
            edge_device.user_id,
            "device.health_changed",
            {
                "device_id": edge_device.device_id,
                "health_status": edge_device.health_status,
                "rssi": edge_device.rssi,
                "fps": edge_device.fps,
                "current_pan": edge_device.current_pan,
                "current_tilt": edge_device.current_tilt,
                "last_seen": edge_device.last_seen,
            },
        )
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
            name=agent.name,
            # The edge triage/agent judges the keyframe against this rule text; without it
            # the edge falls back to a generic "anything suspicious" prompt and drops
            # legitimate events (see SentinelEdge_LaptopEdge pipeline/triage.py _prompt).
            nl_rule=agent.nl_rule or "",
            compiled_prompt=agent.compiled_prompt or "",
            state="armed",
            compiled_edge_config=agent.compiled_edge_config or {},
        ).model_dump(mode="json")
        for agent in result.scalars()
    ]
    # control_mode travels alongside the configs so a reconnecting edge restores the last
    # servo-ownership mode (off/auto_track/agent) it was set to.
    return {"data": configs, "control_mode": edge_device.control_mode}


@router.post("/agent-control")
async def agent_camera_control(
    situation: dict = Body(...),
    edge_device: Device = Depends(get_edge_device),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    """Decide the next PTZ move for a device in "agent" control mode.

    The laptop edge posts a compact scene "situation" (behavior, detections, current
    pan/tilt, and a deterministic fallback ``candidate``); we ask the cloud model for the
    next move, clamp it to the servo limits, audit it, and return the action (or null to
    hold). Never trusts the model — the action is sanitized in camera_control_service.
    """
    action = await decide_camera_control(situation)
    audit = ToolAudit(
        audit_id=_new_audit_id(),
        user_id=edge_device.user_id,
        device_id=edge_device.device_id,
        tool_name="agent_camera_control",
        arguments=situation,
        result={"action": action},
        called_by="agent",
        timestamp=datetime.now(UTC),
    )
    session.add(audit)
    await session.commit()
    return {"data": {"action": action}}


@router.post("/events", status_code=status.HTTP_201_CREATED)
async def create_edge_event(
    payload: EdgeEventCreate,
    response: Response,
    background_tasks: BackgroundTasks,
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
    try:
        await session.commit()
    except IntegrityError:
        # A concurrent request with the same (device_id, idempotency_key) won the
        # race — e.g. the edge retried after a client-side timeout while the first
        # insert was still in flight. Replay the persisted event as an idempotent
        # 200 instead of surfacing a 500, which is exactly what idempotency exists
        # to avoid.
        await session.rollback()
        existing = await _get_event_by_idempotency(
            session, edge_device.device_id, payload.idempotency_key
        )
        if existing is not None:
            response.status_code = status.HTTP_200_OK
            return {"data": EventRead.model_validate(existing).model_dump(mode="json")}
        raise
    await session.refresh(event)
    await realtime_bus.publish(
        event.user_id,
        "event.created",
        {
            "event_id": event.event_id,
            "device_id": event.device_id,
            "agent_id": event.agent_id,
            "severity": event.severity,
            "status": event.status,
            "timestamp": event.timestamp,
            "summary": event.summary,
        },
    )
    # Fire a push alert for qualifying events. Alerting must never break
    # ingestion, so any failure is swallowed.
    try:
        await alert_service.maybe_alert_for_event(session, event)
    except Exception:  # noqa: BLE001 - alerting is best-effort
        pass
    # Milestone 9: verify qualifying events with Qwen Cloud after the response is
    # sent. Runs in its own DB session; re-evaluates alerting on the verdict.
    if verification_service.should_verify(event):
        background_tasks.add_task(verification_service.run_verification, event.event_id)
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
    await realtime_bus.publish(
        clip.user_id,
        "clip.available",
        {
            "clip_id": clip.clip_id,
            "event_id": clip.event_id,
            "device_id": clip.device_id,
            "status": clip.status,
            "clip_type": clip.clip_type,
        },
    )
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
