"""Alert orchestration for Milestone 8 (Firebase Cloud Messaging).

Decides whether an incoming event warrants a push alert, deduplicates, sends
through FCM, stores the result, and publishes the alert status over SSE.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.alert import Alert
from app.models.event import Event
from app.models.push_token import PushToken
from app.services import notification_service
from app.services.realtime_bus import realtime_bus


# Ordered low -> high; an event alerts when its rank >= the configured minimum.
_SEVERITY_ORDER = ["low", "medium", "high", "critical"]
_CHANNEL = "fcm"


def _severity_rank(severity: str | None) -> int:
    try:
        return _SEVERITY_ORDER.index((severity or "").lower())
    except ValueError:
        return -1


def _meets_threshold(severity: str | None) -> bool:
    minimum = _severity_rank(settings.alert_min_severity)
    if minimum < 0:
        minimum = _SEVERITY_ORDER.index("high")
    return _severity_rank(severity) >= minimum


async def maybe_alert_for_event(session: AsyncSession, event: Event) -> Alert | None:
    """Create and dispatch a push alert for ``event`` if it qualifies.

    Returns the persisted :class:`Alert`, or ``None`` when alerting is disabled,
    the severity is below threshold, or the alert was already sent (dedup).
    Safe to call inline: never raises on delivery failure.
    """

    if not settings.alerts_enabled or not _meets_threshold(event.severity):
        return None

    dedupe_key = f"{event.event_id}:{_CHANNEL}"
    now = datetime.now(UTC)
    alert = Alert(
        alert_id=f"alt_{uuid4().hex}",
        event_id=event.event_id,
        user_id=event.user_id,
        channel=_CHANNEL,
        status="pending",
        dedupe_key=dedupe_key,
        created_at=now,
    )
    session.add(alert)
    try:
        await session.commit()
    except IntegrityError:
        # A pending/sent alert already exists for this event+channel: dedup hit.
        await session.rollback()
        return None
    await session.refresh(alert)

    # Gather the user's registered FCM tokens.
    result = await session.execute(
        select(PushToken).where(PushToken.user_id == event.user_id)
    )
    tokens = list(result.scalars())

    if not tokens:
        alert.status = "no_recipients"
        await session.commit()
        await session.refresh(alert)
        await _publish(alert)
        return alert

    title = f"Erlang AI Vision · {(event.severity or 'alert').title()} alert"
    body = event.summary or f"{event.event_type} detected"
    push = notification_service.send_push(
        tokens=[t.token for t in tokens],
        title=title,
        body=body,
        data={
            "event_id": event.event_id,
            "device_id": event.device_id,
            "agent_id": event.agent_id,
            "severity": event.severity or "",
            "type": "event.alert",
        },
    )

    # Prune tokens FCM rejected as permanently invalid.
    if push.invalid_tokens:
        for token in tokens:
            if token.token in push.invalid_tokens:
                await session.delete(token)

    if push.delivered:
        alert.status = "sent"
        alert.sent_at = now
    else:
        alert.status = "failed"
    await session.commit()
    await session.refresh(alert)
    await _publish(alert)
    return alert


async def _publish(alert: Alert) -> None:
    await realtime_bus.publish(
        alert.user_id,
        "alert.created",
        {
            "alert_id": alert.alert_id,
            "event_id": alert.event_id,
            "channel": alert.channel,
            "status": alert.status,
            "sent_at": alert.sent_at,
        },
    )
