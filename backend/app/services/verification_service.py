"""Milestone 9 — Qwen Cloud verification orchestration.

Runs as a background task off event ingestion: builds the verification request,
asks the model (with one repair retry on malformed JSON), stores the verdict in
``events.stage3_verdict``, updates the event's status/severity/confidence,
publishes ``event.verified``, and re-evaluates the alert decision.

Designed to be fire-and-forget safe: it opens its own DB session and never lets a
failure escape (a failed verification degrades the event rather than raising).
"""

from __future__ import annotations

import json
from datetime import UTC, datetime

from sqlalchemy import select

from app.agents.prompts import build_verification_messages
from app.core.config import settings
from app.db.session import async_session_factory
from app.mcp.schemas import ToolResult, get_tool_specs
from app.mcp.tools import ToolContext, execute_tool
from app.models.agent import Agent
from app.models.device import Device
from app.models.event import Event
from app.schemas.verification import VerificationRequest, VerificationVerdict
from app.services import alert_service
from app.services import qwen_client
from app.services.qwen_client import QwenError, QwenResponse
from app.services.realtime_bus import realtime_bus


# Ordered low -> high; an event verifies when its rank >= the configured minimum.
_SEVERITY_ORDER = ["low", "medium", "high", "critical"]
_RECENT_EVENTS_LIMIT = 3


def _severity_rank(severity: str | None) -> int:
    try:
        return _SEVERITY_ORDER.index((severity or "").lower())
    except ValueError:
        return -1


def _min_rank() -> int:
    rank = _severity_rank(settings.verify_min_severity)
    return rank if rank >= 0 else _SEVERITY_ORDER.index("high")


def should_verify(event: Event) -> bool:
    """Whether ``event`` qualifies for cloud verification under current settings."""

    if not settings.verification_enabled:
        return False
    return _severity_rank(event.severity) >= _min_rank()


def _extract_json(raw: str | None) -> dict | None:
    """Best-effort pull a JSON object out of a model reply (handles ``` fences)."""

    if not raw:
        return None
    text = raw.strip()
    if text.startswith("```"):
        text = text.strip("`").strip()
        if text[:4].lower() == "json":
            text = text[4:].strip()
    start = text.find("{")
    end = text.rfind("}")
    candidate = text[start : end + 1] if start != -1 and end > start else text
    try:
        obj = json.loads(candidate)
    except (ValueError, TypeError):
        return None
    return obj if isinstance(obj, dict) else None


def _normalize(obj: dict, fallback_severity: str) -> VerificationVerdict | None:
    """Coerce a loosely-shaped verdict dict into a validated verdict."""

    try:
        try:
            confidence = float(obj.get("confidence"))
        except (TypeError, ValueError):
            confidence = 0.5
        confidence = min(1.0, max(0.0, confidence))

        severity = str(obj.get("severity", "")).lower()
        if severity not in _SEVERITY_ORDER:
            severity = fallback_severity if fallback_severity in _SEVERITY_ORDER else "medium"

        summary = obj.get("summary")
        summary = str(summary) if summary else "No summary provided."

        return VerificationVerdict(
            verified=bool(obj.get("verified")),
            confidence=confidence,
            severity=severity,
            summary=summary,
            recommended_action=str(obj.get("recommended_action") or "notify"),
            tool_requests=obj.get("tool_requests") if isinstance(obj.get("tool_requests"), list) else [],
        )
    except Exception:  # noqa: BLE001 - any malformed field falls back to degraded
        return None


_REPAIR_NUDGE = (
    "Your previous reply was not valid JSON. Reply with ONLY the JSON verdict "
    "object described in the system prompt — no markdown, no commentary."
)


def _assistant_message(response: QwenResponse) -> dict:
    message: dict = {"role": "assistant", "content": response.content or ""}
    if response.tool_calls:
        message["tool_calls"] = [
            {
                "id": call.id,
                "type": "function",
                "function": {"name": call.name, "arguments": json.dumps(call.arguments)},
            }
            for call in response.tool_calls
        ]
    return message


def _tool_message(call_id: str, result: ToolResult) -> dict:
    return {
        "role": "tool",
        "tool_call_id": call_id,
        "content": json.dumps(result.summary_for_model(), default=str),
    }


