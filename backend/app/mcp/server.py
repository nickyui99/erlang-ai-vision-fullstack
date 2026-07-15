"""The SentinelEdge MCP server: the platform's tools behind Model Context Protocol.

Exposes user-scoped tools (camera control, agents, events, clips/recordings) over
MCP streamable HTTP, mounted at ``{api_prefix}/mcp``. The Erlang AI Agent chat
connects to this as an ordinary MCP client — and so can any external MCP client
(Claude, IDEs, ...) holding a valid access token.

Auth: every request carries ``Authorization: Bearer <token>`` where the token is a
signed ``mcp_access`` token minted by this backend (``create_signed_token``); tools
resolve the user from it, so all reads/writes are scoped to that user's data.
Every call is permission-checked against ``permissions.CHAT_AUTONOMY`` and audited
to ``tool_audit`` with ``called_by="chat"`` — same guardrails as the verification
agent's in-process tools.
"""

from __future__ import annotations

import logging
import secrets
import time
from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

from mcp.server.fastmcp import Context, FastMCP, Image
from sqlalchemy import select

from app.core.security import verify_signed_token
from app.db.session import async_session_factory
from app.mcp import permissions
from app.models.agent import Agent
from app.models.clip import Clip
from app.models.device import Device
from app.models.event import Event
from app.models.recording import Recording
from app.models.tool_audit import ToolAudit
from app.services import agent_service
from app.services.edge_command_hub import (
    EdgeCommandTimeoutError,
    EdgeNotConnectedError,
    edge_command_hub,
)
from app.services.media_url_service import media_url_service
from app.services.video_stream_broker import video_stream_broker


log = logging.getLogger("app.mcp.server")

MCP_TOKEN_PURPOSE = "mcp_access"

# Stateless HTTP: each tool call is an independent request (no server-side session
# affinity), which suits an API-embedded server and keeps clients trivial.
mcp_server = FastMCP(
    "SentinelEdge",
    instructions=(
        "Tools for the SentinelEdge AI security-camera platform, scoped to the "
        "authenticated user: inspect cameras and events, move cameras, fetch clips "
        "and recordings, and manage surveillance agents."
    ),
    streamable_http_path="/",
    stateless_http=True,
)


class ToolDenied(Exception):
    """Raised for auth/permission failures; the message is safe to show the model."""


def _user_id_from(ctx: Context) -> str:
    request = getattr(ctx.request_context, "request", None)
    auth = ""
    if request is not None:
        auth = request.headers.get("authorization") or ""
    token = auth[7:].strip() if auth.lower().startswith("bearer ") else ""
    payload = verify_signed_token(token, MCP_TOKEN_PURPOSE) if token else None
    user_id = payload.get("user_id") if isinstance(payload, dict) else None
    if not isinstance(user_id, str) or not user_id:
        raise ToolDenied("missing or invalid MCP access token")
    return user_id


async def _audit(session, *, user_id: str, tool: str, args: dict, ok: bool, summary: str,
                 device_id: str | None = None) -> None:
    session.add(
        ToolAudit(
            audit_id=f"aud_{uuid4().hex}",
            event_id=None,
            user_id=user_id,
            device_id=device_id,
            tool_name=tool,
            arguments=args,
            result={"ok": ok, "summary": summary[:500]},
            called_by="chat",
            timestamp=datetime.now(UTC),
        )
    )
    await session.commit()


