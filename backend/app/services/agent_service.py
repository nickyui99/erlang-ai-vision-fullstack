"""Agent lifecycle operations shared by the REST API and the MCP tool server.

Extracted from ``api/v1/agents.py`` so the chat agent's MCP tools and the app's
endpoints run the exact same create/assign/unassign logic (arming semantics,
realtime publishes, and the edge refresh nudge) instead of drifting copies.
Raises domain errors; HTTP mapping stays in the API layer.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime
import logging
import secrets

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.compiler import compile_agent_rule
from app.models.agent import Agent
from app.models.device import Device
from app.services.edge_command_hub import (
    EdgeCommandTimeoutError,
    EdgeNotConnectedError,
    edge_command_hub,
)
from app.services.realtime_bus import realtime_bus


log = logging.getLogger("app.services.agent_service")


class AgentNotFoundError(LookupError):
    """The agent does not exist or is not owned by the user."""


class DeviceNotFoundError(LookupError):
    """The device does not exist or is not owned by the user."""


class AgentNotAssignedError(LookupError):
    """The agent has no armed sub-agent on the given device."""


def new_agent_id() -> str:
    return f"agt_{secrets.token_urlsafe(18)}"


async def get_owned_agent(session: AsyncSession, user_id: str, agent_id: str) -> Agent:
    result = await session.execute(
        select(Agent).where(Agent.agent_id == agent_id, Agent.user_id == user_id)
    )
    agent = result.scalar_one_or_none()
    if agent is None:
        raise AgentNotFoundError(agent_id)
    return agent


async def ensure_owned_device(session: AsyncSession, user_id: str, device_id: str) -> Device:
    result = await session.execute(
        select(Device).where(Device.device_id == device_id, Device.user_id == user_id)
    )
    device = result.scalar_one_or_none()
    if device is None:
        raise DeviceNotFoundError(device_id)
    return device


async def get_sub_agent(
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


async def nudge_edge_refresh(device_id: str | None) -> bool:
    """Best-effort: tell the device's bridge to re-poll /edge/agents/active NOW, so an
    assign/unassign takes effect in under a second instead of on the next ~30s poll.

    The poll remains the reconciliation path: an offline edge, an old bridge that answers
    unsupported_command, or any failure here just means the change lands on the next poll.
    Called after commit so the re-poll always reads the new state.
    """
    if not device_id:
        return False
    message = {
        "type": "command.refresh_agents",
        "request_id": f"cmd_{secrets.token_urlsafe(18)}",
        "payload": {},
    }
    try:
        result = await asyncio.wait_for(
            edge_command_hub.send_command(device_id, message), timeout=2.0
        )
        return result.get("status") == "ok"
    except (EdgeNotConnectedError, EdgeCommandTimeoutError, TimeoutError):
        return False
    except Exception:  # noqa: BLE001 - a nudge failure must never fail the operation
        log.warning("edge agents-refresh nudge failed for %s", device_id, exc_info=True)
        return False


async def _publish_state(agent: Agent, device_id: str | None = None) -> None:
    await realtime_bus.publish(
        agent.user_id,
        "agent.state_changed",
        {
            "agent_id": agent.agent_id,
            "device_id": device_id if device_id is not None else agent.device_id,
            "state": agent.state,
            "enabled": agent.enabled,
        },
    )


async def create_definition(
    session: AsyncSession,
    user_id: str,
    *,
    name: str,
    nl_rule: str,
    location: str | None = None,
    device_id: str | None = None,
) -> Agent:
    """Create a device-independent agent definition (disarmed until assigned)."""
    if device_id:
        await ensure_owned_device(session, user_id, device_id)
    compiled_prompt, compiled_edge_config = await compile_agent_rule(nl_rule)
    now = datetime.now(UTC)
    agent = Agent(
        agent_id=new_agent_id(),
        user_id=user_id,
        device_id=device_id,
        name=name.strip(),
        location=location.strip() if location else None,
        nl_rule=nl_rule.strip(),
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
    return agent


async def assign_to_device(
    session: AsyncSession, user_id: str, agent_id: str, device_id: str
) -> Agent:
    """Arm ``agent_id`` on ``device_id``: re-arm the retained sub-agent, or clone one.

    Unassign disarms rather than deletes (events/alerts/clips cascade off the
    sub-agent's id), so re-assigning re-arms the SAME row and refreshes its
    definition from the parent — identity, and thus history, is preserved.
    """
    parent = await get_owned_agent(session, user_id, agent_id)
    await ensure_owned_device(session, user_id, device_id)

    existing = await get_sub_agent(session, user_id, parent.agent_id, device_id)
    now = datetime.now(UTC)
    if existing is not None:
        if " ".join((existing.nl_rule or "").split()) != " ".join((parent.nl_rule or "").split()):
            compiled_prompt, compiled_edge_config = await compile_agent_rule(parent.nl_rule)
            existing.compiled_prompt = compiled_prompt
            existing.compiled_edge_config = compiled_edge_config
        existing.name = parent.name
        existing.location = parent.location
        existing.nl_rule = parent.nl_rule
        existing.state = "armed"
        existing.enabled = True
        existing.updated_at = now
        await session.commit()
        await session.refresh(existing)
        await _publish_state(existing)
        await nudge_edge_refresh(existing.device_id)
        return existing

    compiled_prompt, compiled_edge_config = await compile_agent_rule(parent.nl_rule)
    sub_agent = Agent(
        agent_id=new_agent_id(),
        user_id=user_id,
        device_id=device_id,
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
    await _publish_state(sub_agent)
    await nudge_edge_refresh(sub_agent.device_id)
    return sub_agent


async def delete_agent(session: AsyncSession, user_id: str, agent_id: str) -> list[str]:
    """Delete an owned agent outright, returning the device_ids that carried it.

    Deleting a definition cascades its per-camera sub-agents (parent_agent_id FK),
    and each removed agent's events/alerts/clips cascade off its id — so this
    intentionally erases the agent's detection history. Unassign remains the
    non-destructive way to take an agent off a camera.
    """
    agent = await get_owned_agent(session, user_id, agent_id)
    result = await session.execute(
        select(Agent.device_id).where(
            (Agent.agent_id == agent_id) | (Agent.parent_agent_id == agent_id),
            Agent.user_id == user_id,
            Agent.device_id.is_not(None),
        )
    )
    device_ids = sorted({row[0] for row in result})
    await session.delete(agent)
    await session.commit()
    for device_id in device_ids:
        await realtime_bus.publish(
            user_id,
            "agent.state_changed",
            {"agent_id": agent_id, "device_id": device_id, "state": "deleted", "enabled": False},
        )
        await nudge_edge_refresh(device_id)
    return device_ids


async def unassign_from_device(
    session: AsyncSession, user_id: str, agent_id: str, device_id: str
) -> Agent:
    """Disarm ``agent_id``'s sub-agent on ``device_id``, KEEPING the row.

    Events, alerts, and clips cascade off the sub-agent's id (ondelete=CASCADE), so
    deleting it would silently erase the camera's detection history. Deleting the
    camera itself still cascades everything away, as designed.
    """
    await get_owned_agent(session, user_id, agent_id)
    sub_agent = await get_sub_agent(session, user_id, agent_id, device_id)
    if sub_agent is None or sub_agent.state != "armed":
        raise AgentNotAssignedError(agent_id)
    sub_agent.state = "disarmed"
    sub_agent.updated_at = datetime.now(UTC)
    await session.commit()
    await _publish_state(sub_agent, device_id=device_id)
    await nudge_edge_refresh(device_id)
    return sub_agent
