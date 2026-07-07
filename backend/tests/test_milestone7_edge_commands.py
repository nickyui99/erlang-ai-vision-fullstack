import asyncio
from datetime import UTC, datetime
import os
from pathlib import Path
import sys
import tempfile
import threading


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{(Path(tempfile.gettempdir()) / 'sentineledge_m7_pytest.db').as_posix()}"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import select  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402
from starlette.websockets import WebSocketDisconnect  # noqa: E402

from app.core.security import create_session_token, hash_edge_token  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models.agent import Agent  # noqa: E402
from app.models.device import Device  # noqa: E402
from app.models.tool_audit import ToolAudit  # noqa: E402
from app.models.user import User  # noqa: E402


EDGE_TOKEN = "edge-token-m7"
OTHER_EDGE_TOKEN = "edge-token-m7-other"
EDGE_HEADERS = {"Authorization": f"Bearer {EDGE_TOKEN}"}


# Clients entered as context managers during a test, torn down after it.
_entered_clients: list["TestClient"] = []


def setup_function() -> None:
    asyncio.run(_reset_db())


def teardown_function() -> None:
    while _entered_clients:
        _entered_clients.pop().__exit__(None, None, None)


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
    # Enter the TestClient context so websocket_connect() and the threaded client.post()
    # in the relay tests share ONE blocking portal / event loop. A bare TestClient() gives
    # each call its own loop, so the shared edge_command_hub ends up driving a WebSocket
    # bound to one loop from a request handler running on another -> cross-loop deadlock.
    # (Real deployments run every connection on a single Uvicorn loop, so this only bit tests.)
    client = TestClient(app)
    client.__enter__()
    _entered_clients.append(client)
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



def test_device_control_command_relay_result_and_audit() -> None:
    client = _client()

    with client.websocket_connect("/api/v1/edge/ws", headers=EDGE_HEADERS) as websocket:
        response_holder: dict[str, object] = {}

        def post_control() -> None:
            response_holder["response"] = client.post(
                "/api/v1/devices/dev_m7/control",
                json={"action": "fill_light", "enabled": True},
            )

        thread = threading.Thread(target=post_control)
        thread.start()
        command = websocket.receive_json()
        websocket.send_json(
            {
                "type": "response.command_result",
                "request_id": command["request_id"],
                "status": "ok",
                "payload": {"action": "fill_light", "enabled": True},
            }
        )
        thread.join(timeout=3)

    response = response_holder["response"]
    assert response.status_code == 200
    assert response.json()["data"]["status"] == "ok"
    assert command["type"] == "command.fill_light"
    assert command["device_id"] == "dev_m7"
    assert command["payload"] == {"action": "fill_light", "enabled": True}

    audits = asyncio.run(_audit_rows())
    assert len(audits) == 1
    assert audits[0].tool_name == "device_fill_light"
    assert audits[0].called_by == "user"
    assert audits[0].arguments["payload"] == {"action": "fill_light", "enabled": True}
    assert audits[0].result["status"] == "ok"


