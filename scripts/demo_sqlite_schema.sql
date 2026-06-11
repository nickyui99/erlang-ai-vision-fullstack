PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
    user_id TEXT PRIMARY KEY,
    google_sub TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL UNIQUE,
    email_verified INTEGER NOT NULL DEFAULT 0,
    display_name TEXT,
    avatar_url TEXT,
    role TEXT NOT NULL DEFAULT 'user',
    last_login_at TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS devices (
    device_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    edge_token_hash TEXT NOT NULL,
    name TEXT NOT NULL,
    location TEXT,
    health_status TEXT NOT NULL DEFAULT 'unknown',
    rssi REAL,
    fps REAL,
    current_pan INTEGER NOT NULL DEFAULT 90,
    last_seen TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE,
    CHECK (current_pan >= 0 AND current_pan <= 180)
);

CREATE TABLE IF NOT EXISTS agents (
    agent_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    name TEXT NOT NULL,
    location TEXT,
    nl_rule TEXT NOT NULL,
    compiled_prompt TEXT,
    compiled_edge_config TEXT,
    state TEXT NOT NULL DEFAULT 'disarmed',
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE,
    FOREIGN KEY (device_id) REFERENCES devices (device_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS events (
    event_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    event_type TEXT NOT NULL,
    stage1_result TEXT,
    stage2_verdict TEXT,
    stage3_verdict TEXT,
    severity TEXT NOT NULL,
    confidence REAL,
    summary TEXT,
    degraded INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'candidate',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE,
    FOREIGN KEY (agent_id) REFERENCES agents (agent_id) ON DELETE CASCADE,
    FOREIGN KEY (device_id) REFERENCES devices (device_id) ON DELETE CASCADE,
    UNIQUE (device_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS clips (
    clip_id TEXT PRIMARY KEY,
    event_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    idempotency_key TEXT,
    storage_type TEXT NOT NULL,
    storage_path TEXT,
    oss_object_key TEXT,
    clip_type TEXT NOT NULL DEFAULT 'event',
    duration_seconds INTEGER,
    file_size_bytes INTEGER,
    mime_type TEXT,
    checksum_sha256 TEXT,
    status TEXT NOT NULL DEFAULT 'pending_upload',
    upload_id TEXT,
    upload_started_at TEXT,
    upload_completed_at TEXT,
    upload_expires_at TEXT,
    upload_error TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TEXT,
    expires_at TEXT,
    FOREIGN KEY (event_id) REFERENCES events (event_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE,
    FOREIGN KEY (device_id) REFERENCES devices (device_id) ON DELETE CASCADE,
    UNIQUE (device_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS recordings (
    recording_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    storage_type TEXT NOT NULL,
    storage_path TEXT,
    oss_object_key TEXT,
    duration_seconds INTEGER,
    file_size_bytes INTEGER,
    mime_type TEXT,
    checksum_sha256 TEXT,
    status TEXT NOT NULL DEFAULT 'local_only',
    upload_id TEXT,
    upload_started_at TEXT,
    upload_completed_at TEXT,
    upload_expires_at TEXT,
    upload_error TEXT,
    retention_until TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TEXT,
    FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE,
    FOREIGN KEY (device_id) REFERENCES devices (device_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS alerts (
    alert_id TEXT PRIMARY KEY,
    event_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    channel TEXT NOT NULL,
    sent_at TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    dedupe_key TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (event_id) REFERENCES events (event_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE,
    UNIQUE (dedupe_key)
);

CREATE TABLE IF NOT EXISTS tool_audit (
    audit_id TEXT PRIMARY KEY,
    event_id TEXT,
    user_id TEXT NOT NULL,
    device_id TEXT,
    tool_name TEXT NOT NULL,
    arguments TEXT,
    result TEXT,
    called_by TEXT NOT NULL,
    timestamp TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (event_id) REFERENCES events (event_id) ON DELETE SET NULL,
    FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE,
    FOREIGN KEY (device_id) REFERENCES devices (device_id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices (user_id);
CREATE INDEX IF NOT EXISTS idx_agents_user_id ON agents (user_id);
CREATE INDEX IF NOT EXISTS idx_agents_device_id ON agents (device_id);
CREATE INDEX IF NOT EXISTS idx_events_user_timestamp ON events (user_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_events_device_timestamp ON events (device_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_events_status ON events (status);
CREATE INDEX IF NOT EXISTS idx_clips_event_id ON clips (event_id);
CREATE INDEX IF NOT EXISTS idx_clips_user_id ON clips (user_id);
CREATE INDEX IF NOT EXISTS idx_recordings_user_start ON recordings (user_id, start_time DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_user_id ON alerts (user_id);
CREATE INDEX IF NOT EXISTS idx_tool_audit_user_timestamp ON tool_audit (user_id, timestamp DESC);
