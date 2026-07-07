"""Backend-side demo camera simulation (judge/demo account only).

Replaces the laptop edge for demo cameras: instead of a device pushing frames
and a local YOLO+Ollama pipeline, the backend itself plays pre-extracted video
frames into the live-view broker and triages them with the cloud VLM API
(``qwen_client`` -> DashScope). One cloud LLM call per keyframe does detection +
triage together.

Strictly scoped so normal accounts are untouched:
  * ``settings.demo_simulation_enabled`` must be true, AND
  * the device id must start with ``settings.demo_sim_device_prefix``, AND
  * a frame folder ``data/demo_frames/<camera_key>/`` must exist with JPEGs
    (produced offline by ``scripts/extract_demo_frames.py``).

On-demand: a camera's loop starts when a viewer opens its live view (the stream
endpoints call :meth:`DemoSimulator.touch`) and self-stops after
``demo_sim_idle_timeout_seconds`` with no further viewer activity.
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import secrets
import time
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import REPO_ROOT, settings
from app.db.session import async_session_factory
from app.models.agent import Agent
from app.models.device import Device
from app.models.event import Event
from app.services import alert_service, qwen_client
from app.services.qwen_client import QwenError
from app.services.realtime_bus import realtime_bus
from app.services.video_stream_broker import video_stream_broker


_logger = logging.getLogger(__name__)


def _frames_root() -> Path:
    """Where pre-extracted demo frames live (configurable for deployment)."""
    configured = settings.demo_frames_dir
    return Path(configured) if configured else REPO_ROOT / "data" / "demo_frames"

_SYSTEM_PROMPT = (
    "You are a security camera vision analyst. You are given one still frame from a "
    "camera and a monitoring rule. Decide whether the rule is currently triggered by "
    "what is visible in THIS frame. Be conservative: only trigger when the frame "
    "clearly shows it. Reply with ONLY a JSON object, no markdown, of the form: "
    '{"triggered": true|false, "event_type": "person_detected|vehicle_detected|'
    'pet_detected|object_detected|baby_crying|audio_threat", "severity": "low|medium|high", '
    '"confidence": 0.0-1.0, "summary": "one short sentence"}.'
)

_SEVERITY = {"low", "medium", "high", "critical"}


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


@dataclass
class _CameraSim:
    device_id: str
    user_id: str
    frames: list[Path]
    last_activity: float
    task: asyncio.Task | None = None
    last_event_monotonic: float = field(default=0.0)
    triage_in_flight: bool = False


class DemoSimulator:
    def __init__(self) -> None:
        self._sims: dict[str, _CameraSim] = {}
        self._lock = asyncio.Lock()

    # --- gating -----------------------------------------------------------
    def _camera_key(self, device_id: str) -> str:
        prefix = settings.demo_sim_device_prefix
        return device_id[len(prefix):] if device_id.startswith(prefix) else device_id

    def _frames_dir(self, device_id: str) -> Path:
        return _frames_root() / self._camera_key(device_id)

    def _list_frames(self, device_id: str) -> list[Path]:
        directory = self._frames_dir(device_id)
        if not directory.is_dir():
            return []
        return sorted(directory.glob("*.jpg"))

    def is_demo_device(self, device_id: str) -> bool:
        return (
            settings.demo_simulation_enabled
            and device_id.startswith(settings.demo_sim_device_prefix)
        )

    # --- lifecycle --------------------------------------------------------
    async def touch(self, device_id: str, user_id: str) -> None:
        """Signal that a viewer is watching ``device_id``; start the loop if idle."""

        if not self.is_demo_device(device_id):
            return
        now = time.monotonic()
        async with self._lock:
            sim = self._sims.get(device_id)
            if sim is not None and sim.task is not None and not sim.task.done():
                sim.last_activity = now
                return
            frames = self._list_frames(device_id)
            if not frames:
                return
            sim = _CameraSim(device_id=device_id, user_id=user_id, frames=frames, last_activity=now)
            sim.task = asyncio.create_task(self._run(sim))
            self._sims[device_id] = sim
            _logger.info("demo_sim: started camera %s (%d frames)", device_id, len(frames))

    def keepalive(self, device_id: str) -> None:
        """O(1) refresh of viewer activity for an already-running sim (MJPEG hold)."""

        sim = self._sims.get(device_id)
        if sim is not None:
            sim.last_activity = time.monotonic()

    async def _run(self, sim: _CameraSim) -> None:
        await video_stream_broker.start_publishing(sim.device_id)
        frame_interval = 1.0 / max(1.0, settings.demo_sim_fps)
        idx = 0
        last_triage = 0.0
        try:
            while True:
                now = time.monotonic()
                if now - sim.last_activity > settings.demo_sim_idle_timeout_seconds:
                    break
                try:
                    frame_bytes = sim.frames[idx % len(sim.frames)].read_bytes()
                except OSError:
                    frame_bytes = b""
                idx += 1
                if frame_bytes:
                    await video_stream_broker.publish(sim.device_id, frame_bytes)
                    # Until the first event lands, retry quickly so opening a
                    # camera surfaces a detection fast; then use the slow cadence.
                    interval = (
                        settings.demo_sim_first_triage_interval_seconds
                        if sim.last_event_monotonic == 0.0
                        else settings.demo_sim_triage_interval_seconds
                    )
                    if now - last_triage >= interval:
                        last_triage = now
                        # Fire-and-forget so a slow LLM call never stalls playback.
                        asyncio.create_task(self._maybe_triage(sim, frame_bytes))
                await asyncio.sleep(frame_interval)
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - a sim must never crash the request loop
            _logger.exception("demo_sim: camera %s loop failed", sim.device_id)
        finally:
            await video_stream_broker.stop_publishing(sim.device_id)
            async with self._lock:
                if self._sims.get(sim.device_id) is sim:
                    self._sims.pop(sim.device_id, None)
            _logger.info("demo_sim: stopped camera %s", sim.device_id)

    # --- triage + event creation -----------------------------------------
    async def _maybe_triage(self, sim: _CameraSim, frame_bytes: bytes) -> None:
        # Cooldown: don't spend API calls or spawn events back-to-back.
        if time.monotonic() - sim.last_event_monotonic < settings.demo_sim_event_cooldown_seconds:
            return
        # Single-flight: with the fast first-detection cadence, calls could
        # otherwise overlap and create duplicate events on open.
        if sim.triage_in_flight:
            return
        sim.triage_in_flight = True
        try:
            async with async_session_factory() as session:
                agent = await self._armed_agent(session, sim.device_id, sim.user_id)
                if agent is None:
                    return
                device = await session.get(Device, sim.device_id)
                verdict = await self._triage_frame(frame_bytes, agent, device)
                if verdict and bool(verdict.get("triggered")):
                    sim.last_event_monotonic = time.monotonic()
                    await self._create_event(session, sim, agent, device, verdict)
        except Exception:  # noqa: BLE001 - triage is best-effort
            _logger.exception("demo_sim: triage failed for %s", sim.device_id)
        finally:
            sim.triage_in_flight = False

    async def _armed_agent(self, session: AsyncSession, device_id: str, user_id: str) -> Agent | None:
        result = await session.execute(
            select(Agent)
            .where(
                Agent.device_id == device_id,
                Agent.user_id == user_id,
                Agent.enabled.is_(True),
                Agent.state == "armed",
            )
            .order_by(Agent.created_at.desc())
        )
        return result.scalars().first()

    async def _triage_frame(self, frame_bytes: bytes, agent: Agent, device: Device | None) -> dict | None:
        client = qwen_client.get_qwen_client()
        b64 = base64.b64encode(frame_bytes).decode("ascii")
        cfg = agent.compiled_edge_config or {}
        classes = cfg.get("classes") or []
        device_name = device.name if device else agent.device_id
        location = (device.location if device else None) or "unknown"
        prompt = (
            f"Camera: {device_name} (location: {location}).\n"
            f"Monitoring rule: {agent.nl_rule}\n"
            f"Detector classes of interest: {', '.join(classes) if classes else 'any'}.\n"
            "Is this rule triggered in the frame right now?"
        )
        messages = [
            {"role": "system", "content": _SYSTEM_PROMPT},
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
                ],
            },
        ]
        try:
            response = await client.chat(messages)
        except QwenError:
            return None
        return _extract_json(response.content)

    async def _create_event(
        self,
        session: AsyncSession,
        sim: _CameraSim,
        agent: Agent,
        device: Device | None,
        verdict: dict,
    ) -> None:
        now = datetime.now(UTC)
        severity = str(verdict.get("severity", "")).lower()
        if severity not in _SEVERITY:
            severity = "medium"
        try:
            confidence = min(1.0, max(0.0, float(verdict.get("confidence"))))
        except (TypeError, ValueError):
            confidence = 0.7
        event_type = str(verdict.get("event_type") or "object_detected")
        summary = str(verdict.get("summary") or "Demo simulation detection.")

        event = Event(
            event_id=f"evt_sim_{secrets.token_urlsafe(12)}",
            user_id=sim.user_id,
            agent_id=agent.agent_id,
            device_id=sim.device_id,
            idempotency_key=f"{sim.device_id}-sim-{int(now.timestamp() * 1000)}",
            timestamp=now,
            event_type=event_type,
            stage1_result={"source": "demo_sim", "detector": (agent.compiled_edge_config or {}).get("classes")},
            stage2_verdict={"matched_rule": True, "source": "demo_sim"},
            stage3_verdict={
                "verified": True,
                "source": "demo_sim_vlm",
                "confidence": confidence,
                "summary": summary,
            },
            severity=severity,
            confidence=confidence,
            summary=summary,
            degraded=False,
            status="verified",
            created_at=now,
            updated_at=now,
        )
        session.add(event)
        await session.commit()
        await session.refresh(event)
        _logger.info("demo_sim: event %s on %s (%s)", event.event_id, sim.device_id, severity)

        await realtime_bus.publish(
            event.user_id,
            "event.created",
            {
                "event_id": event.event_id,
                "device_id": event.device_id,
                "agent_id": event.agent_id,
                "severity": event.severity,
                "status": event.status,
                "timestamp": event.timestamp,
                "summary": event.summary,
            },
        )
        try:
            await alert_service.maybe_alert_for_event(session, event)
        except Exception:  # noqa: BLE001 - alerting is best-effort
            pass


demo_simulator = DemoSimulator()
