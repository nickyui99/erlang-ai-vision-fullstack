"""index clips.expires_at and recordings.retention_until for the retention sweep

Revision ID: 20260707_0008
Revises: 20260703_0007
Create Date: 2026-07-07

"""

from typing import Sequence, Union

from alembic import op


revision: str = "20260707_0008"
down_revision: Union[str, None] = "20260703_0007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_index("idx_clips_expires_at", "clips", ["expires_at"])
    op.create_index("idx_recordings_retention_until", "recordings", ["retention_until"])


def downgrade() -> None:
    op.drop_index("idx_recordings_retention_until", table_name="recordings")
    op.drop_index("idx_clips_expires_at", table_name="clips")
