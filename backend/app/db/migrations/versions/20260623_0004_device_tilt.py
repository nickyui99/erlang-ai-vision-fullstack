"""add devices.current_tilt (SG90 two-axis gimbal)

Revision ID: 20260623_0004
Revises: 20260622_0003
Create Date: 2026-06-23

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260623_0004"
down_revision: Union[str, None] = "20260622_0003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("devices", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column(
                "current_tilt",
                sa.Integer(),
                nullable=False,
                server_default="90",
            )
        )
        batch_op.create_check_constraint(
            "ck_devices_current_tilt_range",
            "current_tilt >= 0 AND current_tilt <= 180",
        )


def downgrade() -> None:
    with op.batch_alter_table("devices", schema=None) as batch_op:
        batch_op.drop_constraint("ck_devices_current_tilt_range", type_="check")
        batch_op.drop_column("current_tilt")
