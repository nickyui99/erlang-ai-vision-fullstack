import asyncio
from datetime import UTC, datetime
import os
from pathlib import Path
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{(Path(tempfile.gettempdir()) / 'erlang_m8_pytest.db').as_posix()}"

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import select  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402

from app.core.security import create_session_token, hash_edge_token  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models.agent import Agent  # noqa: E402
from app.models.alert import Alert  # noqa: E402
from app.models.device import Device  # noqa: E402
from app.models.push_token import PushToken  # noqa: E402
from app.models.user import User  # noqa: E402
from app.core.config import settings  # noqa: E402
from app.services import notification_service  # noqa: E402


EDGE_TOKEN = "edge-token-m8"
EDGE_HEADERS = {"Authorization": f"Bearer {EDGE_TOKEN}"}


# Captures FCM sends so tests assert on delivery without live credentials.
_sent: list[dict] = []


def setup_function() -> None:
    _sent.clear()
    asyncio.run(_reset_db())


def _fake_send(tokens, title, body, data=None):
    _sent.append({"tokens": list(tokens), "title": title, "body": body, "data": data or {}})
    return notification_service.PushResult(success_count=len(tokens))


def _patch_send(monkeypatch) -> None:
    monkeypatch.setattr(notification_service, "send_push", _fake_send)
    # alert_service imports the module, so patching the attribute is enough.


async def _reset_db() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)

    now = datetime.now(UTC)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as session:
        session.add(
            User(
                user_id="usr_m8",
                google_sub="gsub_m8",
                email="m8@example.com",
                email_verified=True,
                role="user",
                created_at=now,
                updated_at=now,
            )
        )
        await session.commit()
        session.add(
            Device(
                device_id="dev_m8",
                user_id="usr_m8",
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
                agent_id="agt_m8",
                user_id="usr_m8",
                device_id="dev_m8",
                name="Intruder watch",
                nl_rule="Alert on people at night",
                state="armed",
                enabled=True,
                created_at=now,
                updated_at=now,
            )
        )
        await session.commit()


def _user_client(user_id: str = "usr_m8") -> TestClient:
    client = TestClient(app)
    client.cookies.set("erlang_session", create_session_token(user_id))
    return client


def _alerts() -> list[Alert]:
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    async def _q() -> list[Alert]:
        async with session_factory() as session:
            result = await session.execute(select(Alert).order_by(Alert.created_at.asc()))
            return list(result.scalars())

    return asyncio.run(_q())


def _tokens() -> list[PushToken]:
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    async def _q() -> list[PushToken]:
        async with session_factory() as session:
            result = await session.execute(select(PushToken))
            return list(result.scalars())

    return asyncio.run(_q())


def _post_event(client: TestClient, *, severity: str, idem: str, event_id: str | None = None):
    body = {
        "agent_id": "agt_m8",
        "timestamp": datetime.now(UTC).isoformat(),
        "event_type": "person_detected",
        "severity": severity,
        "summary": "Person at the front door",
        "idempotency_key": idem,
    }
    if event_id:
        body["event_id"] = event_id
    return client.post("/api/v1/edge/events", json=body, headers=EDGE_HEADERS)


def test_register_push_token_is_idempotent() -> None:
    client = _user_client()
    first = client.post("/api/v1/notifications/tokens", json={"token": "tok-1", "platform": "web"})
    second = client.post("/api/v1/notifications/tokens", json={"token": "tok-1", "platform": "android"})

    assert first.status_code == 201
    assert second.status_code == 201
    assert first.json()["data"]["token_id"] == second.json()["data"]["token_id"]
    assert len(_tokens()) == 1
    assert _tokens()[0].platform == "android"


def test_high_severity_event_sends_push_alert(monkeypatch) -> None:
    _patch_send(monkeypatch)
    client = _user_client()
    client.post("/api/v1/notifications/tokens", json={"token": "tok-1"})

    response = _post_event(client, severity="high", idem="idem-high")
    assert response.status_code == 201

    alerts = _alerts()
    assert len(alerts) == 1
    assert alerts[0].channel == "fcm"
    assert alerts[0].status == "sent"
    assert alerts[0].sent_at is not None
    assert len(_sent) == 1
    assert _sent[0]["tokens"] == ["tok-1"]
    assert _sent[0]["data"]["event_id"] == response.json()["data"]["event_id"]


def test_low_severity_event_does_not_alert(monkeypatch) -> None:
    _patch_send(monkeypatch)
    # Pin the threshold: settings load the repo .env, so a dev box running with
    # ALERT_MIN_SEVERITY=low would otherwise flip this test's premise.
    monkeypatch.setattr(settings, "alert_min_severity", "high")
    client = _user_client()
    client.post("/api/v1/notifications/tokens", json={"token": "tok-1"})

    response = _post_event(client, severity="low", idem="idem-low")
    assert response.status_code == 201
    assert _alerts() == []
    assert _sent == []


def test_alert_is_deduplicated_per_event(monkeypatch) -> None:
    _patch_send(monkeypatch)
    client = _user_client()
    client.post("/api/v1/notifications/tokens", json={"token": "tok-1"})

    # Same idempotency key + event id -> ingestion returns the existing event,
    # so the alert must not be sent twice.
    first = _post_event(client, severity="critical", idem="idem-dup", event_id="evt_dup")
    second = _post_event(client, severity="critical", idem="idem-dup", event_id="evt_dup")

    assert first.status_code == 201
    assert second.status_code == 200
    assert len(_alerts()) == 1
    assert len(_sent) == 1


def test_high_severity_without_tokens_marks_no_recipients(monkeypatch) -> None:
    _patch_send(monkeypatch)
    client = _user_client()

    response = _post_event(client, severity="high", idem="idem-none")
    assert response.status_code == 201

    alerts = _alerts()
    assert len(alerts) == 1
    assert alerts[0].status == "no_recipients"
    assert _sent == []


def test_deregister_push_token(monkeypatch) -> None:
    client = _user_client()
    client.post("/api/v1/notifications/tokens", json={"token": "tok-1"})
    assert len(_tokens()) == 1

    response = client.delete("/api/v1/notifications/tokens/tok-1")
    assert response.status_code == 204
    assert _tokens() == []
