"""Create (or refresh) a ready-to-use demo account for hackathon judges.

Login is Firebase-backed and the backend rejects any token whose email is not
verified (see app/services/auth_service.upsert_firebase_user). A normally
self-registered email/password account is *unverified*, so a judge would get
stuck on "please verify your email". This script sidesteps that by minting the
account through the Firebase Admin SDK with ``email_verified=True`` and a known
password, then seeding a demo dataset for that account: a spread of cameras,
one per use case, each with an armed agent + a sample event so the
dashboard is populated the moment they sign in. You stream a real demo video
into any camera later via the laptop edge (each camera has its own edge_token).

Only the judge account is touched — every seeded row is owned by that user, so
normal user accounts keep working exactly as before (they register their own
cameras through the app as usual).

The account is keyed to the *real* Firebase UID: the seeded ``users`` row uses
that UID as ``google_sub``, so the backend's first-login upsert finds and
updates this row (preserving the demo data) instead of creating an empty one.

Idempotent: safe to run repeatedly. All rows use fixed IDs and are merged.

Usage
-----
  cd SentinelEdge-Fullstack
  $env:PYTHONPATH = 'backend'

  # Local SQLite (data/sentineledge_demo.db is picked up from .env):
  python scripts/create_judge_account.py

  # Production RDS (point DATABASE_URL at RDS; an explicit env var always wins
  # over the .env value). Grab the RDS URL from the KMS secret, or run this
  # inside the deployed backend container where settings already resolve to RDS:
  $env:DATABASE_URL = 'postgresql+asyncpg://USER:PASSWORD@HOST:5432/sentineledge'
  python scripts/create_judge_account.py

  # Override the credentials handed to judges:
  python scripts/create_judge_account.py --email judge@sentineledge.ai --password "Judge2026!" --name "Hackathon Judge"

Firebase Admin credentials + the target database both come from the same config
loader the app uses (app.core.config -> KMS), so no extra wiring is needed.
"""

from __future__ import annotations

import argparse
import asyncio
import secrets
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from app.core.config import settings  # noqa: E402
from app.core.security import hash_edge_token  # noqa: E402
from app.db.base import Base  # noqa: E402  (imports all models so create_all sees them)
from app.db.session import engine  # noqa: E402
from app.models.agent import Agent  # noqa: E402
from app.models.alert import Alert  # noqa: E402
from app.models.clip import Clip  # noqa: E402  (used by --reset cleanup)
from app.models.device import Device  # noqa: E402
from app.models.event import Event  # noqa: E402
from app.models.recording import Recording  # noqa: E402  (used by --reset cleanup)
from app.models.tool_audit import ToolAudit  # noqa: E402
from app.models.user import User  # noqa: E402
from sqlalchemy import delete, select  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402


# --- Defaults handed to judges ------------------------------------------------
DEFAULT_EMAIL = "judge@sentineledge.ai"
DEFAULT_PASSWORD = "SentinelEdge2026!"
DEFAULT_NAME = "Hackathon Judge"
DEFAULT_API_BASE = "http://localhost:8000"

# Stable IDs so re-runs merge rather than duplicate.
USER_ID = "usr_judge_demo"

# Anchor the demo timeline to a fixed, recent point so it looks live but stays
# deterministic across runs.
BASE = datetime(2026, 7, 5, 21, 0, 0, tzinfo=timezone.utc)


def _t(hours: float) -> datetime:
    return BASE + timedelta(hours=hours)


