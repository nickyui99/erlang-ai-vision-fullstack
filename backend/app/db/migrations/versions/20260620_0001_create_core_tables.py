"""create core tables

Revision ID: 20260620_0001
Revises:
Create Date: 2026-06-20

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260620_0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("google_sub", sa.String(length=255), nullable=False),
        sa.Column("email", sa.String(length=320), nullable=False),
        sa.Column("email_verified", sa.Boolean(), server_default="0", nullable=False),
        sa.Column("display_name", sa.String(length=255), nullable=True),
        sa.Column("avatar_url", sa.String(length=2048), nullable=True),
        sa.Column("role", sa.String(length=32), server_default="user", nullable=False),
        sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("user_id"),
        sa.UniqueConstraint("email"),
        sa.UniqueConstraint("google_sub"),
    )
    op.create_table(
        "devices",
        sa.Column("device_id", sa.String(length=64), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("edge_token_hash", sa.String(length=255), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("location", sa.String(length=255), nullable=True),
        sa.Column("health_status", sa.String(length=32), server_default="unknown", nullable=False),
        sa.Column("rssi", sa.Float(), nullable=True),
        sa.Column("fps", sa.Float(), nullable=True),
        sa.Column("current_pan", sa.Integer(), server_default="90", nullable=False),
        sa.Column("last_seen", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("current_pan >= 0 AND current_pan <= 180", name="ck_devices_current_pan_range"),
        sa.ForeignKeyConstraint(["user_id"], ["users.user_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("device_id"),
    )
    op.create_index("idx_devices_user_id", "devices", ["user_id"])
    op.create_table(
        "agents",
        sa.Column("agent_id", sa.String(length=64), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("device_id", sa.String(length=64), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("location", sa.String(length=255), nullable=True),
        sa.Column("nl_rule", sa.Text(), nullable=False),
        sa.Column("compiled_prompt", sa.Text(), nullable=True),
        sa.Column("compiled_edge_config", sa.JSON(), nullable=True),
        sa.Column("state", sa.String(length=32), server_default="disarmed", nullable=False),
        sa.Column("enabled", sa.Boolean(), server_default="1", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["device_id"], ["devices.device_id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.user_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("agent_id"),
    )
    op.create_index("idx_agents_device_id", "agents", ["device_id"])
    op.create_index("idx_agents_user_id", "agents", ["user_id"])
    op.create_table(
        "events",
        sa.Column("event_id", sa.String(length=64), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("agent_id", sa.String(length=64), nullable=False),
        sa.Column("device_id", sa.String(length=64), nullable=False),
        sa.Column("idempotency_key", sa.String(length=255), nullable=False),
        sa.Column("timestamp", sa.DateTime(timezone=True), nullable=False),
        sa.Column("event_type", sa.String(length=64), nullable=False),
        sa.Column("stage1_result", sa.JSON(), nullable=True),
        sa.Column("stage2_verdict", sa.JSON(), nullable=True),
        sa.Column("stage3_verdict", sa.JSON(), nullable=True),
        sa.Column("severity", sa.String(length=32), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=True),
        sa.Column("summary", sa.Text(), nullable=True),
        sa.Column("degraded", sa.Boolean(), server_default="0", nullable=False),
        sa.Column("status", sa.String(length=32), server_default="candidate", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["agent_id"], ["agents.agent_id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["device_id"], ["devices.device_id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.user_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("event_id"),
        sa.UniqueConstraint("device_id", "idempotency_key", name="uq_events_device_idempotency_key"),
    )
    op.create_index("idx_events_device_timestamp", "events", ["device_id", "timestamp"])
    op.create_index("idx_events_status", "events", ["status"])
    op.create_index("idx_events_user_timestamp", "events", ["user_id", "timestamp"])
    op.create_table(
        "clips",
        sa.Column("clip_id", sa.String(length=64), nullable=False),
        sa.Column("event_id", sa.String(length=64), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("device_id", sa.String(length=64), nullable=False),
        sa.Column("idempotency_key", sa.String(length=255), nullable=True),
        sa.Column("storage_type", sa.String(length=32), nullable=False),
        sa.Column("storage_path", sa.Text(), nullable=True),
        sa.Column("oss_object_key", sa.Text(), nullable=True),
        sa.Column("clip_type", sa.String(length=32), server_default="event", nullable=False),
        sa.Column("duration_seconds", sa.Integer(), nullable=True),
        sa.Column("file_size_bytes", sa.BigInteger(), nullable=True),
        sa.Column("mime_type", sa.String(length=255), nullable=True),
        sa.Column("checksum_sha256", sa.String(length=64), nullable=True),
        sa.Column("status", sa.String(length=32), server_default="pending_upload", nullable=False),
        sa.Column("upload_id", sa.String(length=255), nullable=True),
        sa.Column("upload_started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("upload_completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("upload_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("upload_error", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["device_id"], ["devices.device_id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["event_id"], ["events.event_id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.user_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("clip_id"),
        sa.UniqueConstraint("device_id", "idempotency_key", name="uq_clips_device_idempotency_key"),
    )
    op.create_index("idx_clips_event_id", "clips", ["event_id"])
    op.create_index("idx_clips_user_id", "clips", ["user_id"])
    op.create_table(
        "recordings",
        sa.Column("recording_id", sa.String(length=64), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("device_id", sa.String(length=64), nullable=False),
        sa.Column("start_time", sa.DateTime(timezone=True), nullable=False),
        sa.Column("end_time", sa.DateTime(timezone=True), nullable=False),
        sa.Column("storage_type", sa.String(length=32), nullable=False),
        sa.Column("storage_path", sa.Text(), nullable=True),
        sa.Column("oss_object_key", sa.Text(), nullable=True),
        sa.Column("duration_seconds", sa.Integer(), nullable=True),
        sa.Column("file_size_bytes", sa.BigInteger(), nullable=True),
        sa.Column("mime_type", sa.String(length=255), nullable=True),
        sa.Column("checksum_sha256", sa.String(length=64), nullable=True),
        sa.Column("status", sa.String(length=32), server_default="local_only", nullable=False),
        sa.Column("upload_id", sa.String(length=255), nullable=True),
        sa.Column("upload_started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("upload_completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("upload_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("upload_error", sa.Text(), nullable=True),
        sa.Column("retention_until", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["device_id"], ["devices.device_id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.user_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("recording_id"),
    )
    op.create_index("idx_recordings_user_start", "recordings", ["user_id", "start_time"])
    op.create_table(
        "alerts",
        sa.Column("alert_id", sa.String(length=64), nullable=False),
        sa.Column("event_id", sa.String(length=64), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("channel", sa.String(length=64), nullable=False),
        sa.Column("sent_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.String(length=32), server_default="pending", nullable=False),
        sa.Column("dedupe_key", sa.String(length=255), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["event_id"], ["events.event_id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.user_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("alert_id"),
        sa.UniqueConstraint("dedupe_key", name="uq_alerts_dedupe_key"),
    )
    op.create_index("idx_alerts_user_id", "alerts", ["user_id"])
    op.create_table(
        "tool_audit",
        sa.Column("audit_id", sa.String(length=64), nullable=False),
        sa.Column("event_id", sa.String(length=64), nullable=True),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("device_id", sa.String(length=64), nullable=True),
        sa.Column("tool_name", sa.String(length=128), nullable=False),
        sa.Column("arguments", sa.JSON(), nullable=True),
        sa.Column("result", sa.JSON(), nullable=True),
        sa.Column("called_by", sa.String(length=64), nullable=False),
        sa.Column("timestamp", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["device_id"], ["devices.device_id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["event_id"], ["events.event_id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["user_id"], ["users.user_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("audit_id"),
    )
    op.create_index("idx_tool_audit_user_timestamp", "tool_audit", ["user_id", "timestamp"])


def downgrade() -> None:
    op.drop_index("idx_tool_audit_user_timestamp", table_name="tool_audit")
    op.drop_table("tool_audit")
    op.drop_index("idx_alerts_user_id", table_name="alerts")
    op.drop_table("alerts")
    op.drop_index("idx_recordings_user_start", table_name="recordings")
    op.drop_table("recordings")
    op.drop_index("idx_clips_user_id", table_name="clips")
    op.drop_index("idx_clips_event_id", table_name="clips")
    op.drop_table("clips")
    op.drop_index("idx_events_user_timestamp", table_name="events")
    op.drop_index("idx_events_status", table_name="events")
    op.drop_index("idx_events_device_timestamp", table_name="events")
    op.drop_table("events")
    op.drop_index("idx_agents_user_id", table_name="agents")
    op.drop_index("idx_agents_device_id", table_name="agents")
    op.drop_table("agents")
    op.drop_index("idx_devices_user_id", table_name="devices")
    op.drop_table("devices")
    op.drop_table("users")
