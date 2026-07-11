"""Attach a USB-bridge test camera to your account for LOCAL testing.

The Flutter app only lists devices owned by the logged-in (Google) user, so a
device must belong to *your* user row for it to appear in the app. Flow:

    1. Start backend + frontend (scripts/start-dev.ps1) and LOG IN once with Google
       -- that creates your User row.
    2. Run this with your login email:
         cd erlang-ai-vision-fullstack
         $env:PYTHONPATH = 'backend'
         python scripts/seed_local_device.py --email you@example.com
    3. Refresh the app -> "Local Test Cam" appears. Run the bridge with the printed
       EDGE_TOKEN, open the camera's live view.

Idempotent and safe to delete; touches only the local SQLite demo DB. With no
--email (or an unknown one) it falls back to a standalone usr_local owner, which
works for the raw MJPEG URL but will NOT show in the app.
"""

from __future__ import annotations

import argparse
import asyncio
from datetime import UTC, datetime
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from app.core.config import settings  # noqa: E402
from app.core.security import create_signed_token, hash_edge_token  # noqa: E402
from app.db.base import Base  # noqa: E402  (imports all models so create_all sees them)
from app.db.session import engine  # noqa: E402
from app.models.device import Device  # noqa: E402
from app.models.user import User  # noqa: E402
from sqlalchemy import select  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402


DEVICE_ID = "dev_local"
EDGE_TOKEN = "se_edge_localtest"          # what the bridge sends as Bearer
STREAM_TOKEN_TTL_S = 24 * 3600
STREAM_PURPOSE = "live_stream"
FALLBACK_USER_ID = "usr_local"


async def main(email: str | None) -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    factory = async_sessionmaker(engine, expire_on_commit=False)
    async with factory() as session:
        now = datetime.now(UTC)

        user = None
        if email:
            user = (await session.execute(select(User).where(User.email == email))).scalar_one_or_none()
            if user is None:
                print(f"!! no user with email {email!r} -- log into the app once first, "
                      f"then rerun. Falling back to {FALLBACK_USER_ID} (won't show in the app).")

        if user is None:
            user = await session.get(User, FALLBACK_USER_ID)
            if user is None:
                user = User(
                    user_id=FALLBACK_USER_ID, google_sub="gsub_local", email="local@example.com",
                    email_verified=True, role="user", created_at=now, updated_at=now,
                )
                session.add(user)
                await session.commit()

        device = await session.get(Device, DEVICE_ID)
        if device is None:
            device = Device(
                device_id=DEVICE_ID, user_id=user.user_id,
                edge_token_hash=hash_edge_token(EDGE_TOKEN),
                name="Local Test Cam", health_status="unknown",
                current_pan=90, created_at=now, updated_at=now,
            )
            session.add(device)
        else:
            device.user_id = user.user_id  # re-attach to the chosen owner
            device.edge_token_hash = hash_edge_token(EDGE_TOKEN)
            device.updated_at = now
        await session.commit()
        owner_id = user.user_id

    stream_token = create_signed_token(
        {"device_id": DEVICE_ID, "user_id": owner_id}, STREAM_PURPOSE, STREAM_TOKEN_TTL_S
    )
    base = "http://localhost:8000"
    print(f"\n=== local test wiring (owner={owner_id}, DB={settings.database_url}) ===")
    print(f"DEVICE_ID  : {DEVICE_ID}")
    print(f"EDGE_TOKEN : {EDGE_TOKEN}")
    print("\nRun the bridge with:")
    print(f"  python edge_bridge.py --serial-port COMx \\")
    print(f"      --api-base-url {base} --edge-token {EDGE_TOKEN}")
    print("\nIn the app: refresh -> 'Local Test Cam' -> open its live view.")
    print("Or open the raw MJPEG directly (valid 24h):")
    print(f"  {base}/api/v1/devices/{DEVICE_ID}/stream?token={stream_token}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--email", default=None, help="your Google login email (attaches the camera to that account)")
    args = ap.parse_args()
    asyncio.run(main(args.email))
