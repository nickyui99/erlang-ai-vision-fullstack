import asyncio
from datetime import UTC, datetime
import os
from pathlib import Path
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{(Path(tempfile.gettempdir()) / 'erlang_assign_pytest.db').as_posix()}"

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402

from app.core.security import create_session_token, hash_edge_token  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models.device import Device  # noqa: E402
from app.models.user import User  # noqa: E402


EDGE_TOKEN = "edge-token-assign"
EDGE_HEADERS = {"Authorization": f"Bearer {EDGE_TOKEN}"}


def setup_function() -> None:
    asyncio.run(_reset_db())


async def _reset_db() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as session:
        now = datetime.now(UTC)
        session.add(
            User(
                user_id="usr_as",
                google_sub="gsub_as",
                email="as@example.com",
                email_verified=True,
                role="user",
                created_at=now,
                updated_at=now,
            )
        )
        await session.commit()
        session.add(
            Device(
                device_id="dev_as",
                user_id="usr_as",
                edge_token_hash=hash_edge_token(EDGE_TOKEN),
                name="Front Door",
                health_status="online",
                current_pan=90,
                created_at=now,
                updated_at=now,
            )
        )
        await session.commit()


def _client() -> TestClient:
    client = TestClient(app)
    client.cookies.set("erlang_session", create_session_token("usr_as"))
    return client


def test_create_definition_assign_and_unassign() -> None:
    client = _client()

    # Creating an agent makes a device-less definition.
    created = client.post(
        "/api/v1/agents",
        json={"name": "Pet Watch", "nl_rule": "Alert if a pet jumps on the counter."},
    )
    assert created.status_code == 201
    definition = created.json()["data"]
    assert definition["device_id"] is None
    assert definition["parent_agent_id"] is None
    definition_id = definition["agent_id"]

    # Assigning clones it into a per-camera sub-agent (new id, armed).
    assigned = client.post(
        f"/api/v1/agents/{definition_id}/assign",
        json={"device_id": "dev_as"},
    )
    assert assigned.status_code == 200
    sub = assigned.json()["data"]
    assert sub["agent_id"] != definition_id
    assert sub["parent_agent_id"] == definition_id
    assert sub["device_id"] == "dev_as"
    assert sub["state"] == "armed"

    # Two rows now exist: the definition and the sub-agent.
    listed = client.get("/api/v1/agents").json()["data"]
    assert len(listed) == 2

    # Assigning again is idempotent (no duplicate sub-agent).
    again = client.post(
        f"/api/v1/agents/{definition_id}/assign",
        json={"device_id": "dev_as"},
    )
    assert again.status_code == 200
    assert again.json()["data"]["agent_id"] == sub["agent_id"]
    assert len(client.get("/api/v1/agents").json()["data"]) == 2

    # The edge sees the armed sub-agent in its active config.
    active = client.get("/api/v1/edge/agents/active", headers=EDGE_HEADERS)
    assert active.status_code == 200
    active_ids = [item["agent_id"] for item in active.json()["data"]]
    assert sub["agent_id"] in active_ids

    # Unassigning DISARMS the sub-agent but keeps the row: its events/alerts/clips
    # cascade off this id, so deleting it would erase the camera's detection history.
    removed = client.post(
        f"/api/v1/agents/{definition_id}/unassign",
        json={"device_id": "dev_as"},
    )
    assert removed.status_code == 200
    remaining = client.get("/api/v1/agents").json()["data"]
    assert len(remaining) == 2
    disarmed = next(a for a in remaining if a["agent_id"] == sub["agent_id"])
    assert disarmed["state"] == "disarmed"

    # The edge no longer sees the disarmed sub-agent.
    active = client.get("/api/v1/edge/agents/active", headers=EDGE_HEADERS)
    assert sub["agent_id"] not in [item["agent_id"] for item in active.json()["data"]]

    # Unassigning an already-disarmed agent is still a 404 (not assigned).
    missing = client.post(
        f"/api/v1/agents/{definition_id}/unassign",
        json={"device_id": "dev_as"},
    )
    assert missing.status_code == 404

    # Re-assigning re-arms the SAME sub-agent (identity, and thus history, preserved).
    rearmed = client.post(
        f"/api/v1/agents/{definition_id}/assign",
        json={"device_id": "dev_as"},
    )
    assert rearmed.status_code == 200
    assert rearmed.json()["data"]["agent_id"] == sub["agent_id"]
    assert rearmed.json()["data"]["state"] == "armed"
    assert len(client.get("/api/v1/agents").json()["data"]) == 2


