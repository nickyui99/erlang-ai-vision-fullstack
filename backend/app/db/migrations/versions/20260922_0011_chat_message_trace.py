"""add chat_messages.trace

Holds how an assistant reply was reached — the model's reasoning and the MCP
tool calls it made — so the chat UI can show the thinking panel for older turns
after a reload, not just for the reply that just streamed in.

Revision ID: 20260922_0011
Revises: 20260716_0010
Create Date: 2026-09-22

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260922_0011"
down_revision: Union[str, None] = "20260716_0010"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Nullable with no server default: user turns and pre-existing assistant
    # turns simply have no trace, and the UI renders them unchanged.
    with op.batch_alter_table("chat_messages", schema=None) as batch_op:
        batch_op.add_column(sa.Column("trace", sa.JSON(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("chat_messages", schema=None) as batch_op:
        batch_op.drop_column("trace")
