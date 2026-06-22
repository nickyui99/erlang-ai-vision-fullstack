from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, JSON, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Agent(Base):
    __tablename__ = "agents"
    __table_args__ = (
        Index("idx_agents_user_id", "user_id"),
        Index("idx_agents_device_id", "device_id"),
        Index("idx_agents_parent_agent_id", "parent_agent_id"),
    )

    agent_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(64), ForeignKey("users.user_id", ondelete="CASCADE"), nullable=False)
    device_id: Mapped[str | None] = mapped_column(String(64), ForeignKey("devices.device_id", ondelete="CASCADE"), nullable=True)
    # Main agents (definitions) have parent_agent_id NULL. Assigning a definition
    # to a camera creates a sub-agent whose parent_agent_id points back to it.
    parent_agent_id: Mapped[str | None] = mapped_column(
        String(64), ForeignKey("agents.agent_id", ondelete="CASCADE"), nullable=True
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    location: Mapped[str | None] = mapped_column(String(255))
    nl_rule: Mapped[str] = mapped_column(Text, nullable=False)
    compiled_prompt: Mapped[str | None] = mapped_column(Text)
    compiled_edge_config: Mapped[dict | None] = mapped_column(JSON)
    state: Mapped[str] = mapped_column(String(32), nullable=False, server_default="disarmed")
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="1")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
