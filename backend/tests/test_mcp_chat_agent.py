"""MCP tool server + agentic chat loop.

Covers: the tool registry matches the chat permission table, the bearer gate
guards the mounted MCP app, and the chat turn drives Qwen tool-calls through an
(injected) MCP runner — including the plain-chat fallback when MCP is down.
"""

import asyncio
from datetime import UTC, datetime
import os
from pathlib import Path
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{(Path(tempfile.gettempdir()) / 'erlang_mcp_pytest.db').as_posix()}"

from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402

from app.core.security import create_signed_token  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.mcp import permissions  # noqa: E402
from app.mcp.server import MCP_TOKEN_PURPOSE, MCPBearerGate, mcp_server  # noqa: E402
from app.models.chat import ChatSession  # noqa: E402
from app.models.user import User  # noqa: E402
from app.services import chat_service  # noqa: E402
from app.services.qwen_client import BaseQwenClient, QwenResponse, QwenToolCall  # noqa: E402


EXPECTED_TOOLS = {
    "list_devices", "get_device_status", "pan_camera", "tilt_camera",
    "get_live_snapshot", "query_events", "get_event_clip", "list_recordings",
    "list_agents", "create_agent", "assign_agent", "unassign_agent",
}


def setup_function() -> None:
    asyncio.run(_reset_db())


async def _reset_db() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    factory = async_sessionmaker(engine, expire_on_commit=False)
    async with factory() as session:
        now = datetime.now(UTC)
        session.add(
            User(user_id="usr_mcp", google_sub="gsub_mcp", email="mcp@example.com",
                 email_verified=True, role="user", created_at=now, updated_at=now)
        )
        await session.commit()
        session.add(ChatSession(session_id="chat_mcp_1", user_id="usr_mcp", title=""))
        await session.commit()


# --------------------------------------------------------------------- registry

def test_mcp_server_registers_expected_tools() -> None:
    tools = asyncio.run(mcp_server.list_tools())
    names = {tool.name for tool in tools}
    assert names == EXPECTED_TOOLS
    # Every registered tool must be explicitly allowed for the chat scope —
    # otherwise it would exist but always answer tool_not_permitted.
    for name in names:
        assert permissions.is_allowed(name, scope="chat"), name


def test_verify_scope_table_unchanged() -> None:
    # The verification agent's autonomy is untouched by the chat table.
    assert permissions.is_allowed("pan_camera")
    assert not permissions.is_allowed("create_agent")
    assert not permissions.is_allowed("send_emergency_alert", scope="chat")


# ------------------------------------------------------------------ bearer gate

def _run_gate(headers: list[tuple[bytes, bytes]]) -> tuple[int | None, bool]:
    """Drive MCPBearerGate with one fake HTTP request; returns (status, inner_called)."""
    inner_called = False

    async def inner_app(scope, receive, send):
        nonlocal inner_called
        inner_called = True
        await send({"type": "http.response.start", "status": 200, "headers": []})
        await send({"type": "http.response.body", "body": b"ok"})

    sent: list[dict] = []

    async def send(message):
        sent.append(message)

    async def receive():
        return {"type": "http.request", "body": b"", "more_body": False}

    gate = MCPBearerGate(inner_app)
    asyncio.run(gate({"type": "http", "headers": headers}, receive, send))
    status = next((m["status"] for m in sent if m["type"] == "http.response.start"), None)
    return status, inner_called


def test_bearer_gate_rejects_missing_and_bad_tokens() -> None:
    status, inner = _run_gate([])
    assert status == 401 and not inner
    status, inner = _run_gate([(b"authorization", b"Bearer not-a-real-token")])
    assert status == 401 and not inner


def test_bearer_gate_passes_valid_token() -> None:
    token = create_signed_token({"user_id": "usr_mcp"}, MCP_TOKEN_PURPOSE, 60)
    status, inner = _run_gate([(b"authorization", f"Bearer {token}".encode())])
    assert status == 200 and inner


# ------------------------------------------------------------- agentic chat turn

class FakeRunner:
    """Stands in for McpToolRunner: records calls, returns canned tool output."""

    calls: list[tuple[str, dict]] = []

    def __init__(self, user_id: str) -> None:
        self.user_id = user_id

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return None

    async def list_tool_specs(self) -> list[dict]:
        return [{
            "type": "function",
            "function": {"name": "list_devices", "description": "List cameras",
                         "parameters": {"type": "object", "properties": {}}},
        }]

    async def call(self, name: str, arguments: dict):
        FakeRunner.calls.append((name, arguments))
        return '{"ok": true, "devices": [{"name": "Front Door"}], "count": 1}', []


class ToolCallingClient(BaseQwenClient):
    """First turn requests list_devices; second turn answers using the result."""

    def __init__(self) -> None:
        self.turns: list[list[dict]] = []

    async def verify(self, request, *, repair: bool = False) -> str:
        raise NotImplementedError

    async def chat(self, messages, *, tools=None) -> QwenResponse:
        self.turns.append(messages)
        if len(self.turns) == 1:
            assert tools, "tool specs must be offered on the first turn"
            return QwenResponse(content=None, tool_calls=[
                QwenToolCall(id="call_1", name="list_devices", arguments={})
            ])
        return QwenResponse(content="You have 1 camera: Front Door.")


class BrokenRunner:
    def __init__(self, user_id: str) -> None:
        pass

    async def __aenter__(self):
        raise ConnectionError("MCP server unreachable")

    async def __aexit__(self, *exc):
        return None


class PlainClient(BaseQwenClient):
    async def verify(self, request, *, repair: bool = False) -> str:
        raise NotImplementedError

    async def chat(self, messages, *, tools=None) -> QwenResponse:
        return QwenResponse(content="plain answer, no tools")


def test_agentic_turn_runs_tools_and_persists_reply() -> None:
    FakeRunner.calls = []

    async def drive() -> str:
        factory = async_sessionmaker(engine, expire_on_commit=False)
        async with factory() as session:
            chat = await chat_service.get_owned_session(session, "usr_mcp", "chat_mcp_1")
            client = ToolCallingClient()
            msg = await chat_service.generate_turn(
                session, chat, "what cameras do I have?",
                client=client, runner_factory=FakeRunner,
            )
            # The second model turn must carry the tool result back.
            tool_msgs = [m for m in client.turns[1] if m.get("role") == "tool"]
            assert tool_msgs and "Front Door" in tool_msgs[0]["content"]
            return msg.content

    reply = asyncio.run(drive())
    assert FakeRunner.calls == [("list_devices", {})]
    assert reply == "You have 1 camera: Front Door."


def test_agentic_turn_falls_back_when_mcp_down() -> None:
    async def drive() -> str:
        factory = async_sessionmaker(engine, expire_on_commit=False)
        async with factory() as session:
            chat = await chat_service.get_owned_session(session, "usr_mcp", "chat_mcp_1")
            msg = await chat_service.generate_turn(
                session, chat, "hello?",
                client=PlainClient(), runner_factory=BrokenRunner,
            )
            return msg.content

    assert asyncio.run(drive()) == "plain answer, no tools"
