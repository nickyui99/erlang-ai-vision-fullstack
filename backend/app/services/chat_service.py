"""Chat session orchestration for the Erlang AI Agent.

Owns the persistence + LLM turn logic for conversational chat, kept separate
from the ``agents`` (camera-rule) domain.

A turn is agentic: the assistant connects to the platform's own MCP server
(``app/mcp/server.py``) as an MCP client, offers its tools to Qwen, and loops on
tool calls (snapshot, pan, query events, create/arm agents, ...) up to
``qwen_max_tool_turns`` before replying. If the MCP server is unreachable the
turn degrades to plain text chat — the assistant still answers, tool-less.
"""

from __future__ import annotations

import json
import logging
import secrets
from contextlib import AsyncExitStack
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.prompts import (
    ERLANG_CHAT_TOOLS_SYSTEM_PROMPT,
    build_chat_messages,
)
from app.core.config import settings
from app.core.security import create_signed_token
from app.models.chat import ChatMessage, ChatSession
from app.services.qwen_client import BaseQwenClient, QwenError, QwenResponse, get_qwen_client


log = logging.getLogger("app.services.chat_service")

_TITLE_MAX = 60


def _session_id() -> str:
    return f"chat_{secrets.token_urlsafe(18)}"


def _message_id() -> str:
    return f"msg_{secrets.token_urlsafe(18)}"


def _derive_title(text: str) -> str:
    normalized = " ".join(text.split())
    if len(normalized) <= _TITLE_MAX:
        return normalized
    return normalized[: _TITLE_MAX - 1].rstrip() + "…"


class ChatDailyLimitExceeded(Exception):
    """The account has used up its chat messages for the current UTC day."""

    def __init__(self, limit: int) -> None:
        self.limit = limit
        super().__init__(f"daily chat message limit reached ({limit}/day)")


async def _messages_sent_today(session: AsyncSession, user_id: str) -> int:
    """User-role messages this account sent since UTC midnight, across all sessions."""
    day_start = datetime.now(UTC).replace(hour=0, minute=0, second=0, microsecond=0)
    result = await session.execute(
        select(func.count(ChatMessage.message_id))
        .join(ChatSession, ChatMessage.session_id == ChatSession.session_id)
        .where(
            ChatSession.user_id == user_id,
            ChatMessage.role == "user",
            ChatMessage.created_at >= day_start,
        )
    )
    return int(result.scalar_one() or 0)


async def enforce_daily_limit(session: AsyncSession, user_id: str) -> None:
    """Raise :class:`ChatDailyLimitExceeded` if the account hit today's cap.

    A cost guardrail, not billing: each agentic turn can spend several Qwen calls
    (tool loop) plus MCP tool executions. 0 disables the cap.
    """
    limit = settings.chat_daily_message_limit
    if limit <= 0:
        return
    if await _messages_sent_today(session, user_id) >= limit:
        raise ChatDailyLimitExceeded(limit)