def test_update_device_persists_camera_preferences() -> None:
    client = _client()

    response = client.put(
        "/api/v1/devices/dev_m7",
        json={
            "name": "Front Door",
            "location": "Porch",
            "is_favorite": True,
            "presets": [{"label": "Entry", "pan": 45, "tilt": 95}],
            "ptz_correction_pan": -3,
            "ptz_correction_tilt": 4,
        },
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["is_favorite"] is True
    assert data["presets"] == [{"label": "Entry", "pan": 45, "tilt": 95}]
    assert data["ptz_correction_pan"] == -3
    assert data["ptz_correction_tilt"] == 4

    read_response = client.get("/api/v1/devices/dev_m7")
    assert read_response.status_code == 200
    assert read_response.json()["data"]["presets"][0]["label"] == "Entry"
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


def test_set_control_mode_persists_and_relays_when_edge_connected() -> None:
    client = _client()

    with client.websocket_connect("/api/v1/edge/ws", headers=EDGE_HEADERS) as websocket:
        response_holder: dict[str, object] = {}

        def post_mode() -> None:
            response_holder["response"] = client.post(
                "/api/v1/devices/dev_m7/control-mode", json={"mode": "auto_track"}
            )

        thread = threading.Thread(target=post_mode)
        thread.start()
        command = websocket.receive_json()
        websocket.send_json(
            {
                "type": "response.command_result",
                "request_id": command["request_id"],
                "status": "ok",
                "payload": {"control_mode": "auto_track"},
            }
        )
        thread.join(timeout=3)

    response = response_holder["response"]
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["control_mode"] == "auto_track"   # persisted on the device row
    assert data["relayed"] is True                 # delivered live to the connected edge
    assert command["type"] == "command.set_control_mode"
    assert command["device_id"] == "dev_m7"
    assert command["payload"] == {"mode": "auto_track"}

    # persistence survives a fresh read
    read = client.get("/api/v1/devices/dev_m7")
    assert read.json()["data"]["control_mode"] == "auto_track"

    audits = asyncio.run(_audit_rows())
    assert len(audits) == 1
    assert audits[0].tool_name == "set_control_mode"
    assert audits[0].called_by == "user"


def test_set_control_mode_persists_when_edge_offline() -> None:
    # No edge connected: the request still succeeds (mode persists, relayed=false); the edge will
    # pick it up on its next /agents/active poll.
    client = _client()

    response = client.post("/api/v1/devices/dev_m7/control-mode", json={"mode": "agent"})

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["control_mode"] == "agent"
    assert data["relayed"] is False
    assert client.get("/api/v1/devices/dev_m7").json()["data"]["control_mode"] == "agent"


def test_set_control_mode_rejects_invalid_mode() -> None:
    client = _client()
    response = client.post("/api/v1/devices/dev_m7/control-mode", json={"mode": "spin"})
    assert response.status_code == 422


def test_set_control_mode_ownership_and_auth() -> None:
    assert TestClient(app).post(
        "/api/v1/devices/dev_m7/control-mode", json={"mode": "off"}
    ).status_code == 401
    assert _client("usr_other").post(
        "/api/v1/devices/dev_m7/control-mode", json={"mode": "off"}
    ).status_code == 404


def test_active_configs_includes_control_mode() -> None:
    # The edge poll response carries control_mode so a reconnecting edge restores the last mode.
    client = _client()
    client.post("/api/v1/devices/dev_m7/control-mode", json={"mode": "agent"})

    edge = TestClient(app).get("/api/v1/edge/agents/active", headers=EDGE_HEADERS)
    assert edge.status_code == 200
    assert edge.json()["control_mode"] == "agent"


def test_agent_control_returns_clamped_candidate_offline_model() -> None:
    # With the offline MockQwen (test env), the model yields no action, so the endpoint falls
    # back to the edge-supplied deterministic candidate -- clamped to the servo limits.
    client = TestClient(app)
    situation = {
        "behavior": "follow",
        "target_classes": ["person"],
        "detections": [{"label": "person", "confidence": 0.9}],
        "pan": 90, "tilt": 90,
        "candidate": {"cmd": "pan", "angle": 999},  # out of range on purpose
    }
    response = client.post("/api/v1/edge/agent-control", headers=EDGE_HEADERS, json=situation)
    assert response.status_code == 200
    assert response.json()["data"]["action"] == {"cmd": "pan", "angle": 180}  # clamped

    audits = asyncio.run(_audit_rows())
    assert len(audits) == 1
    assert audits[0].tool_name == "agent_camera_control"
    assert audits[0].called_by == "agent"


def test_agent_control_holds_when_no_candidate() -> None:
    client = TestClient(app)
    response = client.post(
        "/api/v1/edge/agent-control", headers=EDGE_HEADERS,
        json={"behavior": "scan", "detections": [], "candidate": None},
    )
    assert response.status_code == 200
    assert response.json()["data"]["action"] is None  # hold


def test_agent_control_requires_edge_token() -> None:
    assert TestClient(app).post("/api/v1/edge/agent-control", json={}).status_code in (401, 403)


def test_pan_angle_validation() -> None:
    client = _client()

    too_low = client.post("/api/v1/devices/dev_m7/pan", json={"angle": -1})
    too_high = client.post("/api/v1/devices/dev_m7/pan", json={"angle": 181})

    assert too_low.status_code == 422
    assert too_high.status_code == 422


async def _seed_agent_for_device(agent_id: str, device_id: str) -> None:
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as session:
        now = datetime.now(UTC)
        session.add(
            Agent(
                agent_id=agent_id,
                user_id="usr_m7",
                device_id=device_id,
                name="Loiter watch",
                nl_rule="alert on loitering",
                created_at=now,
                updated_at=now,
            )
        )
        await session.commit()


async def _device_exists(device_id: str) -> bool:
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as session:
        result = await session.execute(select(Device).where(Device.device_id == device_id))
        return result.scalar_one_or_none() is not None


async def _agent_exists(agent_id: str) -> bool:
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as session:
        result = await session.execute(select(Agent).where(Agent.agent_id == agent_id))
        return result.scalar_one_or_none() is not None


def test_delete_device_unregisters_and_cascades_agents() -> None:
    asyncio.run(_seed_agent_for_device("agt_m7", "dev_m7"))
    client = _client()

    response = client.delete("/api/v1/devices/dev_m7")

    assert response.status_code == 204
    assert response.content == b""
    assert asyncio.run(_device_exists("dev_m7")) is False
    # The agent assigned to the camera cascade-deletes with it.
    assert asyncio.run(_agent_exists("agt_m7")) is False


def test_delete_device_requires_authentication() -> None:
    response = TestClient(app).delete("/api/v1/devices/dev_m7")

    assert response.status_code == 401
    assert asyncio.run(_device_exists("dev_m7")) is True


def test_delete_device_rejects_non_owner() -> None:
    response = _client("usr_other").delete("/api/v1/devices/dev_m7")

    assert response.status_code == 404
    assert asyncio.run(_device_exists("dev_m7")) is True


def test_delete_unknown_device_returns_404() -> None:
    response = _client().delete("/api/v1/devices/dev_missing")

    assert response.status_code == 404

