"""make agents.device_id nullable (bind at arm time)

Revision ID: 20260622_0002
Revises: 20260620_0001
Create Date: 2026-06-22

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260622_0002"
down_revision: Union[str, None] = "20260620_0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("agents") as batch_op:
        batch_op.alter_column(
            "device_id",
            existing_type=sa.String(length=64),
            nullable=True,
        )


def downgrade() -> None:
    # Disarmed agents may have a NULL device_id; clear those rows would be
    # required before reinstating NOT NULL. We only restore the constraint.
    with op.batch_alter_table("agents") as batch_op:
        batch_op.alter_column(
            "device_id",
            existing_type=sa.String(length=64),
            nullable=False,
        )
