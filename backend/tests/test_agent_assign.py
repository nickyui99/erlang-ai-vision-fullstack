import asyncio
from datetime import UTC, datetime
import os
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///C:/tmp/sentineledge_assign_pytest.db"

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
    client.cookies.set("sentineledge_session", create_session_token("usr_as"))
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

    # Unassigning deletes the sub-agent; the definition remains.
    removed = client.post(
        f"/api/v1/agents/{definition_id}/unassign",
        json={"device_id": "dev_as"},
    )
    assert removed.status_code == 200
    remaining = client.get("/api/v1/agents").json()["data"]
    assert len(remaining) == 1
    assert remaining[0]["agent_id"] == definition_id

    # Unassigning when nothing is assigned is a 404.
    missing = client.post(
        f"/api/v1/agents/{definition_id}/unassign",
        json={"device_id": "dev_as"},
    )
    assert missing.status_code == 404
