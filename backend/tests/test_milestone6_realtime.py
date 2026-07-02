import asyncio
import os
from pathlib import Path
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{(Path(tempfile.gettempdir()) / 'sentineledge_m6_pytest.db').as_posix()}"

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402
from app.services.realtime_bus import RealtimeBus  # noqa: E402


def test_sse_endpoint_rejects_unauthenticated_user() -> None:
    client = TestClient(app)

    response = client.get("/api/v1/stream/events")

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "not_authenticated"


def test_realtime_bus_delivers_only_to_matching_user() -> None:
    async def run() -> None:
        bus = RealtimeBus()
        matching = await bus.subscribe("usr_1")
        other = await bus.subscribe("usr_2")

        await bus.publish("usr_1", "event.created", {"event_id": "evt_1"})

        delivered = await asyncio.wait_for(matching.queue.get(), timeout=1)
        assert delivered.event == "event.created"
        assert delivered.data["event_id"] == "evt_1"
        assert other.queue.empty()

        await bus.unsubscribe(matching)
        await bus.unsubscribe(other)

    asyncio.run(run())


def test_realtime_bus_drops_oldest_when_client_is_slow() -> None:
    async def run() -> None:
        bus = RealtimeBus(queue_size=1)
        subscription = await bus.subscribe("usr_1")

        await bus.publish("usr_1", "event.created", {"event_id": "evt_1"})
        await bus.publish("usr_1", "event.created", {"event_id": "evt_2"})

        delivered = await asyncio.wait_for(subscription.queue.get(), timeout=1)
        assert delivered.data["event_id"] == "evt_2"

        await bus.unsubscribe(subscription)

    asyncio.run(run())
