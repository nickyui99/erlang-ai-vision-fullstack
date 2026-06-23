import asyncio
from datetime import UTC, datetime
import os
from pathlib import Path
import sys
import threading


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///C:/tmp/sentineledge_m7_pytest.db"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import select  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402
from starlette.websockets import WebSocketDisconnect  # noqa: E402

from app.core.security import create_session_token, hash_edge_token  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models.device import Device  # noqa: E402
from app.models.tool_audit import ToolAudit  # noqa: E402
from app.models.user import User  # noqa: E402


EDGE_TOKEN = "edge-token-m7"
OTHER_EDGE_TOKEN = "edge-token-m7-other"
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
        session.add_all(
            [
                User(
                    user_id="usr_m7",
                    google_sub="gsub_m7",
                    email="m7@example.com",
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
        session.add_all(
            [
                Device(
                    device_id="dev_m7",
                    user_id="usr_m7",
                    edge_token_hash=hash_edge_token(EDGE_TOKEN),
                    name="Front Door",
                    health_status="online",
                    current_pan=90,
                    created_at=now,
                    updated_at=now,
                ),
                Device(
                    device_id="dev_other",
                    user_id="usr_other",
                    edge_token_hash=hash_edge_token(OTHER_EDGE_TOKEN),
                    name="Garage",
                    health_status="online",
                    current_pan=90,
                    created_at=now,
                    updated_at=now,
                ),
            ]
        )
        await session.commit()


def _client(user_id: str = "usr_m7") -> TestClient:
    client = TestClient(app)
    client.cookies.set("sentineledge_session", create_session_token(user_id))
    return client


async def _audit_rows() -> list[ToolAudit]:
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as session:
        result = await session.execute(select(ToolAudit).order_by(ToolAudit.timestamp.asc()))
        return list(result.scalars())


def test_edge_websocket_rejects_missing_or_invalid_token() -> None:
    client = TestClient(app)

    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/api/v1/edge/ws"):
            pass

    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/api/v1/edge/ws", headers={"Authorization": "Bearer wrong"}):
            pass


def test_edge_websocket_accepts_valid_token() -> None:
    client = TestClient(app)

    with client.websocket_connect("/api/v1/edge/ws", headers=EDGE_HEADERS):
        pass


def test_pan_command_relay_result_and_audit() -> None:
    client = _client()

    with client.websocket_connect("/api/v1/edge/ws", headers=EDGE_HEADERS) as websocket:
        response_holder: dict[str, object] = {}

        def post_pan() -> None:
            response_holder["response"] = client.post("/api/v1/devices/dev_m7/pan", json={"angle": 45})

        thread = threading.Thread(target=post_pan)
        thread.start()
        command = websocket.receive_json()
        websocket.send_json(
            {
                "type": "response.command_result",
                "request_id": command["request_id"],
                "status": "ok",
                "payload": {"angle": 45},
            }
        )
        thread.join(timeout=3)

    response = response_holder["response"]
    assert response.status_code == 200
    assert response.json()["data"]["request_id"] == command["request_id"]
    assert response.json()["data"]["status"] == "ok"
    assert response.json()["data"]["payload"]["angle"] == 45
    assert command["type"] == "command.pan_camera"
    assert command["device_id"] == "dev_m7"
    assert command["payload"] == {"angle": 45}

    audits = asyncio.run(_audit_rows())
    assert len(audits) == 1
    assert audits[0].tool_name == "pan_camera"
    assert audits[0].called_by == "user"
    assert audits[0].arguments["request_id"] == command["request_id"]
    assert audits[0].result["request_id"] == command["request_id"]
    assert audits[0].result["status"] == "ok"


def test_tilt_command_relay_result_and_audit() -> None:
    client = _client()

    with client.websocket_connect("/api/v1/edge/ws", headers=EDGE_HEADERS) as websocket:
        response_holder: dict[str, object] = {}

        def post_tilt() -> None:
            response_holder["response"] = client.post("/api/v1/devices/dev_m7/tilt", json={"angle": 120})

        thread = threading.Thread(target=post_tilt)
        thread.start()
        command = websocket.receive_json()
        websocket.send_json(
            {
                "type": "response.command_result",
                "request_id": command["request_id"],
                "status": "ok",
                "payload": {"angle": 120},
            }
        )
        thread.join(timeout=3)

    response = response_holder["response"]
    assert response.status_code == 200
    assert response.json()["data"]["status"] == "ok"
    assert response.json()["data"]["payload"]["angle"] == 120
    assert command["type"] == "command.tilt_camera"
    assert command["device_id"] == "dev_m7"
    assert command["payload"] == {"angle": 120}

    audits = asyncio.run(_audit_rows())
    assert len(audits) == 1
    assert audits[0].tool_name == "tilt_camera"
    assert audits[0].called_by == "user"


def test_snapshot_command_relay_result() -> None:
    client = _client()

    with client.websocket_connect("/api/v1/edge/ws", headers=EDGE_HEADERS) as websocket:
        response_holder: dict[str, object] = {}

        def post_snapshot() -> None:
            response_holder["response"] = client.post("/api/v1/devices/dev_m7/snapshot")

        thread = threading.Thread(target=post_snapshot)
        thread.start()
        command = websocket.receive_json()
        websocket.send_json(
            {
                "type": "response.command_result",
                "request_id": command["request_id"],
                "status": "ok",
                "payload": {"snapshot_path": "snapshots/dev_m7/latest.jpg"},
            }
        )
        thread.join(timeout=3)

    response = response_holder["response"]
    assert response.status_code == 200
    assert response.json()["data"]["request_id"] == command["request_id"]
    assert command["type"] == "command.get_live_snapshot"
    assert command["device_id"] == "dev_m7"
    assert command["payload"] == {}


def test_command_endpoint_auth_and_ownership_checks() -> None:
    unauthenticated = TestClient(app)
    response = unauthenticated.post("/api/v1/devices/dev_m7/pan", json={"angle": 45})
    assert response.status_code == 401

    other_user = _client("usr_other")
    response = other_user.post("/api/v1/devices/dev_m7/pan", json={"angle": 45})
    assert response.status_code == 404


def test_command_for_one_device_does_not_relay_to_another_device() -> None:
    client = _client()

    with client.websocket_connect("/api/v1/edge/ws", headers={"Authorization": f"Bearer {OTHER_EDGE_TOKEN}"}):
        response = client.post("/api/v1/devices/dev_m7/pan", json={"angle": 45})

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "edge_not_connected"


def test_command_returns_503_when_edge_not_connected_and_audits_failure() -> None:
    client = _client()

    response = client.post("/api/v1/devices/dev_m7/pan", json={"angle": 45})

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "edge_not_connected"
    audits = asyncio.run(_audit_rows())
    assert len(audits) == 1
    assert audits[0].result["error"]["code"] == "edge_not_connected"


def test_command_returns_504_when_edge_does_not_respond_and_audits_failure() -> None:
    client = _client()

    with client.websocket_connect("/api/v1/edge/ws", headers=EDGE_HEADERS) as websocket:
        response_holder: dict[str, object] = {}

        def post_pan() -> None:
            response_holder["response"] = client.post("/api/v1/devices/dev_m7/pan", json={"angle": 45})

        thread = threading.Thread(target=post_pan)
        thread.start()
        websocket.receive_json()
        thread.join(timeout=12)

    response = response_holder["response"]
    assert response.status_code == 504
    assert response.json()["error"]["code"] == "command_timeout"
    audits = asyncio.run(_audit_rows())
    assert len(audits) == 1
    assert audits[0].result["error"]["code"] == "command_timeout"


def test_pan_angle_validation() -> None:
    client = _client()

    too_low = client.post("/api/v1/devices/dev_m7/pan", json={"angle": -1})
    too_high = client.post("/api/v1/devices/dev_m7/pan", json={"angle": 181})

    assert too_low.status_code == 422
    assert too_high.status_code == 422
