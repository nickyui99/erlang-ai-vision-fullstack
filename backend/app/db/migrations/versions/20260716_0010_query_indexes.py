"""add composite indexes for chat, media, and audit queries

Revision ID: 20260716_0010
Revises: 20260715_0009
Create Date: 2026-07-16

"""

from typing import Sequence, Union

from alembic import op


revision: str = "20260716_0010"
down_revision: Union[str, None] = "20260715_0009"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_index("idx_chat_sessions_user_id", table_name="chat_sessions")
    op.create_index("idx_chat_sessions_user_updated", "chat_sessions", ["user_id", "updated_at"])
    op.drop_index("idx_chat_messages_session_id", table_name="chat_messages")
    op.create_index(
        "idx_chat_messages_session_created",
        "chat_messages",
        ["session_id", "created_at", "message_id"],
    )
    op.drop_index("idx_clips_user_id", table_name="clips")
    op.create_index("idx_clips_event_user_created", "clips", ["event_id", "user_id", "created_at"])
    op.create_index("idx_clips_device_user_created", "clips", ["device_id", "user_id", "created_at"])
    op.create_index("idx_recordings_device_user_start", "recordings", ["device_id", "user_id", "start_time"])
    op.create_index("idx_tool_audit_event_user_timestamp", "tool_audit", ["event_id", "user_id", "timestamp"])


def downgrade() -> None:
    op.drop_index("idx_tool_audit_event_user_timestamp", table_name="tool_audit")
    op.drop_index("idx_recordings_device_user_start", table_name="recordings")
    op.drop_index("idx_clips_device_user_created", table_name="clips")
    op.drop_index("idx_clips_event_user_created", table_name="clips")
    op.create_index("idx_clips_user_id", "clips", ["user_id"])
    op.drop_index("idx_chat_messages_session_created", table_name="chat_messages")
