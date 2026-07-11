from __future__ import annotations

import json
import shutil
import sqlite3
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
DATA = ROOT / "data"
DB_PATH = DATA / "erlang_demo.db"
BUILD_DB_PATH = Path("C:/tmp/erlang_demo.db")
SCHEMA_PATH = SCRIPTS / "demo_sqlite_schema.sql"
sys.path.insert(0, str(ROOT / "backend"))
from app.core.security import hash_edge_token  # noqa: E402

DEMO_EDGE_TOKEN = "se_edge_demo_frontdoor"


def main() -> None:
    DATA.mkdir(parents=True, exist_ok=True)

    if DB_PATH.exists():
        DB_PATH.unlink()
    if BUILD_DB_PATH.exists():
        BUILD_DB_PATH.unlink()

    BUILD_DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(BUILD_DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = DELETE")

    with SCHEMA_PATH.open("r", encoding="utf-8") as schema_file:
        conn.executescript(schema_file.read())

    seed_demo_data(conn)
    conn.commit()
    conn.close()

    validate_database(BUILD_DB_PATH)
    shutil.copy2(BUILD_DB_PATH, DB_PATH)
    print(f"Created {DB_PATH}")


def validate_database(path: Path) -> None:
    conn = sqlite3.connect(path)
    expected_tables = {
        "users",
        "devices",
        "agents",
        "events",
        "clips",
        "recordings",
        "alerts",
        "tool_audit",
        "push_tokens",
    }
    actual_tables = {
        row[0]
        for row in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")
    }
    missing_tables = expected_tables - actual_tables
    if missing_tables:
        raise RuntimeError(f"Missing tables: {sorted(missing_tables)}")
    conn.close()


def seed_demo_data(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        INSERT INTO users (
            user_id, google_sub, email, email_verified, display_name,
            avatar_url, role, last_login_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            "usr_demo_001",
            "google-sub-demo-001",
            "demo@erlang.local",
            1,
            "Demo User",
            "https://example.com/demo-avatar.png",
            "user",
            "2026-06-11T12:00:00Z",
        ),
    )

    conn.execute(
        """
        INSERT INTO devices (
            device_id, user_id, edge_token_hash, name, location,
            health_status, rssi, fps, current_pan, current_tilt, last_seen
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            "dev_frontdoor_001",
            "usr_demo_001",
            hash_edge_token(DEMO_EDGE_TOKEN),
            "Front Door Camera",
            "Front Door",
            "online",
            -58.2,
            15.0,
            90,
            90,
            "2026-06-11T12:45:00Z",
        ),
    )

    conn.execute(
        """
        INSERT INTO agents (
            agent_id, user_id, device_id, parent_agent_id, name, location, nl_rule,
            compiled_prompt, compiled_edge_config, state, enabled
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            "agt_frontdoor_night",
            "usr_demo_001",
            "dev_frontdoor_001",
            None,
            "Night Front Door Watch",
            "Front Door",
            "Alert me if a person is lingering near the front door after 10 PM.",
            "Verify whether the scene matches a person lingering near the front door after hours.",
            json.dumps(
                {
                    "detectors": ["person"],
                    "schedule": {"start": "22:00", "end": "06:00"},
                    "min_confidence": 0.75,
                }
            ),
            "armed",
            1,
        ),
    )

    conn.execute(
        """
        INSERT INTO events (
            event_id, user_id, agent_id, device_id, idempotency_key,
            timestamp, event_type, stage1_result, stage2_verdict,
            stage3_verdict, severity, confidence, summary, degraded, status
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            "evt_demo_001",
            "usr_demo_001",
            "agt_frontdoor_night",
            "dev_frontdoor_001",
            "dev_frontdoor_001-20260611T124500-person",
            "2026-06-11T12:45:00Z",
            "person_detected",
            json.dumps({"detector": "person", "boxes": [{"x": 0.42, "y": 0.2, "w": 0.18, "h": 0.55}]}),
            json.dumps({"matched_rule": True, "reason": "Person present near front door"}),
            json.dumps({"verified": True, "recommended_action": "notify"}),
            "high",
            0.92,
            "Person detected near the front door.",
            0,
            "verified",
        ),
    )

    conn.execute(
        """
        INSERT INTO clips (
            clip_id, event_id, user_id, device_id, idempotency_key,
            storage_type, storage_path, oss_object_key, clip_type,
            duration_seconds, file_size_bytes, mime_type, checksum_sha256,
            status, upload_id, upload_started_at, upload_completed_at,
            upload_expires_at, expires_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            "clip_demo_001",
            "evt_demo_001",
            "usr_demo_001",
            "dev_frontdoor_001",
            "dev_frontdoor_001-evt_demo_001-main-clip",
            "oss",
            None,
            "events/usr_demo_001/dev_frontdoor_001/evt_demo_001/clip_clip_demo_001.mp4",
            "event",
            12,
            8241120,
            "video/mp4",
            "demo-sha256",
            "available",
            "upload_demo_001",
            "2026-06-11T12:46:00Z",
            "2026-06-11T12:46:30Z",
            "2026-06-11T13:01:00Z",
            "2026-06-18T12:46:30Z",
        ),
    )

    conn.execute(
        """
        INSERT INTO recordings (
            recording_id, user_id, device_id, start_time, end_time,
            storage_type, storage_path, oss_object_key, duration_seconds,
            file_size_bytes, mime_type, checksum_sha256, status, retention_until
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            "rec_demo_001",
            "usr_demo_001",
            "dev_frontdoor_001",
            "2026-06-11T12:00:00Z",
            "2026-06-11T12:30:00Z",
            "local_edge",
            "recordings/dev_frontdoor_001/2026-06-11/rec_demo_001.mp4",
            None,
            1800,
            256000000,
            "video/mp4",
            "demo-recording-sha256",
            "local_only",
            "2026-06-14T12:30:00Z",
        ),
    )

    conn.execute(
        """
        INSERT INTO alerts (
            alert_id, event_id, user_id, channel, sent_at, status, dedupe_key
        )
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            "alrt_demo_001",
            "evt_demo_001",
            "usr_demo_001",
            "telegram",
            "2026-06-11T12:45:10Z",
            "sent",
            "evt_demo_001-telegram-high",
        ),
    )

    conn.execute(
        """
        INSERT INTO tool_audit (
            audit_id, event_id, user_id, device_id, tool_name,
            arguments, result, called_by, timestamp
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            "aud_demo_001",
            "evt_demo_001",
            "usr_demo_001",
            "dev_frontdoor_001",
            "pan_camera",
            json.dumps({"angle": 90}),
            json.dumps({"status": "ok"}),
            "qwen_agent",
            "2026-06-11T12:45:05Z",
        ),
    )


if __name__ == "__main__":
    main()




