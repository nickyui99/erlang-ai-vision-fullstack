import asyncio
from datetime import UTC, datetime
import os
from pathlib import Path
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{(Path(tempfile.gettempdir()) / 'erlang_m9_pytest.db').as_posix()}"
os.environ["VERIFICATION_ENABLED"] = "true"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import select  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.core.security import create_session_token, hash_edge_token  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import async_session_factory, engine  # noqa: E402
from app.main import app  # noqa: E402
from app.mcp import permissions  # noqa: E402
from app.mcp.permissions import PanRateLimiter, clamp_pan, clamp_tilt  # noqa: E402
from app.mcp.tools import ToolContext, execute_tool  # noqa: E402
from app.models.agent import Agent  # noqa: E402
from app.models.device import Device  # noqa: E402
from app.models.event import Event  # noqa: E402
from app.models.tool_audit import ToolAudit  # noqa: E402
from app.models.user import User  # noqa: E402
from app.services import verification_service  # noqa: E402
from app.services.qwen_client import (  # noqa: E402
    BaseQwenClient,
    QwenResponse,
    QwenTimeoutError,
    QwenToolCall,
)
from app.services.video_stream_broker import video_stream_broker  # noqa: E402


EDGE_TOKEN = "edge-token-m9"
EDGE_HEADERS = {"Authorization": f"Bearer {EDGE_TOKEN}"}


def setup_module() -> None:
    # The VERIFICATION_ENABLED env var only takes effect when this module is
    # the first to import app config; settings are cached process-wide, so in
    # a full-suite run the flag must be forced on the live settings object.
    settings.verification_enabled = True


def teardown_module() -> None:
    settings.verification_enabled = False


def setup_function() -> None:
    asyncio.run(_reset_db())
    permissions.pan_rate_limiter.reset()
    video_stream_broker._latest.clear()


async def _reset_db() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)

    now = datetime.now(UTC)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as session:
        session.add(
            User(
                user_id="usr_m9",
                google_sub="gsub_m9",
                email="m9@example.com",
                email_verified=True,
                role="user",
                created_at=now,
                updated_at=now,
            )
        )
        await session.commit()
        session.add(
            Device(
                device_id="dev_m9",
                user_id="usr_m9",
                edge_token_hash=hash_edge_token(EDGE_TOKEN),
                name="Front Door",
                health_status="online",
                current_pan=90,
                current_tilt=90,
                created_at=now,
                updated_at=now,
            )
        )
        await session.commit()
        session.add(
            Agent(
                agent_id="agt_m9",
                user_id="usr_m9",
                device_id="dev_m9",
                name="Intruder watch",
                nl_rule="Alert on people loitering at night",
                compiled_prompt="Watch for a person lingering near the door.",
                state="armed",
                enabled=True,
                created_at=now,
                updated_at=now,
            )
        )
        await session.commit()


def _client() -> TestClient:
    return TestClient(app)


def _user_client(user_id: str = "usr_m9") -> TestClient:
    client = TestClient(app)
    client.cookies.set("erlang_session", create_session_token(user_id))
    return client


def _post_event(client: TestClient, *, severity: str, idem: str, event_id: str | None = None):
    body = {
        "agent_id": "agt_m9",
        "timestamp": datetime.now(UTC).isoformat(),
        "event_type": "person_detected",
        "severity": severity,
        "summary": "Person at the front door",
        "idempotency_key": idem,
    }
    if event_id:
        body["event_id"] = event_id
    return client.post("/api/v1/edge/events", json=body, headers=EDGE_HEADERS)


def _event(event_id: str) -> Event | None:
    async def _q() -> Event | None:
        async with async_session_factory() as session:
            result = await session.execute(select(Event).where(Event.event_id == event_id))
            return result.scalar_one_or_none()

    return asyncio.run(_q())


def _audits(event_id: str) -> list[ToolAudit]:
    async def _q() -> list[ToolAudit]:
        async with async_session_factory() as session:
            result = await session.execute(
                select(ToolAudit).where(ToolAudit.event_id == event_id).order_by(ToolAudit.timestamp.asc())
            )
            return list(result.scalars())

    return asyncio.run(_q())


async def _insert_event(session, event_id: str, *, severity: str = "high") -> None:
    now = datetime.now(UTC)
    session.add(
        Event(
            event_id=event_id,
            user_id="usr_m9",
            agent_id="agt_m9",
            device_id="dev_m9",
            idempotency_key=event_id,
            timestamp=now,
            event_type="person_detected",
            severity=severity,
            status="candidate",
            degraded=False,
            created_at=now,
            updated_at=now,
        )
    )
    await session.commit()