async def _run(ctx: Context, tool: str, args: dict, impl):
    """Auth -> permission check -> execute -> audit, in one DB session.

    ``impl(user_id, session)`` returns the tool result (dict or Image). Failures
    return an ``{"ok": False, "error": ...}`` dict rather than raising, so the
    model can read the reason and adjust instead of the turn erroring out.
    """
    try:
        user_id = _user_id_from(ctx)
    except ToolDenied as exc:
        return {"ok": False, "error": str(exc)}
    async with async_session_factory() as session:
        if not permissions.is_allowed(tool, scope="chat"):
            await _audit(session, user_id=user_id, tool=tool, args=args, ok=False,
                         summary="tool_not_permitted", device_id=args.get("device_id"))
            return {"ok": False, "error": "tool_not_permitted"}
        try:
            result = await impl(user_id, session)
            summary = "image" if isinstance(result, Image) else str(result)[:200]
            await _audit(session, user_id=user_id, tool=tool, args=args, ok=True,
                         summary=summary, device_id=args.get("device_id"))
            return result
        except agent_service.AgentNotFoundError:
            error = "agent_not_found"
        except agent_service.DeviceNotFoundError:
            error = "device_not_found"
        except agent_service.AgentNotAssignedError:
            error = "agent_not_assigned_to_device"
        except (EdgeNotConnectedError, EdgeCommandTimeoutError):
            error = "camera_edge_offline"
        except Exception as exc:  # noqa: BLE001 - a tool bug must not kill the chat turn
            log.exception("MCP tool %s failed", tool)
            error = f"tool_error: {exc}"
        await _audit(session, user_id=user_id, tool=tool, args=args, ok=False,
                     summary=error, device_id=args.get("device_id"))
        return {"ok": False, "error": error}


def _command_id() -> str:
    return f"cmd_{secrets.token_urlsafe(18)}"


def _device_dict(device: Device) -> dict:
    return {
        "device_id": device.device_id,
        "name": device.name,
        "location": device.location,
        "health_status": device.health_status,
        "fps": device.fps,
        "current_pan": device.current_pan,
        "current_tilt": device.current_tilt,
        "control_mode": device.control_mode,
        "last_seen": device.last_seen.isoformat() if device.last_seen else None,
    }


def _agent_dict(agent: Agent) -> dict:
    return {
        "agent_id": agent.agent_id,
        "name": agent.name,
        "nl_rule": agent.nl_rule,
        "state": agent.state,
        "enabled": agent.enabled,
        "device_id": agent.device_id,
        "parent_agent_id": agent.parent_agent_id,
        "is_definition": agent.parent_agent_id is None,
    }


# ------------------------------------------------------------------ device tools

@mcp_server.tool()
async def list_devices(ctx: Context) -> dict:
    """List the user's cameras with their live health status."""
    async def impl(user_id: str, session):
        result = await session.execute(
            select(Device).where(Device.user_id == user_id).order_by(Device.created_at)
        )
        devices = [_device_dict(d) for d in result.scalars()]
        return {"ok": True, "devices": devices, "count": len(devices)}
    return await _run(ctx, "list_devices", {}, impl)


@mcp_server.tool()
async def get_device_status(device_id: str, ctx: Context) -> dict:
    """Get one camera's health, position, and connection status."""
    async def impl(user_id: str, session):
        device = await agent_service.ensure_owned_device(session, user_id, device_id)
        return {"ok": True, "device": _device_dict(device)}
    return await _run(ctx, "get_device_status", {"device_id": device_id}, impl)


async def _move_camera(ctx: Context, *, tool: str, command_type: str,
                       device_id: str, angle: int) -> dict:
    async def impl(user_id: str, session):
        await agent_service.ensure_owned_device(session, user_id, device_id)
        # Pan and tilt share the per-user movement budget (same limiter as the
        # verification agent, keyed by user instead of event).
        allowed, reason = permissions.pan_rate_limiter.check_and_register(
            f"chat:{user_id}", time.monotonic()
        )
        if not allowed:
            return {"ok": False, "error": reason}
        raw = await edge_command_hub.send_command(
            device_id,
            {
                "type": command_type,
                "request_id": _command_id(),
                "device_id": device_id,
                "payload": {"angle": angle},
            },
        )
        return {"ok": True, "angle": angle, "status": raw.get("status")}
    return await _run(ctx, tool, {"device_id": device_id, "angle": angle}, impl)


@mcp_server.tool()
async def pan_camera(device_id: str, angle: int, ctx: Context) -> dict:
    """Pan a camera to an absolute horizontal angle (degrees, clamped to 15-165)."""
    return await _move_camera(
        ctx, tool="pan_camera", command_type="command.pan_camera",
        device_id=device_id, angle=permissions.clamp_pan(angle),
    )


