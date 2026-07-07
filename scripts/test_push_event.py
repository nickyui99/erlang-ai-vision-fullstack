"""Fire a test push notification to the demo (judge) account via a real event.

This mints a fresh event for the judge user and runs the backend's own alert
path (:func:`app.services.alert_service.maybe_alert_for_event`) — the exact code
that runs for real edge/AI/simulated events — so it exercises token lookup and
the FCM send end to end. It then prints what happened (sent / no recipients /
failed) and how many device tokens the account has registered.

Prerequisites for an actual notification to arrive:
  * Sign in on the mobile app with the judge account at least once and grant the
    notification permission — that registers an FCM token (check with
    --list-tokens; "0 tokens" means no device has registered yet).
  * Firebase Admin credentials must be configured on this machine/container
    (same config the app uses) and FCM enabled for the project.
  * Severity must meet ALERT_MIN_SEVERITY (default "high"); this script defaults
    to "high" so it always qualifies unless you lower --severity.

Usage
-----
  cd SentinelEdge-Fullstack
  $env:PYTHONPATH = 'backend'

  # Local SQLite (data/sentineledge_demo.db from .env):
  python scripts/test_push_event.py

  # Just show how many tokens the account has (no event created):
  python scripts/test_push_event.py --list-tokens

  # Target a specific camera + custom message, fire 3 alerts:
  python scripts/test_push_event.py --device house_frontdoor \
      --summary "Test: person at the front door" --repeat 3

  # Production RDS (an explicit DATABASE_URL always wins over .env):
  $env:DATABASE_URL = 'postgresql+asyncpg://USER:PASSWORD@HOST:5432/sentineledge'
  python scripts/test_push_event.py
"""

from __future__ import annotations

import argparse
import asyncio
from datetime import UTC, datetime
from pathlib import Path
import sys
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from app.core.config import settings  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.models.agent import Agent  # noqa: E402
from app.models.device import Device  # noqa: E402
from app.models.event import Event  # noqa: E402
from app.models.push_token import PushToken  # noqa: E402
from app.models.user import User  # noqa: E402
from app.services import alert_service  # noqa: E402
from sqlalchemy import select  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402


DEFAULT_EMAIL = "judge@sentineledge.ai"


async def _resolve_user(session, email: str) -> User:
    user = (
        await session.execute(select(User).where(User.email == email))
    ).scalars().first()
    if user is None:
        raise SystemExit(
            f"No user found for {email!r}. Run scripts/create_judge_account.py "
            f"first, or pass --email."
        )
    return user


async def _resolve_device(session, user_id: str, wanted: str | None) -> Device:
    stmt = select(Device).where(Device.user_id == user_id)
    if wanted:
        # Accept a bare catalog key ("house_frontdoor") or a full device id.
        candidates = {wanted, f"dev_judge_{wanted}"}
        stmt = stmt.where(Device.device_id.in_(candidates))
    devices = list((await session.execute(stmt)).scalars())
    if not devices:
        raise SystemExit(
            f"No devices for this account"
            + (f" matching {wanted!r}." if wanted else ".")
        )
    # Prefer the high-severity front-door demo camera when unspecified.
    devices.sort(key=lambda d: d.device_id != "dev_judge_house_frontdoor")
    return devices[0]


async def _resolve_agent(session, user_id: str, device_id: str) -> Agent:
    # Prefer an armed sub-agent bound to this device; fall back to any agent the
    # user owns (agent_id is a required FK on Event).
    bound = (
        await session.execute(
            select(Agent).where(
                Agent.user_id == user_id, Agent.device_id == device_id
            )
        )
    ).scalars().first()
    if bound is not None:
        return bound
    any_agent = (
        await session.execute(select(Agent).where(Agent.user_id == user_id))
    ).scalars().first()
    if any_agent is None:
        raise SystemExit("No agents for this account; cannot attach an event.")
    return any_agent