class _ScriptedClient(BaseQwenClient):
    """Drives the verification loop with canned ``chat`` turns.

    Each turn is either a content string (a would-be verdict) or a list of
    ``QwenToolCall`` (a tool round). ``exc`` makes the first call raise.
    """

    def __init__(self, turns: list | None = None, exc: Exception | None = None) -> None:
        self._turns = list(turns or [])
        self._exc = exc
        self.calls = 0

    async def verify(self, request, *, repair: bool = False) -> str:  # required by ABC
        return "{}"

    async def chat(self, messages, *, tools=None) -> QwenResponse:
        self.calls += 1
        if self._exc is not None:
            raise self._exc
        turn = self._turns.pop(0) if self._turns else ""
        if isinstance(turn, list):
            return QwenResponse(content=None, tool_calls=turn)
        return QwenResponse(content=turn, tool_calls=[])


# --- 9A: happy path via the offline mock client -----------------------------


def test_high_severity_event_is_verified_and_stored() -> None:
    client = _client()
    response = _post_event(client, severity="high", idem="idem-high", event_id="evt_high")

    assert response.status_code == 201
    event = _event("evt_high")
    assert event is not None
    assert event.status == "verified"
    assert event.stage3_verdict is not None
    assert event.stage3_verdict["verified"] is True
    assert event.confidence == 0.9
    assert event.degraded is False


def test_low_severity_event_is_not_verified() -> None:
    client = _client()
    response = _post_event(client, severity="low", idem="idem-low", event_id="evt_low")

    assert response.status_code == 201
    event = _event("evt_low")
    assert event is not None
    assert event.status == "candidate"
    assert event.stage3_verdict is None


def test_verification_disabled_leaves_event_untouched(monkeypatch) -> None:
    monkeypatch.setattr(verification_service.settings, "verification_enabled", False)
    client = _client()
    response = _post_event(client, severity="critical", idem="idem-off", event_id="evt_off")

    assert response.status_code == 201
    event = _event("evt_off")
    assert event is not None
    assert event.status == "candidate"
    assert event.stage3_verdict is None


# --- 9A: verdict outcomes via scripted chat ---------------------------------


def test_negative_verdict_marks_false_positive(monkeypatch) -> None:
    monkeypatch.setattr(verification_service.settings, "verify_min_severity", "low")
    reply = '{"verified": false, "confidence": 0.2, "severity": "low", "summary": "Just a cat", "recommended_action": "ignore"}'
    monkeypatch.setattr(
        verification_service.qwen_client, "get_qwen_client", lambda: _ScriptedClient(turns=[reply])
    )
    client = _client()
    response = _post_event(client, severity="low", idem="idem-fp", event_id="evt_fp")

    assert response.status_code == 201
    event = _event("evt_fp")
    assert event.status == "false_positive"
    assert event.stage3_verdict["verified"] is False
    assert event.confidence == 0.2


def test_markdown_fenced_json_is_parsed(monkeypatch) -> None:
    reply = '```json\n{"verified": true, "confidence": 0.77, "severity": "critical", "summary": "Intruder"}\n```'
    monkeypatch.setattr(
        verification_service.qwen_client, "get_qwen_client", lambda: _ScriptedClient(turns=[reply])
    )
    client = _client()
    response = _post_event(client, severity="high", idem="idem-fence", event_id="evt_fence")

    assert response.status_code == 201
    event = _event("evt_fence")
    assert event.status == "verified"
    assert event.severity == "critical"
    assert event.confidence == 0.77


def test_malformed_output_after_repair_marks_degraded(monkeypatch) -> None:
    scripted = _ScriptedClient(turns=["not json at all", "still not json"])
    monkeypatch.setattr(
        verification_service.qwen_client, "get_qwen_client", lambda: scripted
    )
    client = _client()
    response = _post_event(client, severity="high", idem="idem-bad", event_id="evt_bad")

    assert response.status_code == 201
    event = _event("evt_bad")
    assert event.degraded is True
    assert event.stage3_verdict == {"status": "degraded", "reason": "verification_unavailable"}
    assert event.status == "candidate"
    assert scripted.calls == 2  # initial reply + one repair re-ask