@mcp_server.tool()
async def tilt_camera(device_id: str, angle: int, ctx: Context) -> dict:
    """Tilt a camera to an absolute vertical angle (degrees, clamped to 60-140)."""
    return await _move_camera(
        ctx, tool="tilt_camera", command_type="command.tilt_camera",
        device_id=device_id, angle=permissions.clamp_tilt(angle),
    )


@mcp_server.tool()
async def get_live_snapshot(device_id: str, ctx: Context):
    """Get the camera's current view as a JPEG image (from the live stream)."""
    async def impl(user_id: str, session):
        await agent_service.ensure_owned_device(session, user_id, device_id)
        frame = video_stream_broker.latest_frame(device_id)
        if not frame:
            return {"ok": False, "error": "no_live_frame (camera offline or not streaming)"}
        return Image(data=frame, format="jpeg")
    return await _run(ctx, "get_live_snapshot", {"device_id": device_id}, impl)


# ------------------------------------------------------------------- data tools

@mcp_server.tool()
async def query_events(ctx: Context, device_id: str | None = None,
                       severity: str | None = None, limit: int = 10) -> dict:
    """Query the user's recent security events, newest first. Optionally filter by
    device_id or severity (low|medium|high|critical). limit is capped at 50."""
    async def impl(user_id: str, session):
        query = select(Event).where(Event.user_id == user_id)
        if device_id:
            query = query.where(Event.device_id == device_id)
        if severity:
            query = query.where(Event.severity == severity.lower())
        query = query.order_by(Event.timestamp.desc()).limit(max(1, min(int(limit), 50)))
        result = await session.execute(query)
        events = [
            {
                "event_id": e.event_id,
                "device_id": e.device_id,
                "agent_id": e.agent_id,
                "event_type": e.event_type,
                "severity": e.severity,
                "status": e.status,
                "summary": e.summary,
                "timestamp": e.timestamp.isoformat() if e.timestamp else None,
            }
            for e in result.scalars()
        ]
        return {"ok": True, "events": events, "count": len(events)}
    return await _run(ctx, "query_events",
                      {"device_id": device_id, "severity": severity, "limit": limit}, impl)


@mcp_server.tool()
async def get_event_clip(event_id: str, ctx: Context) -> dict:
    """Get the video clip(s) recorded for an event, with playback URLs when available."""
    async def impl(user_id: str, session):
        result = await session.execute(
            select(Clip).where(Clip.event_id == event_id, Clip.user_id == user_id)
        )
        clips = []
        for clip in result.scalars():
            item = {
                "clip_id": clip.clip_id,
                "clip_type": clip.clip_type,
                "status": clip.status,
                "mime_type": clip.mime_type,
                "duration_seconds": clip.duration_seconds,
            }
            if clip.oss_object_key and clip.status == "available":
                playback_url, _ = media_url_service.playback_url(clip.oss_object_key)
                item["playback_url"] = playback_url
            clips.append(item)
        return {"ok": True, "clips": clips, "count": len(clips)}
    return await _run(ctx, "get_event_clip", {"event_id": event_id}, impl)


@mcp_server.tool()
async def list_recordings(ctx: Context, device_id: str | None = None, limit: int = 10) -> dict:
    """List the user's on-demand recordings, newest first. Optionally filter by device_id."""
    async def impl(user_id: str, session):
        query = select(Recording).where(
            Recording.user_id == user_id, Recording.deleted_at.is_(None)
        )
        if device_id:
            query = query.where(Recording.device_id == device_id)
        query = query.order_by(Recording.start_time.desc()).limit(max(1, min(int(limit), 50)))
        result = await session.execute(query)
        recordings = [
            {
                "recording_id": r.recording_id,
                "device_id": r.device_id,
                "start_time": r.start_time.isoformat() if r.start_time else None,
                "end_time": r.end_time.isoformat() if r.end_time else None,
                "duration_seconds": r.duration_seconds,
                "storage_type": r.storage_type,
                "status": r.status,
            }
            for r in result.scalars()
        ]
        return {"ok": True, "recordings": recordings, "count": len(recordings)}
    return await _run(ctx, "list_recordings", {"device_id": device_id, "limit": limit}, impl)


