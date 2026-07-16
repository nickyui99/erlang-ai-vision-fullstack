from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class ChatSession(Base):
    """One conversation thread between a user and the Erlang AI Agent.

    Distinct from the ``agents`` table (camera-monitoring rules): a chat session
    is a persisted assistant conversation, owned by a user and holding an ordered
    list of :class:`ChatMessage` turns.
    """

    __tablename__ = "chat_sessions"
    __table_args__ = (Index("idx_chat_sessions_user_updated", "user_id", "updated_at"),)

    session_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.user_id", ondelete="CASCADE"), nullable=False
    )
    # Auto-generated from the first user message; blank until then.
    title: Mapped[str] = mapped_column(String(255), nullable=False, server_default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class ChatMessage(Base):
    """A single turn in a :class:`ChatSession`.

    ``role`` is one of ``user``, ``assistant``, or ``system``. Ordering is by
    ``created_at`` (ascending) within a session.
    """

    __tablename__ = "chat_messages"
    __table_args__ = (
        Index("idx_chat_messages_session_created", "session_id", "created_at", "message_id"),
    )

    message_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    session_id: Mapped[str] = mapped_column(
        String(64),
        ForeignKey("chat_sessions.session_id", ondelete="CASCADE"),
        nullable=False,
    )
    role: Mapped[str] = mapped_column(String(16), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
