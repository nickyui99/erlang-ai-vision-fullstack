from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta
import secrets
from typing import Any

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request, status
from fastapi.responses import Response, StreamingResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db_session
from app.core.config import settings
from app.core.security import create_signed_token, generate_edge_token, hash_edge_token, verify_signed_token
from app.models.clip import Clip
from app.models.recording import Recording
from app.models.device import Device
from app.models.tool_audit import ToolAudit
from app.models.user import User
from app.schemas.command import DeviceCommandResult, DevicePanCommand, DeviceTiltCommand
from app.schemas.device import DeviceCreate, DeviceRead, DeviceRegistrationRead, DeviceUpdate, LiveStreamUrlRead
from app.schemas.media import ClipRead, RecordingRead
from app.services.edge_command_hub import EdgeCommandTimeoutError, EdgeNotConnectedError, edge_command_hub
from app.services.video_stream_broker import video_stream_broker


_STREAM_TOKEN_PURPOSE = "live_stream"
_MJPEG_BOUNDARY = "frame"


router = APIRouter(prefix="/devices", tags=["devices"])


def _new_device_id() -> str:
    return f"dev_{secrets.token_urlsafe(18)}"


def _new_command_id() -> str:
    return f"cmd_{secrets.token_urlsafe(18)}"


def _new_audit_id() -> str:
    return f"aud_{secrets.token_urlsafe(18)}"