# ------------------------------------------------------------------ agent tools

@mcp_server.tool()
async def list_agents(ctx: Context) -> dict:
    """List the user's surveillance agents: rule definitions and the per-camera
    sub-agents armed from them (is_definition distinguishes the two)."""
    async def impl(user_id: str, session):
        result = await session.execute(
            select(Agent).where(Agent.user_id == user_id).order_by(Agent.created_at.desc())
        )
        agents = [_agent_dict(a) for a in result.scalars()]
        return {"ok": True, "agents": agents, "count": len(agents)}
    return await _run(ctx, "list_agents", {}, impl)


@mcp_server.tool()
async def create_agent(name: str, nl_rule: str, ctx: Context,
                       location: str | None = None) -> dict:
    """Create a surveillance agent from a plain-English rule (e.g. "Alert me if a
    person appears at the front door after 9pm"). The rule is compiled into an edge
    detector config. The agent starts DISARMED; use assign_agent to arm it on a camera."""
    async def impl(user_id: str, session):
        agent = await agent_service.create_definition(
            session, user_id, name=name, nl_rule=nl_rule, location=location
        )
        return {"ok": True, "agent": _agent_dict(agent),
                "compiled_edge_config": agent.compiled_edge_config}
    return await _run(ctx, "create_agent", {"name": name, "nl_rule": nl_rule}, impl)


@mcp_server.tool()
async def assign_agent(agent_id: str, device_id: str, ctx: Context) -> dict:
    """Arm an agent (by its definition agent_id) on a camera. Takes effect on the
    edge within about a second."""
    async def impl(user_id: str, session):
        sub_agent = await agent_service.assign_to_device(session, user_id, agent_id, device_id)
        return {"ok": True, "sub_agent": _agent_dict(sub_agent)}
    return await _run(ctx, "assign_agent", {"agent_id": agent_id, "device_id": device_id}, impl)


@mcp_server.tool()
async def unassign_agent(agent_id: str, device_id: str, ctx: Context) -> dict:
    """Disarm an agent (by its definition agent_id) on a camera. The camera's event
    history for this agent is preserved."""
    async def impl(user_id: str, session):
        sub_agent = await agent_service.unassign_from_device(session, user_id, agent_id, device_id)
        return {"ok": True, "sub_agent": _agent_dict(sub_agent)}
    return await _run(ctx, "unassign_agent", {"agent_id": agent_id, "device_id": device_id}, impl)


class MCPBearerGate:
    """Coarse ASGI gate for the mounted MCP app: reject requests without a valid
    ``mcp_access`` bearer token before they reach the protocol layer. Tools still
    resolve the user from the same header (defense in depth + identity)."""

    def __init__(self, app: Any) -> None:
        self.app = app

    async def __call__(self, scope, receive, send) -> None:
        if scope["type"] == "http":
            headers = {k.decode("latin-1").lower(): v.decode("latin-1")
                       for k, v in scope.get("headers") or []}
            auth = headers.get("authorization", "")
            token = auth[7:].strip() if auth.lower().startswith("bearer ") else ""
            if not (token and verify_signed_token(token, MCP_TOKEN_PURPOSE)):
                await send({
                    "type": "http.response.start",
                    "status": 401,
                    "headers": [(b"content-type", b"application/json")],
                })
                await send({
                    "type": "http.response.body",
                    "body": b'{"error":{"code":"unauthorized","message":"valid MCP access token required"}}',
                })
                return
        await self.app(scope, receive, send)


def build_mcp_asgi_app():
    """The mountable ASGI app: FastMCP streamable HTTP behind the bearer gate."""
    return MCPBearerGate(mcp_server.streamable_http_app())
