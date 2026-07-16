"""Milestone 9B — MCP tool permissions and actuation guardrails.

Per the plan's safety rules: only read/low-risk tools and tightly limited camera
movement are auto-allowed; high-risk tools are denied. Pan is clamped to the safe
15-165 range and tilt to 60-140 (matching the firmware hard-stop guardrails), and
movement is rate-limited per event (max count + minimum interval).
"""

from __future__ import annotations

from app.core.config import settings


# Servo-safe travel ranges, kept in lockstep with the firmware SERVO_*_MIN/MAX_DEG
# and the backend DevicePan/TiltCommand schemas so the model can never drive a
# servo into its mechanical hard stops.
PAN_MIN_DEG, PAN_MAX_DEG = 15, 165
TILT_MIN_DEG, TILT_MAX_DEG = 60, 140


# Autonomy table for the per-event VERIFICATION agent. Tools not listed are denied.
AUTONOMY: dict[str, str] = {
    "get_live_snapshot": "allow",
    "pan_camera": "allow",
    "tilt_camera": "allow",
    "get_device_status": "allow",
    "query_recent_events": "allow",
    "get_event_clip": "allow",
    # High-risk tools are out of scope for Milestone 9 — denied for completeness
    # so an unexpected request is refused (and audited) rather than executed.
    "send_emergency_alert": "deny",
    "arm_agent": "deny",
    "disarm_agent": "deny",
}

# Autonomy table for the user-facing CHAT agent (the Erlang AI Agent view, connected
# through the MCP server). The user is present and every action is theirs to see, so
# agent management is allowed here; emergency escalation stays denied.
CHAT_AUTONOMY: dict[str, str] = {
    "list_devices": "allow",
    "get_device_status": "allow",
    "get_live_snapshot": "allow",
    "pan_camera": "allow",
    "tilt_camera": "allow",
    "query_events": "allow",
    "get_event_clip": "allow",
    "list_recordings": "allow",
    "list_agents": "allow",
    "create_agent": "allow",
    "assign_agent": "allow",
    "unassign_agent": "allow",
    "send_emergency_alert": "deny",
}


def is_allowed(tool_name: str, scope: str = "verify") -> bool:
    table = CHAT_AUTONOMY if scope == "chat" else AUTONOMY
    return table.get(tool_name) == "allow"


def _to_int(angle: object, default: int = 90) -> int:
    try:
        return int(angle)
    except (TypeError, ValueError):
        return default


def clamp_pan(angle: object) -> int:
    """Clamp an arbitrary angle value into the servo's safe pan range (15-165)."""

    return max(PAN_MIN_DEG, min(PAN_MAX_DEG, _to_int(angle)))


def clamp_tilt(angle: object) -> int:
    """Clamp an arbitrary angle value into the servo's safe tilt range (60-140)."""

    return max(TILT_MIN_DEG, min(TILT_MAX_DEG, _to_int(angle)))


class PanRateLimiter:
    """In-memory pan limiter: a max count and a minimum interval, keyed by a caller
    string.

    ``check_and_register`` is called with a monotonic ``now`` so the interval is
    testable with injected timestamps. Two modes by key:

    * Per-event verification keys by ``event_id`` with no window — a hard cap of
      ``max_pans`` for the (short-lived) event.
    * The user-facing chat keys by ``chat:{user_id}``, which lives for the whole
      process; it passes ``window`` so the cap is a *rolling* one (max pans per
      window) instead of a lifetime cap that would lock the user out forever.

    A ``window`` also bounds memory: timestamps older than it are pruned, so a
    long-lived key can't accumulate an unbounded list.
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

    def check_and_register(
        self, key: str, now: float, *, window: float | None = None
    ) -> tuple[bool, str | None]:
        times = self._timestamps.setdefault(key, [])
        if window is not None:
            # Rolling window: forget pans older than it so a long-lived key
            # (a chat session) is rate-limited, not capped for good.
            cutoff = now - window
            times = [t for t in times if t >= cutoff]
            self._timestamps[key] = times
        if len(times) >= self.max_pans:
            unit = f"per {int(window)}s" if window is not None else "per event"
            return False, f"pan limit reached ({self.max_pans} {unit})"
        if times and (now - times[-1]) < self.min_interval:
            return False, f"too soon since last pan (min {self.min_interval}s)"
        times.append(now)
        return True, None

    def reset(self, key: str | None = None) -> None:
        if key is None:
            self._timestamps.clear()
        else:
            self._timestamps.pop(key, None)


# Process-wide limiter shared across verification runs.
pan_rate_limiter = PanRateLimiter()