def test_qwen_timeout_marks_degraded_and_ingestion_succeeds(monkeypatch) -> None:
    monkeypatch.setattr(
        verification_service.qwen_client,
        "get_qwen_client",
        lambda: _ScriptedClient(exc=QwenTimeoutError("timed out")),
    )
    client = _client()
    response = _post_event(client, severity="critical", idem="idem-timeout", event_id="evt_timeout")

    assert response.status_code == 201
    event = _event("evt_timeout")
    assert event.degraded is True
    assert event.stage3_verdict["status"] == "degraded"


# --- 9B: MCP tools (unit) ---------------------------------------------------


def test_pan_rate_limiter_enforces_count() -> None:
    limiter = PanRateLimiter(max_pans=3, min_interval=0)
    results = [limiter.check_and_register("evt", now=float(i)) for i in range(4)]
    assert [ok for ok, _ in results] == [True, True, True, False]
    assert "pan limit reached" in results[3][1]


def test_pan_rate_limiter_enforces_interval() -> None:
    limiter = PanRateLimiter(max_pans=10, min_interval=5)
    assert limiter.check_and_register("evt", now=0.0)[0] is True
    too_soon_ok, reason = limiter.check_and_register("evt", now=2.0)
    assert too_soon_ok is False and "too soon" in reason
    assert limiter.check_and_register("evt", now=6.0)[0] is True


def test_pan_rate_limiter_window_does_not_lock_out_forever() -> None:
    # The chat path keys by user and passes a window: after the cap is hit, moves
    # older than the window are forgotten, so the user regains control instead of
    # being locked out for the life of the process (the earlier bug).
    limiter = PanRateLimiter(max_pans=3, min_interval=0)
    key = "chat:usr_1"
    for i in range(3):
        assert limiter.check_and_register(key, now=float(i), window=60.0)[0] is True
    # 4th within the window is capped...
    capped_ok, reason = limiter.check_and_register(key, now=3.0, window=60.0)
    assert capped_ok is False and "pan limit reached" in reason
    # ...but once the window has rolled past the earliest moves, it allows again.
    assert limiter.check_and_register(key, now=61.0, window=60.0)[0] is True


def test_clamp_pan() -> None:
    assert clamp_pan(200) == 165
    assert clamp_pan(-5) == 15
    assert clamp_pan("nonsense") == 90


def test_clamp_tilt() -> None:
    assert clamp_tilt(200) == 140
    assert clamp_tilt(-5) == 60
    assert clamp_tilt("nonsense") == 90


def test_tilt_camera_is_permitted_and_audited() -> None:
    async def _run():
        async with async_session_factory() as session:
            await _insert_event(session, "evt_tilt")
            ctx = ToolContext("evt_tilt", "usr_m9", "dev_m9", session)
            result = await execute_tool(
                QwenToolCall("c1", "tilt_camera", {"angle": 120}), ctx
            )
            audits = (
                await session.execute(select(ToolAudit).where(ToolAudit.event_id == "evt_tilt"))
            ).scalars().all()
            return result, list(audits)

    result, audits = asyncio.run(_run())
    # No edge is connected in tests, so it reports edge_unavailable rather than
    # tool_not_permitted — the point is the tool is permitted and audited.
    assert result.error != "tool_not_permitted"
    assert len(audits) == 1
    assert audits[0].tool_name == "tilt_camera"


def test_tool_specs_advertise_pan_and_tilt() -> None:
    from app.mcp.schemas import get_tool_specs

    names = {spec["function"]["name"] for spec in get_tool_specs()}
    assert {"pan_camera", "tilt_camera"} <= names


def test_denied_tool_is_refused_and_audited() -> None:
    async def _run():
        async with async_session_factory() as session:
            await _insert_event(session, "evt_deny")
            ctx = ToolContext("evt_deny", "usr_m9", "dev_m9", session)
            result = await execute_tool(QwenToolCall("c1", "disarm_agent", {}), ctx)
            audits = (
                await session.execute(select(ToolAudit).where(ToolAudit.event_id == "evt_deny"))
            ).scalars().all()
            return result, list(audits)

    result, audits = asyncio.run(_run())
    assert result.ok is False
    assert result.error == "tool_not_permitted"
    assert len(audits) == 1
    assert audits[0].called_by == "agent"
    assert audits[0].tool_name == "disarm_agent"


def test_get_live_snapshot_uses_latest_frame() -> None:
    video_stream_broker._latest["dev_m9"] = b"\xff\xd8fakejpeg\xff\xd9"
    try:
        async def _run():
            async with async_session_factory() as session:
                await _insert_event(session, "evt_snap")
                ctx = ToolContext("evt_snap", "usr_m9", "dev_m9", session)
                return await execute_tool(QwenToolCall("c1", "get_live_snapshot", {}), ctx)

        result = asyncio.run(_run())
    finally:
        video_stream_broker._latest.pop("dev_m9", None)

    assert result.ok is True
    assert result.image_b64 is not None
    assert result.data["source"] == "live_frame"


