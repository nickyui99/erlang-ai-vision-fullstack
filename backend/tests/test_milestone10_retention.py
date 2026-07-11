import asyncio
from datetime import UTC, datetime, timedelta
import os
from pathlib import Path
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{(Path(tempfile.gettempdir()) / 'erlang_m10_pytest.db').as_posix()}"

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import update  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.core.security import create_session_token, hash_edge_token  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models.agent import Agent  # noqa: E402
from app.models.clip import Clip  # noqa: E402
from app.models.device import Device  # noqa: E402
from app.models.recording import Recording  # noqa: E402
from app.models.user import User  # noqa: E402
from app.services import media_retention_service  # noqa: E402

settings.alibaba_cloud_access_key_id = ""
settings.alibaba_cloud_access_key_secret = ""
settings.alicloud_oss_endpoint = ""
settings.alicloud_oss_bucket = ""


EDGE_TOKEN = "edge-token-m10"
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
                user_id="usr_m10",
                google_sub="gsub_m10",
                email="m10@example.com",
                email_verified=True,
                role="user",
                created_at=now,
                updated_at=now,
            )
        )
        await session.commit()
        session.add(
            Device(
                device_id="dev_m10",
                user_id="usr_m10",
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
                agent_id="agt_m10",
                user_id="usr_m10",
                device_id="dev_m10",
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


def _client() -> TestClient:
    client = TestClient(app)
    client.cookies.set("erlang_session", create_session_token("usr_m10"))
    return client


def _create_event(client: TestClient, idempotency_key: str = "dev_m10-evt-1") -> str:
    response = client.post(
        "/api/v1/edge/events",
        headers=EDGE_HEADERS,
        json={
            "agent_id": "agt_m10",
            "timestamp": "2026-07-07T12:00:00Z",
            "event_type": "person_detected",
            "stage1_result": {"detector": "person"},
            "stage2_verdict": {"matched_rule": True},
            "severity": "high",
            "confidence": 0.91,
            "summary": "Person at front door",
            "idempotency_key": idempotency_key,
        },
    )
    assert response.status_code == 201
    return response.json()["data"]["event_id"]


def _create_clip(client: TestClient, event_id: str, *, complete: bool = True, idempotency_key: str = "dev_m10-clip-1") -> str:
    upload = client.post(
        "/api/v1/edge/clips/upload-url",
        headers=EDGE_HEADERS,
        json={
            "event_id": event_id,
            "mime_type": "video/mp4",
            "duration_seconds": 8,
            "idempotency_key": idempotency_key,
        },
    )
    assert upload.status_code == 201
    clip_id = upload.json()["data"]["clip_id"]
    if complete:
        done = client.post(
            f"/api/v1/edge/clips/{clip_id}/complete",
            headers=EDGE_HEADERS,
            json={"file_size_bytes": 1234},
        )
        assert done.status_code == 200
    return clip_id


def _create_recording(client: TestClient, recording_id: str = "rec_m10_oss") -> str:
    response = client.post(
        "/api/v1/edge/recordings",
        headers=EDGE_HEADERS,
        json={
            "recording_id": recording_id,
            "start_time": "2026-07-07T12:00:00Z",
            "end_time": "2026-07-07T12:30:00Z",
            "storage_type": "oss",
            "oss_object_key": f"recordings/usr_m10/dev_m10/{recording_id}.mp4",
            "duration_seconds": 1800,
            "status": "available",
        },
    )
    assert response.status_code == 201
    return response.json()["data"]["recording_id"]


def _set_clip(clip_id: str, **values) -> None:
    async def _apply() -> None:
        session_factory = async_sessionmaker(engine, expire_on_commit=False)
        async with session_factory() as session:
            await session.execute(update(Clip).where(Clip.clip_id == clip_id).values(**values))
            await session.commit()

    asyncio.run(_apply())


def _set_recording(recording_id: str, **values) -> None:
    async def _apply() -> None:
        session_factory = async_sessionmaker(engine, expire_on_commit=False)
        async with session_factory() as session:
            await session.execute(
                update(Recording).where(Recording.recording_id == recording_id).values(**values)
            )
            await session.commit()

    asyncio.run(_apply())


def _get_clip(clip_id: str) -> Clip:
    async def _fetch() -> Clip:
        session_factory = async_sessionmaker(engine, expire_on_commit=False)
        async with session_factory() as session:
            return await session.get(Clip, clip_id)

    return asyncio.run(_fetch())


def _get_recording(recording_id: str) -> Recording:
    async def _fetch() -> Recording:
        session_factory = async_sessionmaker(engine, expire_on_commit=False)
        async with session_factory() as session:
            return await session.get(Recording, recording_id)

    return asyncio.run(_fetch())


def _sweep() -> dict[str, int]:
    return asyncio.run(media_retention_service.sweep_expired_media())


def test_sweep_marks_expired_clip_deleted_and_hides_from_lists() -> None:
    client = _client()
    event_id = _create_event(client)
    clip_id = _create_clip(client, event_id)

    _set_clip(clip_id, expires_at=datetime.now(UTC) - timedelta(days=1))

    counts = _sweep()
    assert counts == {"expired_clips": 1, "stale_uploads": 0, "expired_recordings": 0}

    clip = _get_clip(clip_id)
    assert clip.status == "deleted"
    assert clip.deleted_at is not None

    assert client.get("/api/v1/devices/dev_m10/clips").json()["data"] == []
    assert client.get(f"/api/v1/events/{event_id}/clips").json()["data"] == []
    assert client.post(f"/api/v1/clips/{clip_id}/signed-url").status_code == 404


def test_signed_url_rejects_expired_clip_before_sweep() -> None:
    client = _client()
    event_id = _create_event(client)
    clip_id = _create_clip(client, event_id)

    _set_clip(clip_id, expires_at=datetime.now(UTC) - timedelta(minutes=1))

    signed = client.post(f"/api/v1/clips/{clip_id}/signed-url")
    assert signed.status_code == 410
    assert signed.json()["error"]["code"] == "clip_expired"

    download = client.post(f"/api/v1/clips/{clip_id}/download-url")
    assert download.status_code == 410
    assert download.json()["error"]["code"] == "clip_expired"


def test_sweep_marks_stale_pending_upload_failed() -> None:
    client = _client()
    event_id = _create_event(client)
    clip_id = _create_clip(client, event_id, complete=False)

    _set_clip(clip_id, created_at=datetime.now(UTC) - timedelta(hours=25))

    counts = _sweep()
    assert counts == {"expired_clips": 0, "stale_uploads": 1, "expired_recordings": 0}

    clip = _get_clip(clip_id)
    assert clip.status == "failed"
    assert clip.upload_error == "upload window expired"
    assert clip.deleted_at is None


def test_sweep_marks_expired_recording_deleted() -> None:
    client = _client()
    recording_id = _create_recording(client)

    _set_recording(recording_id, retention_until=datetime.now(UTC) - timedelta(hours=1))

    counts = _sweep()
    assert counts == {"expired_clips": 0, "stale_uploads": 0, "expired_recordings": 1}

    recording = _get_recording(recording_id)
    assert recording.status == "deleted"
    assert recording.deleted_at is not None

    assert client.get("/api/v1/devices/dev_m10/recordings").json()["data"] == []
    assert client.post(f"/api/v1/recordings/{recording_id}/signed-url").status_code == 404


def test_recording_signed_url_rejects_expired_retention() -> None:
    client = _client()
    recording_id = _create_recording(client)

    _set_recording(recording_id, retention_until=datetime.now(UTC) - timedelta(minutes=1))

    signed = client.post(f"/api/v1/recordings/{recording_id}/signed-url")
    assert signed.status_code == 410
    assert signed.json()["error"]["code"] == "recording_expired"


def test_sweep_ignores_unexpired_media() -> None:
    client = _client()
    event_id = _create_event(client)
    clip_id = _create_clip(client, event_id)
    recording_id = _create_recording(client)

    counts = _sweep()
    assert counts == {"expired_clips": 0, "stale_uploads": 0, "expired_recordings": 0}

    assert client.post(f"/api/v1/clips/{clip_id}/signed-url").status_code == 200
    assert client.post(f"/api/v1/recordings/{recording_id}/signed-url").status_code == 200
    assert len(client.get(f"/api/v1/events/{event_id}/clips").json()["data"]) == 1
