"""Smoke tests for the configured database (SQLite locally, RDS PostgreSQL post-migration).

Default run (CI / local, temp SQLite):

    APP_ENV=test PYTHONPATH=backend pytest backend/tests/test_smoke_db.py -v

Validating a live Alibaba RDS instance after scripts/migrate_sqlite_to_rds.py
(run this file STANDALONE â€” in a full-suite run the first-imported module's
DATABASE_URL wins because the engine is created at import):

    APP_ENV=test PYTHONPATH=backend DATABASE_URL=postgresql+asyncpg://... \
        pytest backend/tests/test_smoke_db.py -v

or, when the DSN comes from the Alibaba KMS secret configured in .env:

    APP_ENV=test PYTHONPATH=backend SMOKE_USE_KMS=1 \
        pytest backend/tests/test_smoke_db.py -v

Against a real (non-SQLite) database the suite never drops or creates tables:
it only inserts rows keyed by *_smoketest IDs and deletes them again in
teardown. Set SMOKE_ALLOW_RESET=1 ONLY for a disposable PostgreSQL scratch DB
to get the full drop_all/create_all reset behaviour.
"""

import asyncio
import os
import sys
import tempfile
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
os.environ["APP_ENV"] = "test"
if os.environ.get("SMOKE_USE_KMS") != "1":
    # Default to a throwaway sqlite DB. SMOKE_USE_KMS=1 leaves DATABASE_URL
    # unset so the KMS loader supplies the RDS DSN (live-instance validation).
    os.environ.setdefault(
        "DATABASE_URL",
        f"sqlite+aiosqlite:///{(Path(tempfile.gettempdir()) / 'erlang_smoke_pytest.db').as_posix()}",
    )

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import delete, inspect, select, text  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402

from app.core.security import create_session_token, hash_edge_token  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models.agent import Agent  # noqa: E402
from app.models.device import Device  # noqa: E402
from app.models.event import Event  # noqa: E402
from app.models.user import User  # noqa: E402


ALEMBIC_HEAD = "20260623_0005"
APP_TABLES = {
    "users",
    "devices",
    "agents",
    "events",
    "clips",
    "recordings",
    "alerts",
    "push_tokens",
    "tool_audit",
}

IS_SQLITE = engine.url.get_backend_name() == "sqlite"
RESET_ALLOWED = IS_SQLITE or os.environ.get("SMOKE_ALLOW_RESET") == "1"

EDGE_TOKEN = "edge-token-smoke"
EDGE_HEADERS = {"Authorization": f"Bearer {EDGE_TOKEN}"}

session_factory = async_sessionmaker(engine, expire_on_commit=False)


def setup_function() -> None:
    asyncio.run(_prepare_db())


def teardown_function() -> None:
    asyncio.run(_delete_smoke_rows())


async def _prepare_db() -> None:
    if RESET_ALLOWED:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)
            await conn.run_sync(Base.metadata.create_all)
    await _delete_smoke_rows()
    await _seed_smoke_fixtures()


async def _delete_smoke_rows() -> None:
    # ondelete=CASCADE FKs remove the smoke user's devices/agents/events/
    # clips/recordings/alerts/tool_audit; never touches other rows or DDL.
    async with session_factory() as session:
        await session.execute(delete(User).where(User.user_id == "usr_smoketest"))
        await session.commit()


async def _seed_smoke_fixtures() -> None:
    now = datetime.now(UTC)
    async with session_factory() as session:
        session.add(
            User(
                user_id="usr_smoketest",
                google_sub="gsub_smoketest",
                email="smoketest@example.com",
                email_verified=True,
                role="user",
                created_at=now,
                updated_at=now,
            )
        )
        await session.commit()
        session.add(
            Device(
                device_id="dev_smoketest",
                user_id="usr_smoketest",
                edge_token_hash=hash_edge_token(EDGE_TOKEN),
                name="Smoke Cam",
                health_status="online",
                current_pan=90,
                created_at=now,
                updated_at=now,
            )
        )
        await session.commit()
        session.add(
            Agent(
                agent_id="agt_smoketest",
                user_id="usr_smoketest",
                device_id="dev_smoketest",
                name="Smoke Watch",
                nl_rule="watch",
                compiled_prompt="watch",
                compiled_edge_config={"detectors": ["person"], "min_confidence": 0.75},
                state="armed",
                enabled=True,
                created_at=now,
                updated_at=now,
            )
        )
        await session.commit()


def _client() -> TestClient:
    client = TestClient(app)
    client.cookies.set("erlang_session", create_session_token("usr_smoketest"))
    return client


def _event_payload(idempotency_key: str = "dev_smoketest-evt-1", **overrides) -> dict:
    payload = {
        "agent_id": "agt_smoketest",
        "timestamp": "2026-07-01T04:30:00Z",
        "event_type": "person_detected",
        "stage1_result": {"detector": "person", "score": 0.9},
        "severity": "high",
        "confidence": 0.91,
        "summary": "Smoke test event",
        "idempotency_key": idempotency_key,
    }
    payload.update(overrides)
    return payload


def _as_utc(value) -> datetime:
    if isinstance(value, str):
        value = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def test_healthz() -> None:
    response = TestClient(app).get("/api/v1/healthz")
    assert response.status_code == 200
    assert response.json()["data"]["status"] == "ok"


def test_readyz_database_connectivity() -> None:
    response = TestClient(app).get("/api/v1/readyz")
    assert response.status_code == 200
    assert response.json()["data"]["database"] == "ok"