def test_get_device_status_reads_device() -> None:
    async def _run():
        async with async_session_factory() as session:
            await _insert_event(session, "evt_status")
            ctx = ToolContext("evt_status", "usr_m9", "dev_m9", session)
            return await execute_tool(QwenToolCall("c1", "get_device_status", {}), ctx)

    result = asyncio.run(_run())
    assert result.ok is True
    assert result.data["health_status"] == "online"
    assert result.data["current_pan"] == 90


# --- 9C: agentic tool-calling loop ------------------------------------------


def test_agent_loop_runs_tools_then_verdicts(monkeypatch) -> None:
    turns = [
        [QwenToolCall("c1", "get_live_snapshot", {})],
        [QwenToolCall("c2", "pan_camera", {"angle": 120})],
        '{"verified": true, "confidence": 0.95, "severity": "high", "summary": "Confirmed intruder"}',
    ]
    monkeypatch.setattr(
        verification_service.qwen_client, "get_qwen_client", lambda: _ScriptedClient(turns=turns)
    )
    client = _client()
    response = _post_event(client, severity="high", idem="idem-loop", event_id="evt_loop")

    assert response.status_code == 201
    event = _event("evt_loop")
    assert event.status == "verified"
    assert event.confidence == 0.95

    audits = _audits("evt_loop")
    tool_names = {a.tool_name for a in audits}
    assert {"get_live_snapshot", "pan_camera"} <= tool_names
    assert all(a.called_by == "agent" for a in audits)


def test_agent_loop_enforces_pan_limit(monkeypatch) -> None:
    # Remove the time interval so this test isolates the per-event count cap.
    monkeypatch.setattr(settings, "mcp_min_seconds_between_pans", 0)
    turns = [
        [QwenToolCall(f"c{i}", "pan_camera", {"angle": 100 + i})] for i in range(4)
    ] + ['{"verified": true, "confidence": 0.8, "severity": "high", "summary": "ok"}']
    monkeypatch.setattr(
        verification_service.qwen_client, "get_qwen_client", lambda: _ScriptedClient(turns=turns)
    )
    client = _client()
    response = _post_event(client, severity="high", idem="idem-panlimit", event_id="evt_panlimit")

    assert response.status_code == 201
    pan_audits = [a for a in _audits("evt_panlimit") if a.tool_name == "pan_camera"]
    assert len(pan_audits) == 4
    denied = [a for a in pan_audits if a.result and "pan limit reached" in (a.result.get("error") or "")]
    assert len(denied) == 1  # the 4th pan is rejected by the limiter


# --- audit trail endpoint ---------------------------------------------------


def test_event_audit_endpoint_returns_agent_trail(monkeypatch) -> None:
    turns = [
        [QwenToolCall("c1", "get_live_snapshot", {})],
        [QwenToolCall("c2", "pan_camera", {"angle": 120})],
        '{"verified": true, "confidence": 0.9, "severity": "high", "summary": "ok"}',
    ]
    monkeypatch.setattr(
        verification_service.qwen_client, "get_qwen_client", lambda: _ScriptedClient(turns=turns)
    )
    _post_event(_client(), severity="high", idem="idem-audit", event_id="evt_audit")

    resp = _user_client().get("/api/v1/events/evt_audit/audit")
    assert resp.status_code == 200
    trail = resp.json()["data"]
    names = [row["tool_name"] for row in trail]
    assert "get_live_snapshot" in names and "pan_camera" in names
    assert all(row["called_by"] == "agent" for row in trail)
    # Oldest-first timeline ordering.
    assert [r["timestamp"] for r in trail] == sorted(r["timestamp"] for r in trail)


def test_event_audit_endpoint_rejects_non_owner() -> None:
    async def _seed():
        async with async_session_factory() as session:
            await _insert_event(session, "evt_priv")
            session.add(
                User(
                    user_id="usr_other",
                    google_sub="gsub_other",
                    email="other@example.com",
                    email_verified=True,
                    role="user",
                    created_at=datetime.now(UTC),
                    updated_at=datetime.now(UTC),
                )
            )
            await session.commit()

    asyncio.run(_seed())
    resp = _user_client("usr_other").get("/api/v1/events/evt_priv/audit")
    assert resp.status_code == 404
