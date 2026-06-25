import asyncio
from datetime import UTC, datetime
import os
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///C:/tmp/sentineledge_m5_pytest.db"

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402

from app.core.security import create_session_token, hash_edge_token  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models.agent import Agent  # noqa: E402
from app.models.device import Device  # noqa: E402
from app.models.user import User  # noqa: E402


EDGE_TOKEN = "edge-token-m5"
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
                user_id="usr_m5",
                google_sub="gsub_m5",
                email="m5@example.com",
                email_verified=True,
                role="user",
                created_at=now,
                updated_at=now,
            )
        )
        await session.commit()
        session.add(
            Device(
                device_id="dev_m5",
                user_id="usr_m5",
                edge_token_hash=hash_edge_token(EDGE_TOKEN),
                name="Front Door",
                health_status="online",
                current_pan=90,
                created_at=now,
                updated_at=now,
            )
        )
        await session.commit()
        session.add(
            Agent(
                agent_id="agt_m5",
                user_id="usr_m5",
                device_id="dev_m5",
                name="Night Watch",
                nl_rule="watch",
                compiled_prompt="watch",
                compiled_edge_config={},
                state="armed",
                enabled=True,
                created_at=now,
                updated_at=now,
            )
        )
        await session.commit()


def _event_payload(idempotency_key: str = "dev_m5-evt-1") -> dict:
    return {
        "agent_id": "agt_m5",
        "timestamp": "2026-06-21T12:00:00Z",
        "event_type": "person_detected",
        "stage1_result": {"detector": "person"},
        "stage2_verdict": {"matched_rule": True},
        "severity": "high",
        "confidence": 0.91,
        "summary": "Person at front door",
        "idempotency_key": idempotency_key,
    }


def _client() -> TestClient:
    client = TestClient(app)
    client.cookies.set("sentineledge_session", create_session_token("usr_m5"))
    return client


def test_edge_event_create_and_idempotent_replay() -> None:
    client = _client()

    response = client.post("/api/v1/edge/events", headers=EDGE_HEADERS, json=_event_payload())
    assert response.status_code == 201
    event_id = response.json()["data"]["event_id"]

    duplicate = client.post("/api/v1/edge/events", headers=EDGE_HEADERS, json=_event_payload())
    assert duplicate.status_code == 200
    assert duplicate.json()["data"]["event_id"] == event_id


def test_event_list_detail_and_invalid_agent_ownership() -> None:
    client = _client()

    response = client.post("/api/v1/edge/events", headers=EDGE_HEADERS, json=_event_payload())
    assert response.status_code == 201
    event_id = response.json()["data"]["event_id"]

    listed = client.get("/api/v1/events")
    assert listed.status_code == 200
    assert len(listed.json()["data"]) == 1

    detail = client.get(f"/api/v1/events/{event_id}")
    assert detail.status_code == 200
    assert detail.json()["data"]["severity"] == "high"

    invalid = client.post(
        "/api/v1/edge/events",
        headers=EDGE_HEADERS,
        json={**_event_payload("bad-agent"), "agent_id": "agt_other"},
    )
    assert invalid.status_code == 404


def test_clip_upload_completion_signed_url_and_recording_registration() -> None:
    client = _client()

    event_response = client.post("/api/v1/edge/events", headers=EDGE_HEADERS, json=_event_payload())
    event_id = event_response.json()["data"]["event_id"]

    upload = client.post(
        "/api/v1/edge/clips/upload-url",
        headers=EDGE_HEADERS,
        json={
            "event_id": event_id,
            "mime_type": "video/mp4",
            "duration_seconds": 8,
            "idempotency_key": "dev_m5-clip-1",
        },
    )
    assert upload.status_code == 201
    assert upload.json()["data"]["upload_url"].startswith("placeholder://upload/")
    clip_id = upload.json()["data"]["clip_id"]

    duplicate_upload = client.post(
        "/api/v1/edge/clips/upload-url",
        headers=EDGE_HEADERS,
        json={
            "event_id": event_id,
            "mime_type": "video/mp4",
            "duration_seconds": 8,
            "idempotency_key": "dev_m5-clip-1",
        },
    )
    assert duplicate_upload.status_code == 200
    assert duplicate_upload.json()["data"]["clip_id"] == clip_id

    unavailable = client.post(f"/api/v1/clips/{clip_id}/signed-url")
    assert unavailable.status_code == 409

    complete = client.post(
        f"/api/v1/edge/clips/{clip_id}/complete",
        headers=EDGE_HEADERS,
        json={"file_size_bytes": 1234},
    )
    assert complete.status_code == 200
    assert complete.json()["data"]["status"] == "available"

    clips = client.get(f"/api/v1/events/{event_id}/clips")
    assert clips.status_code == 200
    assert len(clips.json()["data"]) == 1

    signed = client.post(f"/api/v1/clips/{clip_id}/signed-url")
    assert signed.status_code == 200
    assert signed.json()["data"]["playback_url"].startswith("placeholder://playback/")

    recording = client.post(
        "/api/v1/edge/recordings",
        headers=EDGE_HEADERS,
        json={
            "start_time": "2026-06-21T12:00:00Z",
            "end_time": "2026-06-21T12:10:00Z",
            "storage_type": "local_edge",
            "storage_path": "recordings/dev_m5/test.mp4",
        },
    )
    assert recording.status_code == 201
    assert recording.json()["data"]["status"] == "local_only"
