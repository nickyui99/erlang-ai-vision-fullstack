from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db_session
from app.models.chat import ChatSession
from app.models.user import User
from app.schemas.chat import (
    ChatMessageRead,
    ChatSendRequest,
    ChatSessionCreate,
    ChatSessionRead,
)
from app.services import chat_service
from app.services.qwen_client import QwenError


router = APIRouter(prefix="/chat", tags=["chat"])


def _limit_exceeded(exc: chat_service.ChatDailyLimitExceeded) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail={
            "code": "chat_daily_limit_reached",
            "message": (
                f"Daily chat limit reached ({exc.limit} messages/day). "
                "It resets at midnight UTC."
            ),
        },
    )


async def _get_owned_session(
    session: AsyncSession, user_id: str, session_id: str
) -> ChatSession:
    chat = await chat_service.get_owned_session(session, user_id, session_id)
    if chat is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Chat session was not found"},
        )
    return chat


@router.get("/sessions")
async def list_chat_sessions(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    sessions = await chat_service.list_sessions(session, current_user.user_id)
    return {
        "data": [
            ChatSessionRead.model_validate(s).model_dump(mode="json") for s in sessions
        ]
    }


@router.post("/sessions", status_code=status.HTTP_201_CREATED)
async def create_chat_session(
    payload: ChatSessionCreate | None = None,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    first_message = payload.first_message if payload else None
    try:
        chat = await chat_service.create_session(
            session, current_user.user_id, first_message=first_message
        )
    except chat_service.ChatDailyLimitExceeded as exc:
        raise _limit_exceeded(exc) from exc
    except QwenError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"code": "agent_unavailable", "message": "The AI agent is unavailable"},
        ) from exc
    return {"data": ChatSessionRead.model_validate(chat).model_dump(mode="json")}


@router.get("/sessions/{session_id}/messages")
async def list_chat_messages(
    session_id: str,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    await _get_owned_session(session, current_user.user_id, session_id)
    messages = await chat_service.list_messages(session, session_id)
    return {
        "data": [
            ChatMessageRead.model_validate(m).model_dump(mode="json") for m in messages
        ]
    }


@router.post("/sessions/{session_id}/messages", status_code=status.HTTP_201_CREATED)
async def send_chat_message(
    session_id: str,
    payload: ChatSendRequest,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    chat = await _get_owned_session(session, current_user.user_id, session_id)
    try:
        assistant_msg = await chat_service.generate_turn(session, chat, payload.content)
    except chat_service.ChatDailyLimitExceeded as exc:
        raise _limit_exceeded(exc) from exc
    except QwenError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"code": "agent_unavailable", "message": "The AI agent is unavailable"},
        ) from exc
    return {"data": ChatMessageRead.model_validate(assistant_msg).model_dump(mode="json")}


@router.delete("/sessions/{session_id}")
async def delete_chat_session(
    session_id: str,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    chat = await _get_owned_session(session, current_user.user_id, session_id)
    await chat_service.delete_session(session, chat)
    return {"data": {"session_id": session_id, "deleted": True}}
