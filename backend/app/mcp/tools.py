"""Milestone 9B — MCP tool implementations and the audited dispatcher.

Tools are invoked in-process by the verification loop. Every call is permission
checked and written to ``tool_audit`` with ``called_by="agent"`` and the owning
``event_id``. Actuation (pan / snapshot) is relayed through the edge command hub;
reads are scoped to the event's owner via the supplied session.
"""

from __future__ import annotations

import base64
from dataclasses import dataclass
from datetime import UTC, datetime
import secrets
import time
from uuid import uuid4

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.mcp import permissions
from app.mcp.schemas import ToolResult
from app.models.clip import Clip
from app.models.device import Device
from app.models.event import Event
from app.models.tool_audit import ToolAudit
from app.services.edge_command_hub import (
    EdgeCommandTimeoutError,
    EdgeNotConnectedError,
    edge_command_hub,
)
from app.services.media_url_service import media_url_service
from app.services.qwen_client import QwenToolCall
from app.services.video_stream_broker import video_stream_broker


_RECENT_EVENTS_LIMIT = 5


@dataclass
class ToolContext:
    """Identity + DB session a tool runs against, for one event verification."""

    event_id: str
    user_id: str
    device_id: str
    session: AsyncSession


def _command_id() -> str:
    return f"cmd_{secrets.token_urlsafe(18)}"


async def execute_tool(call: QwenToolCall, context: ToolContext) -> ToolResult:
    """Permission-check, run, and audit a single tool call."""

    name = call.name
    args = call.arguments if isinstance(call.arguments, dict) else {}

    if not permissions.is_allowed(name):
        result = ToolResult(tool=name, ok=False, error="tool_not_permitted")
        await _audit(context, name, args, result)
        return result

    try:
        if name == "pan_camera":
            result = await _pan_camera(args, context)
        elif name == "get_live_snapshot":
            result = await _get_live_snapshot(context)
        elif name == "get_device_status":
            result = await _get_device_status(context)
        elif name == "query_recent_events":
            result = await _query_recent_events(context)
        elif name == "get_event_clip":
            result = await _get_event_clip(context)
        else:
            result = ToolResult(tool=name, ok=False, error="unknown_tool")
    except Exception as exc:  # noqa: BLE001 - a tool failure must not crash the loop
        result = ToolResult(tool=name, ok=False, error=f"tool_error: {exc}")

    await _audit(context, name, args, result)
    return result


async def _pan_camera(args: dict, context: ToolContext) -> ToolResult:
    angle = permissions.clamp_angle(args.get("angle", 90))
    allowed, reason = permissions.pan_rate_limiter.check_and_register(
        context.event_id, time.monotonic()
    )
    if not allowed:
        return ToolResult("pan_camera", ok=False, error=reason, data={"requested_angle": angle})
    try:
        raw = await edge_command_hub.send_command(
            context.device_id,
            {
                "type": "command.pan_camera",
                "request_id": _command_id(),
                "device_id": context.device_id,
                "payload": {"angle": angle},
            },
        )
        return ToolResult("pan_camera", ok=True, data={"angle": angle, "status": raw.get("status")})
    except (EdgeNotConnectedError, EdgeCommandTimeoutError) as exc:
        return ToolResult("pan_camera", ok=False, error="edge_unavailable", data={"angle": angle, "detail": str(exc)})


async def _get_live_snapshot(context: ToolContext) -> ToolResult:
    # Prefer the live stream's most recent frame; fall back to an on-demand
    # snapshot command so verification works even when no one is watching.
    frame = video_stream_broker.latest_frame(context.device_id)
    if frame:
        return ToolResult(
            "get_live_snapshot",
            ok=True,
            data={"source": "live_frame", "bytes": len(frame)},
            image_b64=base64.b64encode(frame).decode("ascii"),
        )
    try:
        raw = await edge_command_hub.send_command(
            context.device_id,
            {
                "type": "command.get_live_snapshot",
                "request_id": _command_id(),
                "device_id": context.device_id,
                "payload": {},
            },
        )
        payload = raw.get("payload") if isinstance(raw.get("payload"), dict) else {}
        return ToolResult("get_live_snapshot", ok=True, data={"source": "edge_command", **payload})
    except (EdgeNotConnectedError, EdgeCommandTimeoutError):
        return ToolResult("get_live_snapshot", ok=False, error="no_frame_available")


async def _get_device_status(context: ToolContext) -> ToolResult:
    device = await context.session.get(Device, context.device_id)
    if device is None:
        return ToolResult("get_device_status", ok=False, error="device_not_found")
    return ToolResult(
        "get_device_status",
        ok=True,
        data={
            "health_status": device.health_status,
            "current_pan": device.current_pan,
            "current_tilt": device.current_tilt,
            "rssi": device.rssi,
            "fps": device.fps,
            "last_seen": device.last_seen.isoformat() if device.last_seen else None,
        },
    )


async def _query_recent_events(context: ToolContext) -> ToolResult:
    result = await context.session.execute(
        select(Event)
        .where(Event.device_id == context.device_id, Event.event_id != context.event_id)
        .order_by(Event.timestamp.desc())
        .limit(_RECENT_EVENTS_LIMIT)
    )
    events = [
        {
            "event_id": e.event_id,
            "event_type": e.event_type,
            "severity": e.severity,
            "status": e.status,
            "summary": e.summary,
            "timestamp": e.timestamp.isoformat() if e.timestamp else None,
        }
        for e in result.scalars()
    ]
    return ToolResult("query_recent_events", ok=True, data={"events": events, "count": len(events)})


async def _get_event_clip(context: ToolContext) -> ToolResult:
    result = await context.session.execute(
        select(Clip).where(Clip.event_id == context.event_id)
    )
    clips = []
    for clip in result.scalars():
        item = {
            "clip_id": clip.clip_id,
            "clip_type": clip.clip_type,
            "status": clip.status,
            "mime_type": clip.mime_type,
        }
        if clip.oss_object_key and clip.status == "available":
            playback_url, _ = media_url_service.playback_url(clip.oss_object_key)
            item["playback_url"] = playback_url
        clips.append(item)
    return ToolResult("get_event_clip", ok=True, data={"clips": clips, "count": len(clips)})


async def _audit(context: ToolContext, tool_name: str, args: dict, result: ToolResult) -> None:
    audit = ToolAudit(
        audit_id=f"aud_{uuid4().hex}",
        event_id=context.event_id,
        user_id=context.user_id,
        device_id=context.device_id,
        tool_name=tool_name,
        arguments=args,
        result=result.audit_result(),
        called_by="agent",
        timestamp=datetime.now(UTC),
    )
    context.session.add(audit)
    await context.session.commit()