def test_assign_and_unassign_nudge_edge_refresh(monkeypatch) -> None:
    """Toggling an agent must nudge the device's bridge (command.refresh_agents) so the
    change takes effect immediately instead of on the next ~30s config poll."""
    from app.services.edge_command_hub import edge_command_hub

    calls: list[tuple[str, str]] = []

    async def fake_send_command(device_id: str, message: dict) -> dict:
        calls.append((device_id, message["type"]))
        return {"request_id": message["request_id"], "status": "ok", "payload": {}}

    monkeypatch.setattr(edge_command_hub, "send_command", fake_send_command)
    client = _client()

    definition_id = client.post(
        "/api/v1/agents",
        json={"name": "Nudge Watch", "nl_rule": "Alert me if a person appears."},
    ).json()["data"]["agent_id"]

    assert client.post(
        f"/api/v1/agents/{definition_id}/assign", json={"device_id": "dev_as"}
    ).status_code == 200
    assert calls == [("dev_as", "command.refresh_agents")]

    assert client.post(
        f"/api/v1/agents/{definition_id}/unassign", json={"device_id": "dev_as"}
    ).status_code == 200
    assert calls == [("dev_as", "command.refresh_agents")] * 2

    # Re-arming the retained sub-agent nudges too.
    assert client.post(
        f"/api/v1/agents/{definition_id}/assign", json={"device_id": "dev_as"}
    ).status_code == 200
    assert calls == [("dev_as", "command.refresh_agents")] * 3


def test_unassign_preserves_event_history() -> None:
    """Toggling an agent off a camera must not delete its events (the original bug:
    unassign hard-deleted the sub-agent and events/alerts cascaded away with it)."""
    client = _client()

    definition_id = client.post(
        "/api/v1/agents",
        json={"name": "Person Watch", "nl_rule": "Alert me if a person appears."},
    ).json()["data"]["agent_id"]
    sub = client.post(
        f"/api/v1/agents/{definition_id}/assign",
        json={"device_id": "dev_as"},
    ).json()["data"]

    # The edge escalates an event for the armed sub-agent.
    posted = client.post(
        "/api/v1/edge/events",
        headers=EDGE_HEADERS,
        json={
            "agent_id": sub["agent_id"],
            "timestamp": datetime.now(UTC).isoformat(),
            "event_type": "person",
            "severity": "medium",
            "confidence": 0.9,
            "summary": "A person appeared.",
            "idempotency_key": "evt-keep-1",
        },
    )
    assert posted.status_code in (200, 201), posted.text
    event_id = posted.json()["data"]["event_id"]

    # Disable the agent on the camera, then check the event is still there.
    removed = client.post(
        f"/api/v1/agents/{definition_id}/unassign",
        json={"device_id": "dev_as"},
    )
    assert removed.status_code == 200
    listed = client.get("/api/v1/events").json()["data"]
    assert event_id in [item["event_id"] for item in listed]


def test_delete_definition_cascades_sub_agents_and_events() -> None:
    client = _client()

    definition_id = client.post(
        "/api/v1/agents",
        json={"name": "Door Watch", "nl_rule": "Alert if a person is at the door."},
    ).json()["data"]["agent_id"]
    sub = client.post(
        f"/api/v1/agents/{definition_id}/assign",
        json={"device_id": "dev_as"},
    ).json()["data"]

    # An event exists on the armed sub-agent; deleting the DEFINITION removes the
    # sub-agent (parent FK cascade) and the event with it.
    posted = client.post(
        "/api/v1/edge/events",
        headers=EDGE_HEADERS,
        json={
            "agent_id": sub["agent_id"],
            "timestamp": datetime.now(UTC).isoformat(),
            "event_type": "person",
            "severity": "medium",
            "confidence": 0.9,
            "summary": "A person appeared.",
            "idempotency_key": "evt-del-1",
        },
    )
    assert posted.status_code in (200, 201), posted.text

    deleted = client.delete(f"/api/v1/agents/{definition_id}")
    assert deleted.status_code == 200
    body = deleted.json()["data"]
    assert body["deleted"] is True
    assert body["device_ids"] == ["dev_as"]

    assert client.get("/api/v1/agents").json()["data"] == []
    assert client.get("/api/v1/events").json()["data"] == []

    # Idempotence/ownership: a second delete (or a foreign agent id) is a 404.
    assert client.delete(f"/api/v1/agents/{definition_id}").status_code == 404