# --- Camera catalog -----------------------------------------------------------
# THIS DATA IS ONLY EVER SEEDED FOR THE JUDGE DEMO ACCOUNT. Every row below is
# owned by USER_ID, so normal user accounts are completely unaffected — they keep
# registering their own real cameras through the app as usual. This catalog just
# gives judges a spread of ready-made cameras, one per use case, that you stream
# a demo video into later (via the laptop edge + the camera's edge_token).
#
# `classes` must be labels the edge detectors actually emit, or the pipeline
# won't fire on your video:
#   video (YOLO/COCO): person, car, truck, bus, motorcycle, bicycle, dog, cat,
#                      backpack, handbag, suitcase, ...
#   audio (YAMNet, WiFi/WS only): alarm, glass-break, scream, crying, gunshot
#
# Each entry seeds: one Device (armed, online) + one armed Agent + one recent
# sample event so the tile shows history before your own video runs. Playback
# media (clips/recordings) is deliberately not seeded — the live simulation
# generates real detections instead.
CAMERAS = [
    # --- House (home security) — two cameras ---------------------------------
    {
        "key": "house_frontdoor",
        "name": "Home — Front Door",
        "location": "House · Front Entrance",
        "use_case": "Home security: suspicious person at the front door",
        "agent_name": "Front Door Watch",
        "nl_rule": "Alert me if a suspicious person is loitering at the front door.",
        "prompt": "Verify whether a suspicious person (for example someone in a dark hoodie lingering or acting furtively) is at the front door.",
        "edge_config": {
            "classes": ["person"],
            "dwell_s": 3.0,
            "cooldown_s": 60.0,
            "min_confidence": 0.5,
        },
        "event_type": "person_detected",
        "severity": "high",
        "confidence": 0.93,
        "summary": "A suspicious person in a dark hoodie is at the front door.",
    },
    {
        "key": "house_backyard",
        "name": "Home — Backyard",
        "location": "House · Backyard",
        "use_case": "Yard monitoring: activity / people in the backyard",
        "agent_name": "Backyard Activity Watch",
        "nl_rule": "Let me know about any people or activity in the backyard.",
        "prompt": "Describe any person or activity in the backyard, such as someone doing yard work or mowing the lawn.",
        "edge_config": {
            "classes": ["person"],
            "dwell_s": 3.0,
            "cooldown_s": 30.0,
            "min_confidence": 0.5,
        },
        "event_type": "person_detected",
        "severity": "low",
        "confidence": 0.9,
        "summary": "An elderly man is mowing the lawn in the backyard.",
    },
    # --- Office --------------------------------------------------------------
    {
        "key": "office",
        "name": "Office",
        "location": "Office · Main Floor",
        "use_case": "Office monitoring: meetings and room occupancy",
        "agent_name": "Office Activity Watch",
        "nl_rule": "Notify me when people are meeting in the office.",
        "prompt": "Verify whether people are present and having a meeting or discussion in the office.",
        "edge_config": {
            "classes": ["person"],
            "dwell_s": 3.0,
            "cooldown_s": 60.0,
            "min_confidence": 0.5,
        },
        "event_type": "person_detected",
        "severity": "low",
        "confidence": 0.9,
        "summary": "A few people are having a meeting in the office.",
    },
    # --- Street --------------------------------------------------------------
    {
        "key": "street",
        "name": "Street",
        "location": "Street · Curbside",
        "use_case": "Storefront monitoring: deliveries and street activity",
        "agent_name": "Storefront Delivery Watch",
        "nl_rule": "Notify me when someone is moving goods or deliveries into the store.",
        "prompt": "Verify whether a person is moving stock, boxes, or deliveries into the store on the street.",
        "edge_config": {
            "classes": ["person", "truck", "car"],
            "dwell_s": 2.0,
            "cooldown_s": 45.0,
            "min_confidence": 0.5,
        },
        "event_type": "person_detected",
        "severity": "low",
        "confidence": 0.86,
        "summary": "A person is moving stock into the store.",
    },
    # --- Baby watching -------------------------------------------------------
    {
        "key": "baby",
        "name": "Baby Room",
        "location": "House · Nursery",
        "use_case": "Baby monitor: crying, or the baby climbing out of the crib",
        "agent_name": "Baby Monitor",
        "nl_rule": "Alert me if the baby is crying or climbs out of the crib.",
        "prompt": "Verify whether the baby is crying or out of the crib (person moving in the crib area).",
        "edge_config": {
            # 'crying' is a YAMNet audio class (WiFi/WS only); 'person' covers
            # the baby visually.
            "classes": ["person", "crying"],
            "dwell_s": 1.0,
            "cooldown_s": 30.0,
            "min_confidence": 0.4,
        },
        "event_type": "baby_crying",
        "severity": "high",
        "confidence": 0.88,
        "summary": "Baby is crying in the nursery.",
    },
    # --- Pets watching -------------------------------------------------------
    {
        "key": "pets",
        "name": "Pet Cam",
        "location": "House · Back Door",
        "use_case": "Pet monitoring: cat waiting / meowing at the door",
        "agent_name": "Pet Watch",
        "nl_rule": "Tell me when the cat is at the door wanting to be let in or fed.",
        "prompt": "Verify whether a cat is at the door, e.g. waiting, meowing, or looking to be fed.",
        "edge_config": {
            "classes": ["cat", "dog"],
            "dwell_s": 1.0,
            "cooldown_s": 30.0,
            "min_confidence": 0.4,
        },
        "event_type": "pet_detected",
        "severity": "low",
        "confidence": 0.82,
        "summary": "The cat is at the door, likely hungry.",
    },
]


