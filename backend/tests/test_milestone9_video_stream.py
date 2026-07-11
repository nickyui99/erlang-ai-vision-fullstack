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

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402
from starlette.websockets import WebSocketDisconnect  # noqa: E402

from app.core.security import create_session_token, create_signed_token, hash_edge_token  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models.device import Device  # noqa: E402
from app.models.user import User  # noqa: E402
from app.services.video_stream_broker import VideoStreamBroker  # noqa: E402


EDGE_TOKEN = "edge-token-m9"
EDGE_HEADERS = {"Authorization": f"Bearer {EDGE_TOKEN}"}
STREAM_PURPOSE = "live_stream"


def setup_function() -> None:
    asyncio.run(_reset_db())


async def _reset_db() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as session:
        now = datetime.now(UTC)
        session.add_all(
            [
                User(
                    user_id="usr_m9",
                    google_sub="gsub_m9",
                    email="m9@example.com",
                    email_verified=True,
                    role="user",
                    created_at=now,
                    updated_at=now,
                ),
                User(
                    user_id="usr_other",
                    google_sub="gsub_other",
                    email="other@example.com",
                    email_verified=True,
                    role="user",
                    created_at=now,
                    updated_at=now,
                ),
            ]
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
                created_at=now,
                updated_at=now,
            )
        )
        await session.commit()


def _client(user_id: str = "usr_m9") -> TestClient:
    client = TestClient(app)
    client.cookies.set("erlang_session", create_session_token(user_id))
    return client


# --- broker (the live data path) -------------------------------------------


def test_broker_fans_out_frames_and_isolates_devices() -> None:
    async def run() -> None:
        broker = VideoStreamBroker()
        viewer_a = await broker.subscribe("dev_a")
        viewer_b = await broker.subscribe("dev_b")

        await broker.publish("dev_a", b"frame-a")

        delivered = await asyncio.wait_for(viewer_a.get(), timeout=1)
        assert delivered == b"frame-a"
        assert viewer_b.empty()

    asyncio.run(run())


def test_broker_replays_latest_frame_to_new_viewer() -> None:
    async def run() -> None:
        broker = VideoStreamBroker()
        await broker.publish("dev_a", b"latest")

        viewer = await broker.subscribe("dev_a")
        delivered = await asyncio.wait_for(viewer.get(), timeout=1)
        assert delivered == b"latest"

    asyncio.run(run())


def test_broker_drops_oldest_for_slow_viewer() -> None:
    async def run() -> None:
        broker = VideoStreamBroker(queue_size=1)
        viewer = await broker.subscribe("dev_a")

        await broker.publish("dev_a", b"f1")
        await broker.publish("dev_a", b"f2")

        delivered = await asyncio.wait_for(viewer.get(), timeout=1)
        assert delivered == b"f2"

    asyncio.run(run())


def test_broker_tracks_publishing_state() -> None:
    async def run() -> None:
        broker = VideoStreamBroker()
        assert broker.is_publishing("dev_a") is False
        await broker.start_publishing("dev_a")
        assert broker.is_publishing("dev_a") is True
        await broker.stop_publishing("dev_a")
        assert broker.is_publishing("dev_a") is False

    asyncio.run(run())


# --- edge ingest WebSocket ---------------------------------------------------


def test_edge_stream_ws_rejects_missing_or_invalid_token() -> None:
    client = TestClient(app)

    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/api/v1/edge/stream"):
            pass

    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/api/v1/edge/stream", headers={"Authorization": "Bearer wrong"}):
            pass


def test_edge_stream_ws_accepts_valid_token() -> None:
    client = TestClient(app)

    with client.websocket_connect("/api/v1/edge/stream", headers=EDGE_HEADERS) as ws:
        ws.send_bytes(b"\xff\xd8\xff\xd9")  # minimal JPEG-ish payload


# --- stream-url minting ------------------------------------------------------


def test_stream_url_requires_authentication() -> None:
    response = TestClient(app).post("/api/v1/devices/dev_m9/stream-url")
    assert response.status_code == 401


def test_stream_url_enforces_ownership() -> None:
    response = _client("usr_other").post("/api/v1/devices/dev_m9/stream-url")
    assert response.status_code == 404


def test_stream_url_returns_signed_stream_url() -> None:
    response = _client().post("/api/v1/devices/dev_m9/stream-url")
    assert response.status_code == 200
    stream_url = response.json()["data"]["stream_url"]
    assert "/api/v1/devices/dev_m9/stream?token=" in stream_url


# --- MJPEG egress token checks (return before the stream body opens) ---------


def test_stream_egress_rejects_invalid_token() -> None:
    response = _client().get("/api/v1/devices/dev_m9/stream", params={"token": "garbage"})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_stream_token"


def test_stream_egress_rejects_token_for_a_different_device() -> None:
    token = create_signed_token(
        {"device_id": "dev_other", "user_id": "usr_m9"},
        STREAM_PURPOSE,
        300,
    )
    response = _client().get("/api/v1/devices/dev_m9/stream", params={"token": token})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_stream_token"
