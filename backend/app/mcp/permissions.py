"""Milestone 9B — MCP tool permissions and actuation guardrails.

Per the plan's safety rules: only read/low-risk tools and a tightly limited pan
are auto-allowed; high-risk tools are denied. Pan is clamped to 0-180 and
rate-limited per event (max count + minimum interval).
"""

from __future__ import annotations

from app.core.config import settings


# Autonomy table. Tools not listed are treated as denied.
AUTONOMY: dict[str, str] = {
    "get_live_snapshot": "allow",
    "pan_camera": "allow",
    "get_device_status": "allow",
    "query_recent_events": "allow",
    "get_event_clip": "allow",
    # High-risk tools are out of scope for Milestone 9 — denied for completeness
    # so an unexpected request is refused (and audited) rather than executed.
    "send_emergency_alert": "deny",
    "arm_agent": "deny",
    "disarm_agent": "deny",
}


def is_allowed(tool_name: str) -> bool:
    return AUTONOMY.get(tool_name) == "allow"


def clamp_angle(angle: object) -> int:
    """Clamp an arbitrary angle value into the servo's safe 0-180 range."""

    try:
        value = int(angle)
    except (TypeError, ValueError):
        value = 90
    return max(0, min(180, value))


class PanRateLimiter:
    """In-memory per-event pan limiter: max pans and a minimum interval.

    ``check_and_register`` is called with a monotonic ``now`` so the interval is
    testable with injected timestamps. State is keyed by ``event_id``.
    """

    def __init__(self, max_pans: int | None = None, min_interval: float | None = None) -> None:
        self._max_pans = max_pans
        self._min_interval = min_interval
        self._timestamps: dict[str, list[float]] = {}

    @property
    def max_pans(self) -> int:
        return self._max_pans if self._max_pans is not None else settings.mcp_max_pans_per_event

    @property
    def min_interval(self) -> float:
        return self._min_interval if self._min_interval is not None else settings.mcp_min_seconds_between_pans

    def check_and_register(self, event_id: str, now: float) -> tuple[bool, str | None]:
        times = self._timestamps.setdefault(event_id, [])
        if len(times) >= self.max_pans:
            return False, f"pan limit reached ({self.max_pans} per event)"
        if times and (now - times[-1]) < self.min_interval:
            return False, f"too soon since last pan (min {self.min_interval}s)"
        times.append(now)
        return True, None

    def reset(self, event_id: str | None = None) -> None:
        if event_id is None:
            self._timestamps.clear()
        else:
            self._timestamps.pop(event_id, None)


# Process-wide limiter shared across verification runs.
pan_rate_limiter = PanRateLimiter()
