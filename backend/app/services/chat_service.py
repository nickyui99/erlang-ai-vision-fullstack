"""Chat session orchestration for the Erlang AI Agent.

Owns the persistence + LLM turn logic for conversational chat, kept separate
from the ``agents`` (camera-rule) domain. This first cut is non-streaming: a
turn stores the user message, calls Qwen once, and persists the reply. Streaming
is layered on top in a later step.
"""

from __future__ import annotations

import secrets
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.prompts import build_chat_messages
from app.core.config import settings
from app.models.chat import ChatMessage, ChatSession
from app.services.qwen_client import BaseQwenClient, get_qwen_client


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


async def create_session(
    session: AsyncSession,
    user_id: str,
    *,
    first_message: str | None = None,
    client: BaseQwenClient | None = None,
) -> ChatSession:
    """Create a session. If ``first_message`` is given, run the opening turn."""

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


async def generate_turn(
    session: AsyncSession,
    chat: ChatSession,
    user_content: str,
    *,
    client: BaseQwenClient | None = None,
) -> ChatMessage:
    """Append the user message, get the assistant reply, persist and return it."""

    # Chat is text-only, so drive it from the free-first text model (not the vision default).
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