class McpToolRunner:
    """One chat turn's MCP client connection to the platform tool server.

    Mints a short-lived ``mcp_access`` token for the user and speaks streamable
    HTTP to the server this same process mounts at ``{api_prefix}/mcp``.
    """

    def __init__(self, user_id: str) -> None:
        from app.mcp.server import MCP_TOKEN_PURPOSE

        token = create_signed_token(
            {"user_id": user_id}, MCP_TOKEN_PURPOSE, settings.mcp_token_ttl_seconds
        )
        self._url = (
            settings.mcp_internal_base_url.rstrip("/") + settings.api_prefix + "/mcp/"
        )
        self._headers = {"Authorization": f"Bearer {token}"}
        self._stack = AsyncExitStack()
        self._session = None

    async def __aenter__(self) -> "McpToolRunner":
        from mcp import ClientSession
        from mcp.client.streamable_http import streamablehttp_client

        read, write, _ = await self._stack.enter_async_context(
            streamablehttp_client(self._url, headers=self._headers)
        )
        self._session = await self._stack.enter_async_context(ClientSession(read, write))
        await self._session.initialize()
        return self

    async def __aexit__(self, *exc) -> None:
        await self._stack.aclose()

    async def list_tool_specs(self) -> list[dict]:
        """The server's tools as OpenAI-style function specs for the Qwen API."""
        listed = await self._session.list_tools()
        return [
            {
                "type": "function",
                "function": {
                    "name": tool.name,
                    "description": tool.description or "",
                    "parameters": tool.inputSchema
                    or {"type": "object", "properties": {}},
                },
            }
            for tool in listed.tools
        ]

    async def call(self, name: str, arguments: dict) -> tuple[str, list[str]]:
        """Run one tool; returns (text for the tool message, image data-URLs)."""
        result = await self._session.call_tool(name, arguments or {})
        texts: list[str] = []
        images: list[str] = []
        for part in result.content:
            part_type = getattr(part, "type", "")
            if part_type == "text":
                texts.append(part.text)
            elif part_type == "image":
                images.append(f"data:{part.mimeType};base64,{part.data}")
                texts.append("(image attached below)")
        if getattr(result, "isError", False) and not texts:
            texts.append("tool call failed")
        return "\n".join(texts) or "(no output)", images


def _assistant_tool_message(response: QwenResponse) -> dict:
    return {
        "role": "assistant",
        "content": response.content or "",
        "tool_calls": [
            {
                "id": call.id,
                "type": "function",
                "function": {"name": call.name, "arguments": json.dumps(call.arguments)},
            }
            for call in response.tool_calls
        ],
    }


async def _agentic_reply(
    user_id: str,
    history: list[dict],
    client: BaseQwenClient,
    *,
    runner_factory=None,
) -> str:
    """Run the tool loop against the MCP server; fall back to plain chat if it's down."""
    factory = runner_factory or McpToolRunner
    try:
        async with factory(user_id) as runner:
            tool_specs = await runner.list_tool_specs()
            messages = build_chat_messages(
                history, system_prompt=ERLANG_CHAT_TOOLS_SYSTEM_PROMPT
            )
            for _ in range(max(1, settings.qwen_max_tool_turns)):
                response = await client.chat(messages, tools=tool_specs)
                if not response.tool_calls:
                    return (response.content or "").strip() or "…"
                messages.append(_assistant_tool_message(response))
                image_urls: list[str] = []
                for call in response.tool_calls:
                    text, images = await runner.call(call.name, call.arguments)
                    messages.append(
                        {"role": "tool", "tool_call_id": call.id, "content": text}
                    )
                    image_urls.extend(images)
                if image_urls:
                    # Tool-role messages are text-only in the OpenAI schema; images
                    # ride in as a user-role multimodal part so vision models see them.
                    content: list[dict] = [
                        {"type": "text", "text": "Images returned by the tool calls above:"}
                    ]
                    content.extend(
                        {"type": "image_url", "image_url": {"url": url}}
                        for url in image_urls
                    )
                    messages.append({"role": "user", "content": content})
            # Tool budget exhausted: force a final text answer without tools.
            response = await client.chat(messages)
            return (response.content or "").strip() or "…"
    except QwenError:
        raise  # the API layer maps this to 502 agent_unavailable
    except Exception:  # noqa: BLE001 - MCP down must degrade, not kill the chat
        log.warning("MCP tool loop unavailable; falling back to plain chat", exc_info=True)
        response = await client.chat(build_chat_messages(history))
        return (response.content or "").strip() or "…"


async def create_session(
    session: AsyncSession,
    user_id: str,
    *,
    first_message: str | None = None,
    client: BaseQwenClient | None = None,
) -> ChatSession:
    """Create a session. If ``first_message`` is given, run the opening turn."""

    # Check the cap before creating anything, so a 429 doesn't leave an empty
    # orphan session behind (generate_turn re-checks for the direct-message path).
    if first_message:
        await enforce_daily_limit(session, user_id)
    chat = ChatSession(session_id=_session_id(), user_id=user_id, title="")
    session.add(chat)
    await session.commit()
    await session.refresh(chat)
    if first_message:
        await generate_turn(session, chat, first_message, client=client)
        await session.refresh(chat)
    return chat


