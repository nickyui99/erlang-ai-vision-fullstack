import asyncio
from datetime import UTC, datetime
import os
from pathlib import Path
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{(Path(tempfile.gettempdir()) / 'erlang_chat_pytest.db').as_posix()}"

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402

from app.core.security import create_session_token  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models.user import User  # noqa: E402


def setup_function() -> None:
    asyncio.run(_reset_db())


async def _reset_db() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as session:
        now = datetime.now(UTC)
        for uid, sub, email in (
            ("usr_a", "gsub_a", "a@example.com"),
            ("usr_b", "gsub_b", "b@example.com"),
        ):
            session.add(
                User(
                    user_id=uid,
                    google_sub=sub,
                    email=email,
                    email_verified=True,
                    role="user",
                    created_at=now,
                    updated_at=now,
                )
            )
        await session.commit()


def _client(user_id: str = "usr_a") -> TestClient:
    client = TestClient(app)
    client.cookies.set("erlang_session", create_session_token(user_id))
    return client


def test_create_send_and_history() -> None:
    client = _client()

    created = client.post("/api/v1/chat/sessions", json={})
    assert created.status_code == 201
    session_id = created.json()["data"]["session_id"]
    assert created.json()["data"]["title"] == ""

    # Session shows up in the list.
    listed = client.get("/api/v1/chat/sessions").json()["data"]
    assert [s["session_id"] for s in listed] == [session_id]

    # Sending a message returns the assistant reply.
    sent = client.post(
        f"/api/v1/chat/sessions/{session_id}/messages",
        json={"content": "Which cameras need attention?"},
    )
    assert sent.status_code == 201
    reply = sent.json()["data"]
    assert reply["role"] == "assistant"
    assert reply["content"]

    # History is ordered user -> assistant, and the title was derived.
    messages = client.get(f"/api/v1/chat/sessions/{session_id}/messages").json()["data"]
    assert [m["role"] for m in messages] == ["user", "assistant"]
    assert messages[0]["content"] == "Which cameras need attention?"

    title = client.get("/api/v1/chat/sessions").json()["data"][0]["title"]
    assert title == "Which cameras need attention?"


def test_create_with_first_message_runs_opening_turn() -> None:
    client = _client()

    created = client.post(
        "/api/v1/chat/sessions",
        json={"first_message": "Summarize today's security events."},
    )
    assert created.status_code == 201
    data = created.json()["data"]
    assert data["title"] == "Summarize today's security events."

    messages = client.get(
        f"/api/v1/chat/sessions/{data['session_id']}/messages"
    ).json()["data"]
    assert [m["role"] for m in messages] == ["user", "assistant"]


def test_mock_reply_is_conversational_not_verdict() -> None:
    # Offline/keyless chat must read as conversation, not an event-verification
    # JSON verdict (the mock's other mode).
    client = _client()
    session_id = client.post("/api/v1/chat/sessions", json={}).json()["data"]["session_id"]

    reply = client.post(
        f"/api/v1/chat/sessions/{session_id}/messages",
        json={"content": "Hello there"},
    ).json()["data"]["content"]

    assert "Erlang AI Agent" in reply
    assert '"verified"' not in reply
    assert "Hello there" in reply


def test_ownership_isolation() -> None:
    owner = _client("usr_a")
    intruder = _client("usr_b")

    session_id = owner.post("/api/v1/chat/sessions", json={}).json()["data"]["session_id"]

    # Another user cannot see, message, or delete the session.
    assert intruder.get("/api/v1/chat/sessions").json()["data"] == []
    assert intruder.get(f"/api/v1/chat/sessions/{session_id}/messages").status_code == 404
    assert (
        intruder.post(
            f"/api/v1/chat/sessions/{session_id}/messages", json={"content": "hi"}
        ).status_code
        == 404
    )
    assert intruder.delete(f"/api/v1/chat/sessions/{session_id}").status_code == 404


def test_delete_session() -> None:
    client = _client()
    session_id = client.post("/api/v1/chat/sessions", json={}).json()["data"]["session_id"]

    deleted = client.delete(f"/api/v1/chat/sessions/{session_id}")
    assert deleted.status_code == 200
    assert deleted.json()["data"]["deleted"] is True

    assert client.get("/api/v1/chat/sessions").json()["data"] == []
    assert client.get(f"/api/v1/chat/sessions/{session_id}/messages").status_code == 404