def create_firebase_user(email: str, password: str, display_name: str) -> str:
    """Create or update a pre-verified Firebase email/password user. Returns UID."""
    # Reuse the app's own initializer so credential resolution (KMS temp file or
    # local service-account path) matches exactly what the backend does.
    from app.services.auth_service import _initialize_firebase_admin

    _initialize_firebase_admin()
    from firebase_admin import auth

    try:
        existing = auth.get_user_by_email(email)
        auth.update_user(
            existing.uid,
            password=password,
            email_verified=True,
            display_name=display_name,
            disabled=False,
        )
        print(f"[firebase] updated existing user {email} (uid={existing.uid})")
        return existing.uid
    except auth.UserNotFoundError:
        created = auth.create_user(
            email=email,
            password=password,
            email_verified=True,
            display_name=display_name,
        )
        print(f"[firebase] created user {email} (uid={created.uid})")
        return created.uid


async def seed_database(uid: str, email: str, display_name: str, reset: bool = False) -> None:
    # For a fresh local SQLite file, make sure the schema exists. On RDS the
    # tables are created by Alembic migrations; create_all is a no-op there.
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    factory = async_sessionmaker(engine, expire_on_commit=False)
    async with factory() as session:
        now = datetime.now(timezone.utc)

        # --- User -------------------------------------------------------------
        # Reuse any existing row for this Firebase UID or email so we don't trip
        # the unique constraints on google_sub / email.
        result = await session.execute(
            select(User).where((User.google_sub == uid) | (User.email == email))
        )
        user = result.scalars().first()
        if user is None:
            user = User(user_id=USER_ID, created_at=now)
            session.add(user)
        user.google_sub = uid
        user.email = email
        user.email_verified = True
        user.display_name = display_name
        user.role = "user"
        user.last_login_at = now
        user.updated_at = now
        await session.flush()
        owner_id = user.user_id

        # --- Cameras (one per use case), each with an armed agent + sample -----
        # history. All rows are owned by owner_id (the judge account only).
        # Edge tokens are generated randomly per run (never hard-coded in source)
        # and printed below for you to paste into the edge bridge.
        edge_tokens: dict[str, str] = {}
        for index, cam in enumerate(CAMERAS):
            key = cam["key"]
            edge_token = f"se_edge_judge_{key}_{secrets.token_urlsafe(18)}"
            edge_tokens[key] = edge_token
            dev_id = f"dev_judge_{key}"
            # Arming model: a device-independent definition + an armed sub-agent
            # bound to the camera (exactly what the app's "assign" flow creates).
            def_id = f"agt_def_{key}"
            agt_id = f"agt_judge_{key}"  # the armed sub-agent on this camera
            evt_id = f"evt_judge_{key}"
            alrt_id = f"alrt_judge_{key}"
            aud_id = f"aud_judge_{key}"
            # Stagger the sample event times so the Events feed looks natural.
            seen = _t(-1 - index * 0.5)
            classes = cam["edge_config"]["classes"]
            primary_class = classes[0] if classes else "object"

            await session.merge(
                Device(
                    device_id=dev_id,
                    user_id=owner_id,
                    edge_token_hash=hash_edge_token(edge_token),
                    name=cam["name"],
                    location=cam["location"],
                    # Shown "online" for a populated dashboard; the real health
                    # flips automatically once you start streaming a video into
                    # it (the edge sends heartbeats).
                    health_status="online",
                    rssi=-52.0 - index * 3,
                    fps=15.0,
                    current_pan=90,
                    current_tilt=90,
                    is_favorite=(index == 0),
                    presets=[
                        {"label": "Wide", "pan": 90, "tilt": 90},
                        {"label": "Zone", "pan": 70, "tilt": 100},
                    ],
                    last_seen=seen,
                    created_at=BASE,
                    updated_at=now,
                )
            )

            # Definition (reusable rule; device-independent, shown in Agents tab
            # and offered in the quick-arm sheet).
            await session.merge(
                Agent(
                    agent_id=def_id,
                    user_id=owner_id,
                    device_id=None,
                    parent_agent_id=None,
                    name=cam["agent_name"],
                    location=None,
                    nl_rule=cam["nl_rule"],
                    compiled_prompt=cam["prompt"],
                    compiled_edge_config=cam["edge_config"],
                    state="disarmed",
                    enabled=True,
                    created_at=BASE,
                    updated_at=now,
                )
            )
            # Flush so the self-referential FK (sub-agent -> definition) resolves.
            await session.flush()
            # Armed sub-agent on this camera (the "assignment"). This is what the
            # edge / demo simulator reads (device-bound + armed) and what the
            # arming UI counts as armed on the camera.
            await session.merge(
                Agent(
                    agent_id=agt_id,
                    user_id=owner_id,
                    device_id=dev_id,
                    parent_agent_id=def_id,
                    name=cam["agent_name"],
                    location=cam["location"],
                    nl_rule=cam["nl_rule"],
                    compiled_prompt=cam["prompt"],
                    compiled_edge_config=cam["edge_config"],
                    state="armed",
                    enabled=True,
                    created_at=BASE,
                    updated_at=now,
                )
            )

            # One recent, verified sample event so each camera tile shows history
            # before your own footage runs.
            await session.merge(
                Event(
                    event_id=evt_id,
                    user_id=owner_id,
                    agent_id=agt_id,
                    device_id=dev_id,
                    idempotency_key=f"{dev_id}-{evt_id}",
                    timestamp=seen,
                    event_type=cam["event_type"],
                    stage1_result={"detector": primary_class},
                    stage2_verdict={"matched_rule": True, "reason": cam["summary"]},
                    stage3_verdict={"verified": True, "recommended_action": "notify"},
                    severity=cam["severity"],
                    confidence=cam["confidence"],
                    summary=cam["summary"],
                    degraded=False,
                    status="verified",
                    created_at=seen,
                    updated_at=now,
                )
            )

            # Playback media (clips/recordings) is intentionally NOT seeded: the
            # backend simulation + real detections populate the live view, and
            # fake OSS-backed clips would only render broken playback entries.

            # Alerts + audit only for the two high-severity cameras, to keep the
            # feed realistic rather than uniform.
            if cam["severity"] == "high":
                await session.merge(
                    Alert(
                        alert_id=alrt_id,
                        event_id=evt_id,
                        user_id=owner_id,
                        channel="push",
                        sent_at=seen + timedelta(seconds=8),
                        status="sent",
                        dedupe_key=f"{evt_id}-push-{cam['severity']}",
                        created_at=seen + timedelta(seconds=8),
                    )
                )
                await session.merge(
                    ToolAudit(
                        audit_id=aud_id,
                        event_id=evt_id,
                        user_id=owner_id,
                        device_id=dev_id,
                        tool_name="snapshot_camera",
                        arguments={},
                        result={"ok": True},
                        called_by="qwen_agent",
                        timestamp=seen + timedelta(seconds=2),
                    )
                )

        # --- Prune stale demo cameras not in the current catalog --------------
        # Only when --reset: removes leftover dev_judge_* devices from an older
        # catalog (e.g. after renaming cameras). FK ON DELETE CASCADE takes the
        # agents/events/clips/recordings/audit/alerts with them.
        if reset:
            catalog_ids = [f"dev_judge_{cam['key']}" for cam in CAMERAS]
            stale = await session.execute(
                select(Device.device_id).where(
                    Device.user_id == owner_id,
                    Device.device_id.like("dev_judge_%"),
                    Device.device_id.notin_(catalog_ids),
                )
            )
            stale_ids = [row[0] for row in stale]
            if stale_ids:
                await session.execute(delete(Device).where(Device.device_id.in_(stale_ids)))
                print(f"[reset] pruned {len(stale_ids)} stale demo camera(s): {', '.join(stale_ids)}")

            # Prune any judge-owned agent that isn't part of the canonical set:
            # stale definitions (device-independent, missed by the device prune)
            # and stray sub-agents left over from earlier arming/test runs. Events
            # referencing a removed agent cascade away with it.
            canonical_agent_ids = [f"agt_def_{cam['key']}" for cam in CAMERAS] + [
                f"agt_judge_{cam['key']}" for cam in CAMERAS
            ]
            agents_del = await session.execute(
                delete(Agent).where(
                    Agent.user_id == owner_id,
                    Agent.agent_id.notin_(canonical_agent_ids),
                )
            )
            if agents_del.rowcount:
                print(f"[reset] pruned {agents_del.rowcount} stale/stray agent(s)")

            # Remove previously-seeded playback media (clips/recordings). We no
            # longer seed these; the live simulation generates real detections.
            clips_del = await session.execute(
                delete(Clip).where(Clip.user_id == owner_id, Clip.clip_id.like("clip_judge_%"))
            )
            recs_del = await session.execute(
                delete(Recording).where(Recording.user_id == owner_id, Recording.recording_id.like("rec_judge_%"))
            )
            removed = (clips_del.rowcount or 0) + (recs_del.rowcount or 0)
            if removed:
                print(f"[reset] removed {clips_del.rowcount or 0} seeded clip(s) + {recs_del.rowcount or 0} recording(s)")

        await session.commit()
        return owner_id, edge_tokens


