"""Seed local playback clips for the camera Playback & Download panel.

This script intentionally uses sqlite3 directly instead of importing backend
settings, so local seeding does not trigger Alibaba KMS secret loading.

Examples:
    python scripts/seed_playback_clips.py --email you@example.com
    python scripts/seed_playback_clips.py --device-id dev_local --count 6
"""

from __future__ import annotations

import argparse
from datetime import UTC, datetime, timedelta
import json
from pathlib import Path
import sqlite3

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DB = ROOT / "data" / "erlang_demo.db"


def utc_text(value: datetime) -> str:
    return value.astimezone(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def safe_id(value: str) -> str:
    return "".join(ch if ch.isalnum() else "_" for ch in value)[:28]


def pick_user(conn: sqlite3.Connection, email: str | None) -> sqlite3.Row:
    if email:
        user = conn.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()
        if user is None:
            raise SystemExit(f"No user found for {email!r}. Log into the app once, then rerun.")
        return user

    user = conn.execute(
        """
        SELECT * FROM users
        ORDER BY COALESCE(last_login_at, created_at) DESC
        LIMIT 1
        """
    ).fetchone()
    if user is None:
        now = utc_text(datetime.now(UTC))
        conn.execute(
            """
            INSERT INTO users (
                user_id, google_sub, email, email_verified, display_name, role,
                created_at, updated_at, last_login_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                "usr_playback_demo",
                "gsub_playback_demo",
                "playback-demo@erlang.local",
                1,
                "Playback Demo",
                "user",
                now,
                now,
                now,
            ),
        )
        user = conn.execute("SELECT * FROM users WHERE user_id = ?", ("usr_playback_demo",)).fetchone()
    return user


def pick_or_create_device(conn: sqlite3.Connection, user_id: str, device_id: str | None) -> sqlite3.Row:
    if device_id:
        device = conn.execute(
            "SELECT * FROM devices WHERE device_id = ? AND user_id = ?",
            (device_id, user_id),
        ).fetchone()
        if device is None:
            raise SystemExit(f"No device {device_id!r} found for selected user {user_id!r}.")
        return device

    device = conn.execute(
        """
        SELECT * FROM devices
        WHERE user_id = ?
        ORDER BY COALESCE(last_seen, updated_at, created_at) DESC
        LIMIT 1
        """,
        (user_id,),
    ).fetchone()
    if device is None:
        now = utc_text(datetime.now(UTC))
        conn.execute(
            """
            INSERT INTO devices (
                device_id, user_id, edge_token_hash, name, location,
                health_status, rssi, fps, current_pan, current_tilt,
                last_seen, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                "dev_playback_demo",
                user_id,
                "local-playback-demo-token-hash",
                "Playback Demo Camera",
                "Demo Area",
                "online",
                -52.0,
                15.0,
                90,
                90,
                now,
                now,
                now,
            ),
        )
        device = conn.execute("SELECT * FROM devices WHERE device_id = ?", ("dev_playback_demo",)).fetchone()
    return device


def ensure_agent(conn: sqlite3.Connection, user_id: str, device_id: str) -> str:
    suffix = safe_id(device_id)
    agent_id = f"agt_playback_{suffix}"
    now = utc_text(datetime.now(UTC))
    conn.execute(
        """
        INSERT INTO agents (
            agent_id, user_id, device_id, parent_agent_id, name, location,
            nl_rule, compiled_prompt, compiled_edge_config, state, enabled,
            created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(agent_id) DO UPDATE SET
            user_id = excluded.user_id,
            device_id = excluded.device_id,
            updated_at = excluded.updated_at
        """,
        (
            agent_id,
            user_id,
            device_id,
            None,
            "Playback Demo Detector",
            "Camera",
            "Create playback demo clips for camera review.",
            "Playback demo detector.",
            json.dumps({"demo": True, "detectors": ["person", "motion"]}),
            "armed",
            1,
            now,
            now,
        ),
    )
    return agent_id


def seed_clips(conn: sqlite3.Connection, *, user_id: str, device_id: str, agent_id: str, count: int) -> list[str]:
    now = datetime.now(UTC).replace(microsecond=0)
    event_types = ["person_detected", "motion_detected", "vehicle_detected", "unknown_object"]
    severities = ["high", "medium", "low", "medium"]
    summaries = [
        "Person detected near camera.",
        "Motion detected in monitored area.",
        "Vehicle movement detected.",
        "Unknown object detected near camera.",
    ]
    clip_ids: list[str] = []

    for index in range(count):
        timestamp = now - timedelta(minutes=3 * index + 1)
        ts_key = timestamp.strftime("%Y%m%dT%H%M%SZ")
        event_id = f"evt_playback_{safe_id(device_id)}_{index + 1:02d}"
        clip_id = f"clip_playback_{safe_id(device_id)}_{index + 1:02d}"
        event_type = event_types[index % len(event_types)]
        severity = severities[index % len(severities)]
        summary = summaries[index % len(summaries)]
        duration = 14 + (index % 4) * 5
        uploaded_at = timestamp + timedelta(seconds=35)
        expires_at = uploaded_at + timedelta(days=7)

        conn.execute(
            """
            INSERT INTO events (
                event_id, user_id, agent_id, device_id, idempotency_key,
                timestamp, event_type, stage1_result, stage2_verdict,
                stage3_verdict, severity, confidence, summary, degraded,
                status, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(event_id) DO UPDATE SET
                timestamp = excluded.timestamp,
                event_type = excluded.event_type,
                severity = excluded.severity,
                confidence = excluded.confidence,
                summary = excluded.summary,
                status = excluded.status,
                updated_at = excluded.updated_at
            """,
            (
                event_id,
                user_id,
                agent_id,
                device_id,
                f"{device_id}-{ts_key}-{event_type}",
                utc_text(timestamp),
                event_type,
                json.dumps({"demo": True, "detector": event_type}),
                json.dumps({"matched_rule": True}),
                json.dumps({"verified": True, "source": "seed_playback_clips"}),
                severity,
                0.86 - (index % 3) * 0.04,
                summary,
                0,
                "verified",
                utc_text(timestamp),
                utc_text(now),
            ),
        )

        conn.execute(
            """
            INSERT INTO clips (
                clip_id, event_id, user_id, device_id, idempotency_key,
                storage_type, storage_path, oss_object_key, clip_type,
                duration_seconds, file_size_bytes, mime_type, checksum_sha256,
                status, upload_id, upload_started_at, upload_completed_at,
                upload_expires_at, upload_error, created_at, updated_at,
                deleted_at, expires_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(clip_id) DO UPDATE SET
                event_id = excluded.event_id,
                user_id = excluded.user_id,
                device_id = excluded.device_id,
                oss_object_key = excluded.oss_object_key,
                duration_seconds = excluded.duration_seconds,
                file_size_bytes = excluded.file_size_bytes,
                status = excluded.status,
                upload_completed_at = excluded.upload_completed_at,
                updated_at = excluded.updated_at,
                deleted_at = NULL,
                expires_at = excluded.expires_at
            """,
            (
                clip_id,
                event_id,
                user_id,
                device_id,
                f"{device_id}-{event_id}-playback-clip",
                "oss",
                None,
                f"events/{user_id}/{device_id}/{event_id}/clip_{clip_id}.mp4",
                "event",
                duration,
                2_400_000 + index * 420_000,
                "video/mp4",
                None,
                "available",
                f"upload_{clip_id}",
                utc_text(timestamp + timedelta(seconds=5)),
                utc_text(uploaded_at),
                utc_text(uploaded_at + timedelta(minutes=15)),
                None,
                utc_text(timestamp),
                utc_text(now),
                None,
                utc_text(expires_at),
            ),
        )
        clip_ids.append(clip_id)

    return clip_ids



def seed_recordings(
    conn: sqlite3.Connection,
    *,
    user_id: str,
    device_id: str,
    count: int,
    storage_type: str,
) -> list[str]:
    now = datetime.now(UTC).replace(microsecond=0)
    current_block_start = now.replace(minute=(now.minute // 30) * 30, second=0, microsecond=0)
    recording_ids: list[str] = []
    use_oss = storage_type == "oss"

    for index in range(max(1, min(4, count))):
        start = current_block_start - timedelta(minutes=30 * index)
        end = start + timedelta(minutes=30)
        recording_id = f"rec_playback_{safe_id(device_id)}_{start.strftime('%Y%m%dT%H%M')}"
        oss_object_key = (
            f"recordings/{user_id}/{device_id}/{start.strftime('%Y%m%dT%H%M%SZ')}_{recording_id}.mp4"
            if use_oss
            else None
        )
        conn.execute(
            """
            INSERT INTO recordings (
                recording_id, user_id, device_id, start_time, end_time,
                storage_type, storage_path, oss_object_key, duration_seconds,
                file_size_bytes, mime_type, checksum_sha256, status,
                upload_id, upload_started_at, upload_completed_at,
                upload_expires_at, upload_error, retention_until,
                created_at, updated_at, deleted_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(recording_id) DO UPDATE SET
                start_time = excluded.start_time,
                end_time = excluded.end_time,
                storage_type = excluded.storage_type,
                storage_path = excluded.storage_path,
                oss_object_key = excluded.oss_object_key,
                duration_seconds = excluded.duration_seconds,
                file_size_bytes = excluded.file_size_bytes,
                status = excluded.status,
                retention_until = excluded.retention_until,
                updated_at = excluded.updated_at,
                deleted_at = NULL
            """,
            (
                recording_id,
                user_id,
                device_id,
                utc_text(start),
                utc_text(end),
                "oss" if use_oss else "local_edge",
                None if use_oss else f"recordings/{device_id}/{start.strftime('%Y%m%dT%H%M')}.mp4",
                oss_object_key,
                1800,
                78_000_000 + index * 1_250_000,
                "video/mp4",
                None,
                "available" if use_oss else "local_only",
                f"upload_{recording_id}" if use_oss else None,
                utc_text(end - timedelta(minutes=2)) if use_oss else None,
                utc_text(end),
                None,
                None,
                utc_text(end + timedelta(hours=72)),
                utc_text(start),
                utc_text(now),
                None,
            ),
        )
        recording_ids.append(recording_id)

    return recording_ids

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=str(DEFAULT_DB), help="SQLite DB path")
    parser.add_argument("--email", default=None, help="App user email to seed clips for")
    parser.add_argument("--device-id", default=None, help="Existing device ID owned by the selected user")
    parser.add_argument("--count", type=int, default=6, help="Number of event clips to seed")
    parser.add_argument("--recording-storage", choices=["local_edge", "oss"], default="oss", help="Storage mode for seeded 30-minute recordings")
    args = parser.parse_args()

    db_path = Path(args.db)
    if not db_path.exists():
        raise SystemExit(f"Database not found: {db_path}")

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        user = pick_user(conn, args.email)
        device = pick_or_create_device(conn, user["user_id"], args.device_id)
        agent_id = ensure_agent(conn, user["user_id"], device["device_id"])
        clip_ids = seed_clips(
            conn,
            user_id=user["user_id"],
            device_id=device["device_id"],
            agent_id=agent_id,
            count=max(1, args.count),
        )
        recording_ids = seed_recordings(
            conn,
            user_id=user["user_id"],
            device_id=device["device_id"],
            count=max(1, args.count // 2),
            storage_type=args.recording_storage,
        )
        conn.commit()
    finally:
        conn.close()

    print("Seeded playback clips")
    print(f"  DB       : {db_path}")
    print(f"  user     : {user['email']} ({user['user_id']})")
    print(f"  device   : {device['name']} ({device['device_id']})")
    print(f"  clips    : {', '.join(clip_ids)}")
    print(f"  recordings: {', '.join(recording_ids)}")


if __name__ == "__main__":
    main()