async def _run(
    email: str,
    device_arg: str | None,
    severity: str,
    summary: str | None,
    repeat: int,
    list_tokens_only: bool,
    full_tokens: bool,
) -> None:
    factory = async_sessionmaker(engine, expire_on_commit=False)
    async with factory() as session:
        user = await _resolve_user(session, email)

        tokens = list(
            (
                await session.execute(
                    select(PushToken).where(PushToken.user_id == user.user_id)
                )
            ).scalars()
        )
        print(f"database        : {settings.database_url}")
        print(f"account         : {user.email} (user_id={user.user_id})")
        print(f"alerts_enabled  : {settings.alerts_enabled}")
        print(f"min severity    : {settings.alert_min_severity}")
        print(f"registered tokens: {len(tokens)}")
        show_full = full_tokens or list_tokens_only
        for t in tokens:
            shown = t.token if show_full else f"{t.token[:24]}..."
            print(f"   - {t.platform:<7} (last_used={t.last_used_at})")
            print(f"     {shown}")

        if list_tokens_only:
            if not tokens:
                print(
                    "\n  No device tokens. Sign in on the mobile app with this "
                    "account and allow notifications, then re-run."
                )
            return

        if not tokens:
            print(
                "\n  WARNING: 0 tokens registered — the alert will be created but "
                "no push can be delivered. Sign in on mobile (allow notifications) "
                "first."
            )

        device = await _resolve_device(session, user.user_id, device_arg)
        agent = await _resolve_agent(session, user.user_id, device.device_id)
        print(f"\ncamera          : {device.name} ({device.device_id})")
        print(f"agent           : {agent.name} ({agent.agent_id})")

        for i in range(1, repeat + 1):
            now = datetime.now(UTC)
            event_id = f"evt_test_{uuid4().hex[:12]}"
            text = summary or f"Test alert #{i} from {device.name}"
            event = Event(
                event_id=event_id,
                user_id=user.user_id,
                agent_id=agent.agent_id,
                device_id=device.device_id,
                idempotency_key=event_id,
                timestamp=now,
                event_type="test_push",
                stage1_result={"detector": "test"},
                stage2_verdict={"matched_rule": True, "reason": text},
                stage3_verdict={"verified": True, "recommended_action": "notify"},
                severity=severity,
                confidence=0.99,
                summary=text,
                degraded=False,
                status="verified",
                created_at=now,
                updated_at=now,
            )
            session.add(event)
            await session.commit()

            alert = await alert_service.maybe_alert_for_event(session, event)
            if alert is None:
                print(
                    f"[{i}/{repeat}] event {event_id}: no alert "
                    f"(severity {severity!r} below threshold "
                    f"{settings.alert_min_severity!r}, or alerts disabled)."
                )
            else:
                print(
                    f"[{i}/{repeat}] event {event_id} -> alert {alert.alert_id}: "
                    f"status={alert.status}"
                    + (f" sent_at={alert.sent_at}" if alert.sent_at else "")
                )

    print("\nDone. Interpreting the status:")
    print("  sent          -> FCM accepted the message; check the device.")
    print("  no_recipients -> account has no registered token (sign in on mobile).")
    print("  failed        -> FCM rejected all tokens (bad token, or Admin creds/")
    print("                   FCM not configured on the backend).")


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Fire a test push notification to the judge account via a real event."
    )
    ap.add_argument("--email", default=DEFAULT_EMAIL, help=f"account email (default: {DEFAULT_EMAIL})")
    ap.add_argument(
        "--device",
        default=None,
        help="camera to attach the event to: a catalog key (e.g. 'house_frontdoor') "
        "or a full device id. Defaults to the front-door demo camera.",
    )
    ap.add_argument(
        "--severity",
        default="high",
        choices=["low", "medium", "high", "critical"],
        help="event severity (default: high — meets the default alert threshold).",
    )
    ap.add_argument("--summary", default=None, help="notification body text.")
    ap.add_argument("--repeat", type=int, default=1, help="how many alerts to fire (default: 1).")
    ap.add_argument(
        "--list-tokens",
        action="store_true",
        help="only show the account's registered push tokens; do not create an event.",
    )
    ap.add_argument(
        "--full-tokens",
        action="store_true",
        help="print full (untruncated) token values (implied by --list-tokens).",
    )
    args = ap.parse_args()

    asyncio.run(
        _run(
            args.email,
            args.device,
            args.severity,
            args.summary,
            max(1, args.repeat),
            args.list_tokens,
            args.full_tokens,
        )
    )


if __name__ == "__main__":
    main()