def _image_message(image_b64: str) -> dict:
    return {
        "role": "user",
        "content": [
            {"type": "text", "text": "Here is the requested live snapshot."},
            {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"}},
        ],
    }


async def _agentic_verify(
    client: qwen_client.BaseQwenClient,
    request: VerificationRequest,
    context: ToolContext,
) -> VerificationVerdict | None:
    """Tool-calling loop: let the model gather evidence, then return a verdict.

    Offers MCP tools for up to ``qwen_max_tool_turns`` rounds, executing each
    requested tool and feeding results (and any snapshot image) back. When the
    model replies without tool calls we parse the verdict, with one repair
    re-ask on malformed JSON; otherwise verification degrades (returns None).
    """

    messages = build_verification_messages(request)
    tool_specs = get_tool_specs()
    max_turns = settings.qwen_max_tool_turns
    turns = 0
    repaired = False

    while True:
        offer_tools = tool_specs if turns < max_turns else None
        try:
            response = await client.chat(messages, tools=offer_tools)
        except QwenError:
            return None
        turns += 1

        if offer_tools is not None and response.tool_calls:
            messages.append(_assistant_message(response))
            for call in response.tool_calls:
                result = await execute_tool(call, context)
                messages.append(_tool_message(call.id, result))
                if result.image_b64:
                    messages.append(_image_message(result.image_b64))
            continue

        obj = _extract_json(response.content)
        if obj is not None:
            verdict = _normalize(obj, request.severity)
            if verdict is not None:
                return verdict
        if not repaired:
            repaired = True
            messages.append({"role": "user", "content": _REPAIR_NUDGE})
            continue
        return None


async def _recent_events(session, event: Event) -> list[dict]:
    result = await session.execute(
        select(Event)
        .where(Event.device_id == event.device_id, Event.event_id != event.event_id)
        .order_by(Event.timestamp.desc())
        .limit(_RECENT_EVENTS_LIMIT)
    )
    return [
        {
            "event_type": e.event_type,
            "severity": e.severity,
            "summary": e.summary,
            "status": e.status,
            "timestamp": e.timestamp.isoformat() if e.timestamp else None,
        }
        for e in result.scalars()
    ]


async def run_verification(event_id: str) -> None:
    """Verify ``event_id`` and persist the outcome. Safe to fire-and-forget."""

    async with async_session_factory() as session:
        event = await session.get(Event, event_id)
        if event is None:
            return
        agent = await session.get(Agent, event.agent_id)
        device = await session.get(Device, event.device_id)

        request = VerificationRequest(
            event_id=event.event_id,
            rule=agent.nl_rule if agent else "",
            compiled_prompt=agent.compiled_prompt if agent else None,
            event_type=event.event_type,
            severity=event.severity,
            summary=event.summary,
            confidence=event.confidence,
            stage1_result=event.stage1_result,
            stage2_verdict=event.stage2_verdict,
            device_name=device.name if device else event.device_id,
            device_location=device.location if device else None,
            recent_events=await _recent_events(session, event),
        )

        client = qwen_client.get_qwen_client()
        context = ToolContext(
            event_id=event.event_id,
            user_id=event.user_id,
            device_id=event.device_id,
            session=session,
        )
        verdict = await _agentic_verify(client, request, context)

        if verdict is None:
            event.degraded = True
            event.stage3_verdict = {"status": "degraded", "reason": "verification_unavailable"}
        else:
            event.stage3_verdict = verdict.model_dump()
            event.confidence = verdict.confidence
            event.severity = verdict.severity
            event.status = "verified" if verdict.verified else "false_positive"
        event.updated_at = datetime.now(UTC)
        await session.commit()
        await session.refresh(event)

        await realtime_bus.publish(
            event.user_id,
            "event.verified",
            {
                "event_id": event.event_id,
                "device_id": event.device_id,
                "agent_id": event.agent_id,
                "status": event.status,
                "severity": event.severity,
                "confidence": event.confidence,
                "summary": event.summary,
                "degraded": event.degraded,
                "verified": verdict.verified if verdict else None,
            },
        )

        # Re-evaluate alerting now that severity/status reflect the verdict.
        # Best-effort: alert failures must not surface from a background task.
        try:
            await alert_service.maybe_alert_for_event(session, event)
        except Exception:  # noqa: BLE001 - alerting is best-effort
            pass
