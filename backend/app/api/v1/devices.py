from __future__ import annotations

from datetime import UTC, datetime
import secrets
from typing import Any

from fastapi import APIRouter, Body, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db_session
from app.core.security import generate_edge_token, hash_edge_token
from app.models.device import Device
from app.models.tool_audit import ToolAudit
from app.models.user import User
from app.schemas.command import DeviceCommandResult, DevicePanCommand, DeviceTiltCommand
from app.schemas.device import DeviceCreate, DeviceRead, DeviceRegistrationRead, DeviceUpdate
from app.services.edge_command_hub import EdgeCommandTimeoutError, EdgeNotConnectedError, edge_command_hub


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