async def _run(
    email: str,
    password: str,
    name: str,
    skip_firebase: bool,
    uid_override: str | None,
    api_base: str,
    reset: bool,
) -> None:
    if skip_firebase:
        uid = uid_override or f"judge-demo-uid-{email}"
        print(f"[firebase] SKIPPED — seeding DB only with uid={uid!r}")
    else:
        uid = create_firebase_user(email, password, name)

    owner_id, edge_tokens = await seed_database(uid, email, name, reset=reset)

    print("\n=== judge demo account ready ===")
    print(f"  database    : {settings.database_url}")
    print(f"  user_id     : {owner_id}")
    print(f"  firebase uid: {uid}")
    print("\n  Judges sign in on the app's 'Sign in with email' form:")
    print(f"    email    : {email}")
    print(f"    password : {password}")

    print(f"\n  Seeded {len(CAMERAS)} demo cameras (each with an armed agent + sample event):")
    for cam in CAMERAS:
        print(f"    • {cam['name']} [{cam['location']}]")
        print(f"        use case  : {cam['use_case']}")
        print(f"        device_id : dev_judge_{cam['key']}")
        print(f"        edge_token: {edge_tokens[cam['key']]}")

    print("\n  --- Place YOUR video into a camera later (run in SentinelEdge_LaptopEdge/src) ---")
    print("  Two terminals per camera — the bridge forwards frames to the cloud so the app's")
    print("  live view shows your footage, and the pipeline runs its agent on it:")
    example = CAMERAS[0]
    print(f"\n    # Terminal A — bridge for '{example['name']}':")
    print(f"    python transport/edge_bridge.py --edge-token {edge_tokens[example['key']]} \\")
    print(f"        --api-base-url {api_base} --log-level INFO")
    print("    # Terminal B — feed your video in as the device:")
    print("    python transport/simulate_device.py --video <YOUR_VIDEO.mp4> --loop-video --tone")
    print("\n  Swap --edge-token for any camera above; pick a video that matches its use case")
    print("  (a person clip for Home/Office, a car clip for Street, a pet clip for Pet Cam,")
    print("  etc.). The GUI console (python transport/edge_console.py) does the same in one")
    print("  window: set Source=Simulator Video, paste the edge token, Start.")
    print("\n  For BACKEND simulation instead of the edge: drop clips in data/demo_videos/")
    print("  named by camera key, run scripts/extract_demo_frames.py --videos-dir, set")
    print("  DEMO_SIMULATION_ENABLED=true (+ QWEN_API_KEY for AI events), open a camera.")

    if skip_firebase:
        print("\n  NOTE: Firebase user was NOT created (--skip-firebase). Sign-in will only")
        print("  work once a Firebase user with a matching UID exists.")


