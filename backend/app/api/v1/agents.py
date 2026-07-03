from __future__ import annotations

from datetime import UTC, datetime
import secrets

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.compiler import compile_agent_rule
from app.api.deps import get_current_user, get_db_session
from app.models.agent import Agent
from app.models.device import Device
from app.models.user import User
from app.schemas.agent import AgentAssign, AgentCreate, AgentRead, AgentUpdate
from app.services.realtime_bus import realtime_bus


router = APIRouter(prefix="/agents", tags=["agents"])


def _new_agent_id() -> str:
    return f"agt_{secrets.token_urlsafe(18)}"


async def _get_owned_agent(session: AsyncSession, user_id: str, agent_id: str) -> Agent:
    result = await session.execute(
        select(Agent).where(Agent.agent_id == agent_id, Agent.user_id == user_id)
    )
    agent = result.scalar_one_or_none()
    if agent is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Agent was not found"},
        )
    return agent


async def _ensure_owned_device(session: AsyncSession, user_id: str, device_id: str) -> Device:
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
async def create_agent(
    payload: AgentCreate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    device_id: str | None = None
    if payload.device_id:
        await _ensure_owned_device(session, current_user.user_id, payload.device_id)
        device_id = payload.device_id
    compiled_prompt, compiled_edge_config = await compile_agent_rule(payload.nl_rule)
    now = datetime.now(UTC)
    agent = Agent(
        agent_id=_new_agent_id(),
        user_id=current_user.user_id,
        device_id=device_id,
        name=payload.name.strip(),
        location=payload.location.strip() if payload.location else None,
        nl_rule=payload.nl_rule.strip(),
        compiled_prompt=compiled_prompt,
        compiled_edge_config=compiled_edge_config,
        state="disarmed",
        enabled=True,
        created_at=now,
        updated_at=now,
    )
    session.add(agent)
    await session.commit()
    await session.refresh(agent)
    return {"data": AgentRead.model_validate(agent).model_dump(mode="json")}


@router.get("")
async def list_agents(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    result = await session.execute(
        select(Agent).where(Agent.user_id == current_user.user_id).order_by(Agent.created_at.desc())
    )
    agents = [AgentRead.model_validate(agent).model_dump(mode="json") for agent in result.scalars()]
    return {"data": agents}


@router.get("/{agent_id}")
async def get_agent(
    agent_id: str,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    agent = await _get_owned_agent(session, current_user.user_id, agent_id)
    return {"data": AgentRead.model_validate(agent).model_dump(mode="json")}


@router.put("/{agent_id}")
async def update_agent(
    agent_id: str,
    payload: AgentUpdate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    agent = await _get_owned_agent(session, current_user.user_id, agent_id)
    normalized_payload_rule = " ".join(payload.nl_rule.split())
    if normalized_payload_rule != " ".join((agent.nl_rule or "").split()):
        compiled_prompt, compiled_edge_config = await compile_agent_rule(payload.nl_rule)
        agent.compiled_prompt = compiled_prompt
        agent.compiled_edge_config = compiled_edge_config
    agent.name = payload.name.strip()
    agent.location = payload.location.strip() if payload.location else None
    agent.nl_rule = payload.nl_rule.strip()
    agent.updated_at = datetime.now(UTC)
    await session.commit()
    await session.refresh(agent)
    return {"data": AgentRead.model_validate(agent).model_dump(mode="json")}


async def _get_sub_agent(
    session: AsyncSession, user_id: str, parent_agent_id: str, device_id: str
) -> Agent | None:
    result = await session.execute(
        select(Agent).where(
            Agent.parent_agent_id == parent_agent_id,
            Agent.device_id == device_id,
            Agent.user_id == user_id,
        )
    )
    return result.scalar_one_or_none()


@router.post("/{agent_id}/assign")
async def assign_agent(
    agent_id: str,
    payload: AgentAssign,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    # Assigning clones the definition into a per-camera sub-agent (new id).
    parent = await _get_owned_agent(session, current_user.user_id, agent_id)
    await _ensure_owned_device(session, current_user.user_id, payload.device_id)

    existing = await _get_sub_agent(
        session, current_user.user_id, parent.agent_id, payload.device_id
    )
    if existing is not None:
        return {"data": AgentRead.model_validate(existing).model_dump(mode="json")}

    compiled_prompt, compiled_edge_config = await compile_agent_rule(parent.nl_rule)
    now = datetime.now(UTC)
    sub_agent = Agent(
        agent_id=_new_agent_id(),
        user_id=current_user.user_id,
        device_id=payload.device_id,
        parent_agent_id=parent.agent_id,
        name=parent.name,
        location=parent.location,
        nl_rule=parent.nl_rule,
        compiled_prompt=compiled_prompt,
        compiled_edge_config=compiled_edge_config,
        state="armed",
        enabled=True,
        created_at=now,
        updated_at=now,
    )
    session.add(sub_agent)
    await session.commit()
    await session.refresh(sub_agent)
    await realtime_bus.publish(
        current_user.user_id,
        "agent.state_changed",
        {
            "agent_id": sub_agent.agent_id,
            "device_id": sub_agent.device_id,
            "state": sub_agent.state,
            "enabled": sub_agent.enabled,
        },
    )
    return {"data": AgentRead.model_validate(sub_agent).model_dump(mode="json")}


@router.post("/{agent_id}/unassign")
async def unassign_agent(
    agent_id: str,
    payload: AgentAssign,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    # Unassigning disconnects (deletes) the camera's sub-agent.
    await _get_owned_agent(session, current_user.user_id, agent_id)
    sub_agent = await _get_sub_agent(
        session, current_user.user_id, agent_id, payload.device_id
    )
    if sub_agent is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "code": "not_found",
                "message": "Agent is not assigned to this device",
            },
        )
    sub_agent_id = sub_agent.agent_id
    await session.delete(sub_agent)
    await session.commit()
    await realtime_bus.publish(
        current_user.user_id,
        "agent.state_changed",
        {
            "agent_id": sub_agent_id,
            "device_id": payload.device_id,
            "state": "disarmed",
            "enabled": False,
        },
    )
    return {
        "data": {
            "agent_id": agent_id,
            "sub_agent_id": sub_agent_id,
            "device_id": payload.device_id,
            "state": "disarmed",
        }
    }
