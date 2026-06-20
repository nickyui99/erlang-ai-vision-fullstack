from __future__ import annotations

from datetime import UTC, datetime
import secrets

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db_session
from app.core.security import generate_edge_token, hash_edge_token
from app.models.device import Device
from app.models.user import User
from app.schemas.device import DeviceCreate, DeviceRead, DeviceRegistrationRead, DeviceUpdate


router = APIRouter(prefix="/devices", tags=["devices"])


def _new_device_id() -> str:
    return f"dev_{secrets.token_urlsafe(18)}"


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