def main() -> None:
    ap = argparse.ArgumentParser(description="Create a pre-verified demo login + seed demo data for judges.")
    ap.add_argument("--email", default=DEFAULT_EMAIL, help=f"login email (default: {DEFAULT_EMAIL})")
    ap.add_argument("--password", default=DEFAULT_PASSWORD, help="login password")
    ap.add_argument("--name", default=DEFAULT_NAME, help="display name")
    ap.add_argument(
        "--skip-firebase",
        action="store_true",
        help="seed the database only; do not touch Firebase (use --uid to pin the google_sub).",
    )
    ap.add_argument("--uid", default=None, help="Firebase UID to key the DB user to (with --skip-firebase).")
    ap.add_argument(
        "--api-base-url",
        default=DEFAULT_API_BASE,
        help=f"backend URL printed in the 'stream your video' commands (default: {DEFAULT_API_BASE}).",
    )
    ap.add_argument(
        "--reset",
        action="store_true",
        help="delete stale dev_judge_* cameras not in the current catalog (cascades their data).",
    )
    args = ap.parse_args()

    asyncio.run(
        _run(
            args.email,
            args.password,
            args.name,
            args.skip_firebase,
            args.uid,
            args.api_base_url,
            args.reset,
        )
    )


if __name__ == "__main__":
    main()
