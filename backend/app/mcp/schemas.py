"""Milestone 9B — MCP tool specs and result type.

``get_tool_specs`` returns OpenAI function-calling specs for the tools the
verification agent may call. ``ToolResult`` is the in-process return shape.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class ToolResult:
    """Outcome of one tool execution.

    ``image_b64`` carries a JPEG keyframe (e.g. from ``get_live_snapshot``) that
    the caller re-inlines as an image message for the multimodal model; it is
    never written to the audit log.
    """

    tool: str
    ok: bool
    data: dict = field(default_factory=dict)
    error: str | None = None
    image_b64: str | None = None

    def summary_for_model(self) -> dict:
        """Compact, image-free dict to feed back to the model as the tool result."""

        summary: dict = {"tool": self.tool, "ok": self.ok}
        if self.error:
            summary["error"] = self.error
        summary.update(self.data)
        if self.image_b64:
            summary["image"] = "attached as the next image message"
        return summary

    def audit_result(self) -> dict:
        """What we persist to ``tool_audit.result`` (no raw image bytes)."""

        return {"ok": self.ok, "error": self.error, **self.data}


def get_tool_specs() -> list[dict]:
    """OpenAI-style tool specs offered to the verification model."""

    return [
        {
            "type": "function",
            "function": {
                "name": "get_live_snapshot",
                "description": "Fetch a fresh camera frame to look at the current scene before deciding.",
                "parameters": {"type": "object", "properties": {}},
            },
        },
        {
            "type": "function",
            "function": {
                "name": "pan_camera",
                "description": "Pan the camera to a horizontal angle (0-180 degrees) for a better view.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "angle": {
                            "type": "integer",
                            "minimum": 0,
                            "maximum": 180,
                            "description": "Target pan angle in degrees.",
                        }
                    },
                    "required": ["angle"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "get_device_status",
                "description": "Get the camera's current health, position, and signal.",
                "parameters": {"type": "object", "properties": {}},
            },
        },
        {
            "type": "function",
            "function": {
                "name": "query_recent_events",
                "description": "List recent events from this camera for additional context.",
                "parameters": {"type": "object", "properties": {}},
            },
        },
        {
            "type": "function",
            "function": {
                "name": "get_event_clip",
                "description": "Get clip metadata / playback URL recorded for this event.",
                "parameters": {"type": "object", "properties": {}},
            },
        },
    ]