async def list_sessions(session: AsyncSession, user_id: str) -> list[ChatSession]:
    result = await session.execute(
        select(ChatSession)
        .where(ChatSession.user_id == user_id)
        .order_by(ChatSession.updated_at.desc())
    )
    return list(result.scalars())


async def get_owned_session(
    session: AsyncSession, user_id: str, session_id: str
) -> ChatSession | None:
    result = await session.execute(
        select(ChatSession).where(
            ChatSession.session_id == session_id, ChatSession.user_id == user_id
        )
    )
    return result.scalar_one_or_none()


async def list_messages(session: AsyncSession, session_id: str) -> list[ChatMessage]:
    result = await session.execute(
        select(ChatMessage)
        .where(ChatMessage.session_id == session_id)
        .order_by(ChatMessage.created_at.asc(), ChatMessage.message_id.asc())
    )
    return list(result.scalars())


async def delete_session(session: AsyncSession, chat: ChatSession) -> None:
    await session.delete(chat)
    await session.commit()


async def _history_for(session: AsyncSession, session_id: str) -> list[dict]:
    messages = await list_messages(session, session_id)
    return [{"role": m.role, "content": m.content} for m in messages]


def _tools_available(runner_factory) -> bool:
    """Whether this turn should attempt the MCP tool loop.

    Tests stay hermetic: in the test env the loop only runs when a runner factory
    is injected explicitly (otherwise the client would dial a live localhost port).
    """
    if runner_factory is not None:
        return True
    return settings.mcp_server_enabled and settings.app_env != "test"


async def generate_turn(
    session: AsyncSession,
    chat: ChatSession,
    user_content: str,
    *,
    client: BaseQwenClient | None = None,
    runner_factory=None,
) -> ChatMessage:
    """Append the user message, get the assistant reply, persist and return it.

    Raises :class:`ChatDailyLimitExceeded` when the account's per-day message cap
    is spent (checked before anything is persisted or any model call is made).
    """

    await enforce_daily_limit(session, chat.user_id)
    # The chatbot runs on the TEXT default (qwen3.7-max); only per-event image
    # verification runs on the cheaper vision default (qwen3.7-plus). When a chat
    # turn carries a snapshot from an MCP tool, QwenClient's modality-aware
    # fallback chain still routes image payloads that the primary can't take.
    client = client or get_qwen_client(model=settings.qwen_text_model)

    # Set created_at explicitly: the SQLite server_default (func.now()) only has
    # second precision, which would tie the user and assistant turns and make
    # their order nondeterministic. Python timestamps keep microsecond precision.
    user_now = datetime.now(UTC)
    user_msg = ChatMessage(
        message_id=_message_id(),
        session_id=chat.session_id,
        role="user",
        content=user_content,
        created_at=user_now,
    )
    session.add(user_msg)
    if not chat.title:
        chat.title = _derive_title(user_content)
    chat.updated_at = user_now
    await session.commit()

    history = await _history_for(session, chat.session_id)
    if _tools_available(runner_factory):
        reply_text = await _agentic_reply(
            chat.user_id, history, client, runner_factory=runner_factory
        )
    else:
        response = await client.chat(build_chat_messages(history))
        reply_text = (response.content or "").strip() or "…"

    assistant_now = datetime.now(UTC)
    assistant_msg = ChatMessage(
        message_id=_message_id(),
        session_id=chat.session_id,
        role="assistant",
        content=reply_text,
        created_at=assistant_now,
    )
    session.add(assistant_msg)
    chat.updated_at = assistant_now
    await session.commit()
    await session.refresh(assistant_msg)
    return assistant_msg