async def _get_owned_device(session: AsyncSession, user_id: str, device_id: str) -> Device:
    result = await session.execute(
        select(Device).where(Device.device_id == device_id, Device.user_id == user_id)
    )
    device = result.scalar_one_or_none()
    if device is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Device was not found"},
        )
    return device


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_device(
    payload: DeviceCreate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    raw_edge_token = generate_edge_token()
    now = datetime.now(UTC)
    device = Device(
        device_id=_new_device_id(),
        user_id=current_user.user_id,
        edge_token_hash=hash_edge_token(raw_edge_token),
        name=payload.name.strip(),
        location=payload.location.strip() if payload.location else None,
        health_status="unknown",
        current_pan=90,
        created_at=now,
        updated_at=now,
    )
    session.add(device)
    await session.commit()
    await session.refresh(device)

    data = DeviceRegistrationRead(device=DeviceRead.model_validate(device), edge_token=raw_edge_token)
    return {"data": data.model_dump(mode="json")}


@router.get("")
async def list_devices(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    result = await session.execute(
        select(Device).where(Device.user_id == current_user.user_id).order_by(Device.created_at.desc())
    )
    devices = [DeviceRead.model_validate(device).model_dump(mode="json") for device in result.scalars()]
    return {"data": devices}


@router.get("/{device_id}/clips")
async def list_device_clips(
    device_id: str,
    clip_type: str | None = None,
    status_filter: str | None = Query(default="available", alias="status"),
    limit: int = Query(default=20, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    await _get_owned_device(session, current_user.user_id, device_id)
    query = select(Clip).where(
        Clip.device_id == device_id,
        Clip.user_id == current_user.user_id,
        Clip.deleted_at.is_(None),
    )
    if clip_type:
        query = query.where(Clip.clip_type == clip_type)
    if status_filter:
        query = query.where(Clip.status == status_filter)

    result = await session.execute(query.order_by(Clip.created_at.desc()).limit(limit))
    clips = [ClipRead.model_validate(clip).model_dump(mode="json") for clip in result.scalars()]
    return {"data": clips}


@router.get("/{device_id}/recordings")
async def list_device_recordings(
    device_id: str,
    status_filter: str | None = Query(default=None, alias="status"),
    limit: int = Query(default=20, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    await _get_owned_device(session, current_user.user_id, device_id)
    query = select(Recording).where(
        Recording.device_id == device_id,
        Recording.user_id == current_user.user_id,
        Recording.deleted_at.is_(None),
    )
    if status_filter:
        query = query.where(Recording.status == status_filter)

    result = await session.execute(query.order_by(Recording.start_time.desc()).limit(limit))
    recordings = [RecordingRead.model_validate(recording).model_dump(mode="json") for recording in result.scalars()]
    return {"data": recordings}
@router.get("/{device_id}")
async def get_device(
    device_id: str,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    device = await _get_owned_device(session, current_user.user_id, device_id)
    return {"data": DeviceRead.model_validate(device).model_dump(mode="json")}


@router.put("/{device_id}")
async def update_device(
    device_id: str,
    payload: DeviceUpdate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    device = await _get_owned_device(session, current_user.user_id, device_id)
    device.name = payload.name.strip()
    device.location = payload.location.strip() if payload.location else None
    device.updated_at = datetime.now(UTC)
    await session.commit()
    await session.refresh(device)
    return {"data": DeviceRead.model_validate(device).model_dump(mode="json")}


@router.delete("/{device_id}", status_code=status.HTTP_204_NO_CONTENT, response_class=Response)
async def delete_device(
    device_id: str,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> Response:
    """Unregisters a camera. Assigned agents and recorded events cascade-delete
    via their device foreign keys (ondelete=CASCADE)."""
    device = await _get_owned_device(session, current_user.user_id, device_id)
    await session.delete(device)
    await session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{device_id}/pan")
async def pan_device(
    device_id: str,
    payload: DevicePanCommand,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    device = await _get_owned_device(session, current_user.user_id, device_id)
    result = await _send_audited_device_command(
        session=session,
        user=current_user,
        device=device,
        tool_name="pan_camera",
        command_type="command.pan_camera",
        payload={"angle": payload.angle},
    )
    return {"data": result.model_dump(mode="json")}


@router.post("/{device_id}/tilt")
async def tilt_device(
    device_id: str,
    payload: DeviceTiltCommand,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    device = await _get_owned_device(session, current_user.user_id, device_id)
    result = await _send_audited_device_command(
        session=session,
        user=current_user,
        device=device,
        tool_name="tilt_camera",
        command_type="command.tilt_camera",
        payload={"angle": payload.angle},
    )
    return {"data": result.model_dump(mode="json")}


@router.post("/{device_id}/snapshot")
async def get_device_snapshot(
    device_id: str,
    _payload: dict[str, Any] | None = Body(default=None),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    device = await _get_owned_device(session, current_user.user_id, device_id)
    result = await _send_audited_device_command(
        session=session,
        user=current_user,
        device=device,
        tool_name="get_live_snapshot",
        command_type="command.get_live_snapshot",
        payload={},
    )
    return {"data": result.model_dump(mode="json")}


@router.post("/{device_id}/stream-url")
async def create_device_stream_url(
    device_id: str,
    request: Request,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    """Mint a short-lived signed URL the frontend `<img>` can use to pull the
    device's live MJPEG stream. A query-string token is used because a
    cross-origin image request does not carry the session cookie."""
    device = await _get_owned_device(session, current_user.user_id, device_id)
    ttl = settings.signed_url_ttl_seconds
    token = create_signed_token(
        {"device_id": device.device_id, "user_id": current_user.user_id},
        _STREAM_TOKEN_PURPOSE,
        ttl,
    )
    base = str(request.base_url).rstrip("/")
    stream_url = f"{base}{settings.api_prefix}/devices/{device.device_id}/stream?token={token}"
    data = LiveStreamUrlRead(
        stream_url=stream_url,
        expires_at=datetime.now(UTC) + timedelta(seconds=ttl),
    )
    return {"data": data.model_dump(mode="json")}



@router.get("/{device_id}/stream-frame", name="stream_device_latest_frame")
async def stream_device_latest_frame(
    device_id: str,
    token: str = Query(...),
    session: AsyncSession = Depends(get_db_session),
) -> Response:
    """Return the latest pushed JPEG frame as a single image response.

    This uses the same signed token as the MJPEG stream and gives Flutter web a
    reliable polling fallback when the browser/platform-view does not repaint an
    MJPEG <img> continuously.
    """
    payload = verify_signed_token(token, _STREAM_TOKEN_PURPOSE)
    if payload is None or payload.get("device_id") != device_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_stream_token", "message": "Stream token is invalid or expired"},
        )
    user_id = payload.get("user_id")
    if not isinstance(user_id, str):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_stream_token", "message": "Stream token is invalid or expired"},
        )
    await _get_owned_device(session, user_id, device_id)

    frame = video_stream_broker.latest_frame(device_id)
    if not frame:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"code": "no_stream_frame", "message": "No video frame is available yet"},
        )
    return Response(
        content=frame,
        media_type="image/jpeg",
        headers={"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"},
    )

@router.get("/{device_id}/stream", name="stream_device_video")
async def stream_device_video(
    device_id: str,
    request: Request,
    token: str = Query(...),
    session: AsyncSession = Depends(get_db_session),
) -> StreamingResponse:
    """Stream the device's pushed JPEG frames to the browser as MJPEG."""
    payload = verify_signed_token(token, _STREAM_TOKEN_PURPOSE)
    if payload is None or payload.get("device_id") != device_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_stream_token", "message": "Stream token is invalid or expired"},
        )
    user_id = payload.get("user_id")
    if not isinstance(user_id, str):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_stream_token", "message": "Stream token is invalid or expired"},
        )
    await _get_owned_device(session, user_id, device_id)

    queue = await video_stream_broker.subscribe(device_id)

    async def frame_generator():
        try:
            while not await request.is_disconnected():
                try:
                    frame = await asyncio.wait_for(queue.get(), timeout=10)
                except asyncio.TimeoutError:
                    continue
                header = (
                    f"--{_MJPEG_BOUNDARY}\r\n"
                    f"Content-Type: image/jpeg\r\n"
                    f"Content-Length: {len(frame)}\r\n\r\n"
                ).encode("ascii")
                yield header + frame + b"\r\n"
        finally:
            await video_stream_broker.unsubscribe(device_id, queue)

    return StreamingResponse(
        frame_generator(),
        media_type=f"multipart/x-mixed-replace; boundary={_MJPEG_BOUNDARY}",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


async def _send_audited_device_command(
    *,
    session: AsyncSession,
    user: User,
    device: Device,
    tool_name: str,
    command_type: str,
    payload: dict[str, Any],
) -> DeviceCommandResult:
    request_id = _new_command_id()
    message = {
        "type": command_type,
        "request_id": request_id,
        "device_id": device.device_id,
        "payload": payload,
    }
    audit = ToolAudit(
        audit_id=_new_audit_id(),
        user_id=user.user_id,
        device_id=device.device_id,
        tool_name=tool_name,
        arguments={
            "request_id": request_id,
            "device_id": device.device_id,
            "payload": payload,
        },
        result=None,
        called_by="user",
        timestamp=datetime.now(UTC),
    )
    session.add(audit)
    await session.commit()

    try:
        raw_result = await edge_command_hub.send_command(device.device_id, message)
        result = DeviceCommandResult(
            request_id=request_id,
            status=str(raw_result.get("status", "unknown")),
            payload=raw_result.get("payload") if isinstance(raw_result.get("payload"), dict) else {},
        )
        audit.result = result.model_dump(mode="json")
        await session.commit()
        return result
    except EdgeNotConnectedError as exc:
        audit.result = {"status": "failed", "error": {"code": "edge_not_connected", "message": str(exc)}}
        await session.commit()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"code": "edge_not_connected", "message": "Edge device is not connected"},
        ) from exc
    except EdgeCommandTimeoutError as exc:
        audit.result = {"status": "failed", "error": {"code": "command_timeout", "message": str(exc)}}
        await session.commit()
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail={"code": "command_timeout", "message": "Edge command timed out"},
        ) from exc
