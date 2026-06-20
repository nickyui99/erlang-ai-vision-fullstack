from __future__ import annotations

from datetime import UTC, datetime

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db_session, get_edge_device
from app.models.agent import Agent
from app.models.device import Device
from app.schemas.agent import EdgeAgentConfigRead
from app.schemas.device import DeviceHeartbeat, DeviceRead


router = APIRouter(prefix="/edge", tags=["edge"])


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
