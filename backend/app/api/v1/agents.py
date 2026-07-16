from __future__ import annotations

from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.builder import run_agent_builder
from app.agents.compiler import compile_agent_rule
from app.api.deps import get_current_user, get_db_session
from app.models.agent import Agent
from app.models.user import User
from app.schemas.agent import (
    AgentAssign,
    AgentBuilderRequest,
    AgentCreate,
    AgentRead,
    AgentUpdate,
)
from app.services import agent_service


router = APIRouter(prefix="/agents", tags=["agents"])


def _not_found(message: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail={"code": "not_found", "message": message},
    )


@router.post("/builder")
async def agent_builder(
    payload: AgentBuilderRequest,
    current_user: User = Depends(get_current_user),
) -> dict:
    """Conversational rule builder: one chat turn -> reply + proposed rule preview."""
    result = await run_agent_builder([turn.model_dump() for turn in payload.messages])
    return {"data": result}


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_agent(
    payload: AgentCreate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    try:
        agent = await agent_service.create_definition(
            session,
            current_user.user_id,
            name=payload.name,
            nl_rule=payload.nl_rule,
            location=payload.location,
            device_id=payload.device_id,
        )
    except agent_service.DeviceNotFoundError:
        raise _not_found("Device was not found")
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
    try:
        agent = await agent_service.get_owned_agent(session, current_user.user_id, agent_id)
    except agent_service.AgentNotFoundError:
        raise _not_found("Agent was not found")
    return {"data": AgentRead.model_validate(agent).model_dump(mode="json")}


@router.put("/{agent_id}")
async def update_agent(
    agent_id: str,
    payload: AgentUpdate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    try:
        agent = await agent_service.get_owned_agent(session, current_user.user_id, agent_id)
    except agent_service.AgentNotFoundError:
        raise _not_found("Agent was not found")
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


@router.post("/{agent_id}/assign")
async def assign_agent(
    agent_id: str,
    payload: AgentAssign,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    # Assigning arms a per-camera sub-agent (re-arming the retained one if it exists);
    # the shared logic lives in agent_service so the chat agent's MCP tools match.
    try:
        sub_agent = await agent_service.assign_to_device(
            session, current_user.user_id, agent_id, payload.device_id
        )
    except agent_service.AgentNotFoundError:
        raise _not_found("Agent was not found")
    except agent_service.DeviceNotFoundError:
        raise _not_found("Device was not found")
    return {"data": AgentRead.model_validate(sub_agent).model_dump(mode="json")}


@router.post("/{agent_id}/unassign")
async def unassign_agent(
    agent_id: str,
    payload: AgentAssign,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    # Unassigning DISARMS the sub-agent but keeps the row so its events/alerts/clips
    # survive (they cascade off the sub-agent's id). See agent_service.unassign_from_device.
    try:
        sub_agent = await agent_service.unassign_from_device(
            session, current_user.user_id, agent_id, payload.device_id
        )
    except agent_service.AgentNotFoundError:
        raise _not_found("Agent was not found")
    except agent_service.AgentNotAssignedError:
        raise _not_found("Agent is not assigned to this device")
    return {
        "data": {
            "agent_id": agent_id,
            "sub_agent_id": sub_agent.agent_id,
            "device_id": payload.device_id,
            "state": "disarmed",
        }
    }


@router.delete("/{agent_id}")
async def delete_agent(
    agent_id: str,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    # Deleting a definition cascades its sub-agents, and each removed agent's
    # events/alerts/clips cascade with it (see agent_service.delete_agent).
    try:
        device_ids = await agent_service.delete_agent(session, current_user.user_id, agent_id)
    except agent_service.AgentNotFoundError:
        raise _not_found("Agent was not found")
    return {"data": {"agent_id": agent_id, "deleted": True, "device_ids": device_ids}}