def test_all_app_tables_present() -> None:
    async def _table_names() -> set[str]:
        async with engine.connect() as conn:
            return set(await conn.run_sync(lambda sync_conn: inspect(sync_conn).get_table_names()))

    assert APP_TABLES <= asyncio.run(_table_names())


def test_alembic_version_at_head() -> None:
    async def _version() -> str | None:
        async with engine.connect() as conn:
            names = set(await conn.run_sync(lambda sync_conn: inspect(sync_conn).get_table_names()))
            if "alembic_version" not in names:
                return None
            return (await conn.execute(text("SELECT version_num FROM alembic_version"))).scalar()

    version = asyncio.run(_version())
    if version is None:
        pytest.skip("schema was created via create_all (no alembic_version table)")
    assert version == ALEMBIC_HEAD


def test_edge_event_create_via_api() -> None:
    response = _client().post("/api/v1/edge/events", headers=EDGE_HEADERS, json=_event_payload())
    assert response.status_code == 201
    assert response.json()["data"]["severity"] == "high"


def test_event_readback_via_session_api() -> None:
    client = _client()
    created = client.post("/api/v1/edge/events", headers=EDGE_HEADERS, json=_event_payload())
    event_id = created.json()["data"]["event_id"]

    listed = client.get("/api/v1/events")
    assert listed.status_code == 200
    assert event_id in {item["event_id"] for item in listed.json()["data"]}

    detail = client.get(f"/api/v1/events/{event_id}")
    assert detail.status_code == 200
    assert detail.json()["data"]["event_type"] == "person_detected"


def test_event_idempotency_unique_constraint() -> None:
    client = _client()
    first = client.post("/api/v1/edge/events", headers=EDGE_HEADERS, json=_event_payload())
    assert first.status_code == 201
    replay = client.post("/api/v1/edge/events", headers=EDGE_HEADERS, json=_event_payload())
    assert replay.status_code == 200
    assert replay.json()["data"]["event_id"] == first.json()["data"]["event_id"]


def test_json_column_round_trip() -> None:
    client = _client()
    stage1 = {
        "detector": "person",
        "boxes": [{"x": 0.42, "y": 0.2, "w": 0.1, "h": 0.3}],
        "labels": ["äºº", "person"],
        "nested": {"deep": {"value": 1.5, "flag": True, "none": None}},
    }
    created = client.post(
        "/api/v1/edge/events",
        headers=EDGE_HEADERS,
        json=_event_payload(stage1_result=stage1),
    )
    detail = client.get(f"/api/v1/events/{created.json()['data']['event_id']}")
    assert detail.json()["data"]["stage1_result"] == stage1


def test_datetime_tz_round_trip() -> None:
    client = _client()
    sent = "2026-07-01T12:34:56.789000+08:00"
    created = client.post(
        "/api/v1/edge/events",
        headers=EDGE_HEADERS,
        json=_event_payload(timestamp=sent),
    )
    event_id = created.json()["data"]["event_id"]
    detail = client.get(f"/api/v1/events/{event_id}")
    assert _as_utc(detail.json()["data"]["timestamp"]) == _as_utc(sent)

    async def _db_timestamp() -> datetime:
        async with session_factory() as session:
            return (
                await session.execute(select(Event.timestamp).where(Event.event_id == event_id))
            ).scalar_one()

    stored = asyncio.run(_db_timestamp())
    if not IS_SQLITE:
        assert stored.tzinfo is not None
    assert _as_utc(stored) == _as_utc(sent)


def test_boolean_round_trip() -> None:
    client = _client()
    created = client.post("/api/v1/edge/events", headers=EDGE_HEADERS, json=_event_payload())
    event_id = created.json()["data"]["event_id"]

    async def _fetch() -> tuple[bool, bool]:
        async with session_factory() as session:
            enabled = (
                await session.execute(select(Agent.enabled).where(Agent.agent_id == "agt_smoketest"))
            ).scalar_one()
            degraded = (
                await session.execute(select(Event.degraded).where(Event.event_id == event_id))
            ).scalar_one()
            return enabled, degraded

    enabled, degraded = asyncio.run(_fetch())
    assert enabled is True
    assert degraded is False


def test_recording_register_via_api() -> None:
    response = _client().post(
        "/api/v1/edge/recordings",
        headers=EDGE_HEADERS,
        json={
            "start_time": "2026-07-01T04:00:00Z",
            "end_time": "2026-07-01T04:10:00Z",
            "storage_type": "local_edge",
            "storage_path": "recordings/dev_smoketest/smoke.mp4",
        },
    )
    assert response.status_code == 201
    assert response.json()["data"]["status"] == "local_only"


def test_fk_cascade_delete_smoke_user() -> None:
    client = _client()
    created = client.post("/api/v1/edge/events", headers=EDGE_HEADERS, json=_event_payload())
    event_id = created.json()["data"]["event_id"]

    asyncio.run(_delete_smoke_rows())

    async def _leftovers() -> tuple[int, int]:
        async with session_factory() as session:
            events = (
                await session.execute(select(Event).where(Event.event_id == event_id))
            ).scalars().all()
            devices = (
                await session.execute(select(Device).where(Device.device_id == "dev_smoketest"))
            ).scalars().all()
            return len(events), len(devices)

    events_left, devices_left = asyncio.run(_leftovers())
    assert events_left == 0
    assert devices_left == 0
