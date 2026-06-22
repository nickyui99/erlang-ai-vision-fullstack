"""add agents.parent_agent_id (assign definitions as sub-agents)

Revision ID: 20260622_0003
Revises: 20260622_0002
Create Date: 2026-06-22

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260622_0003"
down_revision: Union[str, None] = "20260622_0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("agents", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column("parent_agent_id", sa.String(length=64), nullable=True)
        )
        batch_op.create_foreign_key(
            "fk_agents_parent_agent_id",
            "agents",
            ["parent_agent_id"],
            ["agent_id"],
            ondelete="CASCADE",
        )
        batch_op.create_index(
            "idx_agents_parent_agent_id", ["parent_agent_id"]
        )


def downgrade() -> None:
    with op.batch_alter_table("agents", schema=None) as batch_op:
        batch_op.drop_index("idx_agents_parent_agent_id")
        batch_op.drop_constraint("fk_agents_parent_agent_id", type_="foreignkey")
        batch_op.drop_column("parent_agent_id")
