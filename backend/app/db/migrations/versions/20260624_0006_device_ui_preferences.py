"""add device UI preferences

Revision ID: 20260624_0006
Revises: 20260623_0005
Create Date: 2026-06-24

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260624_0006"
down_revision: Union[str, None] = "20260623_0005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("devices", schema=None) as batch_op:
        batch_op.add_column(sa.Column("is_favorite", sa.Boolean(), nullable=False, server_default="0"))
        batch_op.add_column(sa.Column("presets", sa.JSON(), nullable=True))
        batch_op.add_column(sa.Column("ptz_correction_pan", sa.Integer(), nullable=False, server_default="0"))
        batch_op.add_column(sa.Column("ptz_correction_tilt", sa.Integer(), nullable=False, server_default="0"))


def downgrade() -> None:
    with op.batch_alter_table("devices", schema=None) as batch_op:
        batch_op.drop_column("ptz_correction_tilt")
        batch_op.drop_column("ptz_correction_pan")
        batch_op.drop_column("presets")
        batch_op.drop_column("is_favorite")