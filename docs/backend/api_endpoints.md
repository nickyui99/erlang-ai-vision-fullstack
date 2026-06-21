# SentinelEdge Backend API Endpoints

This document describes the SentinelEdge backend API surface.

## Implementation Status

Currently implemented endpoints:

| Method | Endpoint | Status |
|---|---|---|
| `GET` | `/healthz` | Implemented |
| `GET` | `/readyz` | Implemented |
| `GET` | `/api/v1/version` | Implemented |
| `POST` | `/api/v1/auth/firebase/login` | Implemented |
| `POST` | `/api/v1/auth/logout` | Implemented |
| `GET` | `/api/v1/users/me` | Implemented |
| `POST` | `/api/v1/devices` | Implemented |
| `GET` | `/api/v1/devices` | Implemented |
| `GET` | `/api/v1/devices/{device_id}` | Implemented |
| `PUT` | `/api/v1/devices/{device_id}` | Implemented |
| `POST` | `/api/v1/devices/{device_id}/pan` | Implemented |
| `POST` | `/api/v1/devices/{device_id}/snapshot` | Implemented |
| `POST` | `/api/v1/agents` | Implemented |
| `GET` | `/api/v1/agents` | Implemented |
| `GET` | `/api/v1/agents/{agent_id}` | Implemented |
| `PUT` | `/api/v1/agents/{agent_id}` | Implemented |
| `POST` | `/api/v1/agents/{agent_id}/arm` | Implemented |
| `POST` | `/api/v1/agents/{agent_id}/disarm` | Implemented |
| `POST` | `/api/v1/edge/heartbeat` | Implemented |
| `GET` | `/api/v1/edge/agents/active` | Implemented |
| `GET` | `/api/v1/stream/events` | Implemented |
| `WS` | `/api/v1/edge/ws` | Implemented |

Event, clip, recording, SSE, WebSocket, pan command, and snapshot command endpoints are implemented. Alert, Qwen, MCP, and broader tool endpoints are planned for later milestones.

Base API prefix:

```text
/api/v1
```

## Authentication Model

| Actor | Auth method | Notes |
|---|---|---|
| Web app user | Firebase Google sign-in plus backend session cookie | Used for user-facing APIs. |
| Mobile WebView user | Same as web app | Prefer cookie session for WebView and SSE compatibility. |
| Laptop edge service | Device-bound edge token | Used for edge ingestion, heartbeat, config pull, and WebSocket. |
| Admin user | Firebase-authenticated user with `admin` role | Used for privileged/debug actions. |

User-facing routes must derive `user_id` from the authenticated backend session. Edge routes must derive `device_id` and `user_id` from the edge token. Clients should not send trusted `user_id` values.

## Common Response Shapes

Success response:

```json
{
  "data": {},
  "request_id": "req_123"
}
```

Error response:

```json
{
  "error": {
    "code": "not_found",
    "message": "Resource was not found"
  },
  "request_id": "req_123"
}
```

## Health

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/healthz` | Public | Implemented. Basic process health check. |
| `GET` | `/readyz` | Public | Implemented. Validates database availability. |
| `GET` | `/api/v1/version` | Public | Implemented. Returns backend version/build metadata. |

Example `GET /readyz` response:

```json
{
  "data": {
    "status": "ready",
    "database": "ok"
  },
  "request_id": "req_123"
}
```

## Auth

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/api/v1/auth/firebase/login` | Firebase ID token | Implemented. Verifies Firebase ID token, upserts local user, and creates backend session. |
| `POST` | `/api/v1/auth/logout` | User session | Implemented. Ends current user session. |
| `GET` | `/api/v1/users/me` | User session | Implemented. Returns current user profile. |

Example `POST /api/v1/auth/firebase/login` request:

```http
Authorization: Bearer <firebase_id_token>
```

The frontend obtains this ID token from Firebase Auth after Google sign-in. The backend maps Firebase `uid` to the local `users.google_sub` field and still uses local `users.user_id` for ownership.

Example `GET /api/v1/users/me` response:

```json
{
  "data": {
    "user_id": "usr_123",
    "email": "user@example.com",
    "email_verified": true,
    "display_name": "Example User",
    "avatar_url": "https://example.com/avatar.png",
    "role": "user"
  },
  "request_id": "req_123"
}
```

## Devices

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/api/v1/devices` | User session | List devices owned by the current user. |
| `POST` | `/api/v1/devices` | User session | Register a new device and issue an edge token once. |
| `GET` | `/api/v1/devices/{device_id}` | User session | Get device details. |
| `PUT` | `/api/v1/devices/{device_id}` | User session | Update device metadata. |
| `POST` | `/api/v1/edge/heartbeat` | Edge token | Implemented. Update authenticated edge device health status. |
| `POST` | `/api/v1/devices/{device_id}/pan` | User session | Implemented. Request camera pan through edge relay. |
| `POST` | `/api/v1/devices/{device_id}/snapshot` | User session | Implemented. Request a fresh snapshot through edge relay. |

Example `POST /api/v1/devices` request:

```json
{
  "name": "Front Door Camera",
  "location": "Front Door"
}
```

Example response:

```json
{
  "data": {
    "device": {
      "device_id": "dev_123",
      "name": "Front Door Camera",
      "location": "Front Door",
      "health_status": "unknown"
    },
    "edge_token": "shown-once-raw-device-token"
  },
  "request_id": "req_123"
}
```

The backend stores only `edge_token_hash`, not the raw token.

Example `POST /api/v1/edge/heartbeat` request:

```json
{
  "health_status": "online",
  "rssi": -58.2,
  "fps": 15.0,
  "current_pan": 90
}
```

Example `POST /api/v1/devices/{device_id}/pan` request:

```json
{
  "angle": 90
}
```

Example command response:

```json
{
  "data": {
    "request_id": "cmd_123",
    "status": "ok",
    "payload": {
      "angle": 90
    }
  },
  "request_id": "req_123"
}
```

`POST /api/v1/devices/{device_id}/snapshot` accepts an empty body and returns the edge command result using the same response shape.

## Agents

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/api/v1/agents` | User session | List current user's agents. |
| `POST` | `/api/v1/agents` | User session | Create an agent. |
| `GET` | `/api/v1/agents/{agent_id}` | User session | Get agent details. |
| `PUT` | `/api/v1/agents/{agent_id}` | User session | Update agent rule or metadata. |
| `DELETE` | `/api/v1/agents/{agent_id}` | User session | Planned. Delete or disable an agent. |
| `POST` | `/api/v1/agents/{agent_id}/arm` | User session | Arm an agent. |
| `POST` | `/api/v1/agents/{agent_id}/disarm` | User session | Disarm an agent. |
| `GET` | `/api/v1/edge/agents/active` | Edge token | Implemented. Edge pulls active compiled configs for its device. |

Example `POST /api/v1/agents` request:

```json
{
  "device_id": "dev_123",
  "name": "Night Front Door Watch",
  "location": "Front Door",
  "nl_rule": "Alert me if a person is lingering near the front door after 10 PM."
}
```

Example response:

```json
{
  "data": {
    "agent_id": "agt_123",
    "device_id": "dev_123",
    "name": "Night Front Door Watch",
    "state": "disarmed",
    "enabled": true,
    "compiled_edge_config": {
      "detectors": ["person"],
      "min_confidence": 0.75,
      "rule_text": "Alert me if a person is lingering near the front door after 10 PM."
    }
  },
  "request_id": "req_123"
}
```

## Edge APIs

Edge APIs are used by the laptop edge service or camera gateway. They require a device-bound edge token.

Recommended header:

```http
Authorization: Bearer <edge_token>
```

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/api/v1/edge/heartbeat` | Edge token | Implemented. Update current edge/device health. |
| `GET` | `/api/v1/edge/agents/active` | Edge token | Implemented. Pull active compiled agent configs for the authenticated device. |
| `POST` | `/api/v1/edge/events` | Edge token | Submit a candidate or verified event. |
| `POST` | `/api/v1/edge/clips` | Edge token | Register clip metadata for an event. |
| `POST` | `/api/v1/edge/clips/upload-url` | Edge token | Create clip metadata and return signed upload URL. |
| `POST` | `/api/v1/edge/clips/{clip_id}/complete` | Edge token | Mark direct upload as complete. |
| `POST` | `/api/v1/edge/recordings` | Edge token | Register recording segment metadata. |
| `WS` | `/api/v1/edge/ws` | Edge token | Implemented. Bidirectional command channel. |

Example `POST /api/v1/edge/events` request:

```json
{
  "event_id": "evt_edge_001",
  "agent_id": "agt_123",
  "timestamp": "2026-06-11T12:45:00Z",
  "event_type": "person_detected",
  "stage1_result": {
    "detector": "person",
    "boxes": []
  },
  "stage2_verdict": {
    "matched_rule": true
  },
  "severity": "high",
  "confidence": 0.92,
  "summary": "Person detected near the front door.",
  "degraded": false,
  "idempotency_key": "dev_123-20260611T124500-person"
}
```

The backend derives `device_id` and `user_id` from the edge token. If the request includes a `device_id`, it must match the token-bound device.

Example `POST /api/v1/edge/clips/upload-url` request:

```json
{
  "event_id": "evt_edge_001",
  "clip_type": "event",
  "mime_type": "video/mp4",
  "duration_seconds": 12,
  "file_size_bytes": 8241120,
  "checksum_sha256": "sha256-hex-value",
  "idempotency_key": "dev_123-evt_edge_001-main-clip"
}
```

Example response:

```json
{
  "data": {
    "clip_id": "clip_123",
    "upload_url": "https://oss-region.aliyuncs.com/signed-upload-url",
    "oss_object_key": "events/usr_123/dev_123/evt_edge_001/clip_clip_123.mp4",
    "upload_expires_at": "2026-06-11T13:00:00Z"
  },
  "request_id": "req_123"
}
```

Example `POST /api/v1/edge/clips/{clip_id}/complete` request:

```json
{
  "file_size_bytes": 8241120,
  "checksum_sha256": "sha256-hex-value"
}
```

## Events

User-facing event APIs require a user session.

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/api/v1/events` | User session | List current user's events. |
| `GET` | `/api/v1/events/{event_id}` | User session | Get event details. |
| `PATCH` | `/api/v1/events/{event_id}/status` | User session | Update event status. |
| `POST` | `/api/v1/events/{event_id}/dismiss` | User session | Dismiss an event. |
| `POST` | `/api/v1/events/{event_id}/false-positive` | User session | Mark event as false positive. |

Recommended query parameters for `GET /api/v1/events`:

| Parameter | Description |
|---|---|
| `device_id` | Filter by device. |
| `agent_id` | Filter by agent. |
| `status` | Filter by lifecycle status. |
| `severity` | Filter by severity. |
| `from` | Start timestamp. |
| `to` | End timestamp. |
| `limit` | Page size. |
| `cursor` | Pagination cursor. |

Example event response:

```json
{
  "data": {
    "event_id": "evt_edge_001",
    "device_id": "dev_123",
    "agent_id": "agt_123",
    "timestamp": "2026-06-11T12:45:00Z",
    "event_type": "person_detected",
    "severity": "high",
    "confidence": 0.92,
    "summary": "Person detected near the front door.",
    "degraded": false,
    "status": "verified"
  },
  "request_id": "req_123"
}
```

## Clips

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/api/v1/clips` | User session or edge token | Create clip metadata. Prefer edge route for device uploads. |
| `GET` | `/api/v1/events/{event_id}/clips` | User session | List clips for an event. |
| `GET` | `/api/v1/clips/{clip_id}` | User session | Get clip metadata. |
| `POST` | `/api/v1/clips/{clip_id}/signed-url` | User session | Generate temporary playback URL. |
| `DELETE` | `/api/v1/clips/{clip_id}` | User session | Soft-delete clip metadata and optionally delete OSS object. |

Example signed URL response:

```json
{
  "data": {
    "clip_id": "clip_123",
    "playback_url": "https://oss-region.aliyuncs.com/signed-playback-url",
    "expires_at": "2026-06-11T13:00:00Z"
  },
  "request_id": "req_123"
}
```

Signed URL generation must check ownership, `deleted_at`, and clip `status`.

## Recordings

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/api/v1/recordings` | User session or edge token | Create recording metadata. Prefer edge route for device submissions. |
| `GET` | `/api/v1/recordings` | User session | List current user's recording segments. |
| `GET` | `/api/v1/recordings/{recording_id}` | User session | Get recording metadata. |
| `POST` | `/api/v1/recordings/{recording_id}/signed-url` | User session | Generate temporary playback URL if uploaded. |
| `DELETE` | `/api/v1/recordings/{recording_id}` | User session | Soft-delete recording metadata and optionally delete OSS object. |

Recommended query parameters for `GET /api/v1/recordings`:

| Parameter | Description |
|---|---|
| `device_id` | Filter by device. |
| `from` | Recording start lower bound. |
| `to` | Recording end upper bound. |
| `status` | Filter by recording status. |
| `limit` | Page size. |
| `cursor` | Pagination cursor. |

## Alerts

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/api/v1/alerts` | User session | List alert records for current user. |
| `GET` | `/api/v1/alerts/{alert_id}` | User session | Get alert delivery details. |
| `POST` | `/api/v1/alerts/{alert_id}/retry` | User session or admin | Retry a failed alert if allowed. |

Example alert response:

```json
{
  "data": {
    "alert_id": "alrt_123",
    "event_id": "evt_edge_001",
    "channel": "telegram",
    "status": "sent",
    "sent_at": "2026-06-11T12:45:10Z"
  },
  "request_id": "req_123"
}
```

## Realtime SSE

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/api/v1/stream/events` | User session | Implemented. Server-Sent Events stream for event, device, agent, and clip updates. |

Recommended event types:

```text
event.created
event.verified
event.alerted
device.health_changed
agent.state_changed
clip.available
```

Example SSE message:

```text
event: event.created
data: {"event_id":"evt_edge_001","device_id":"dev_123","severity":"high"}
```

For browser `EventSource`, prefer session-cookie authentication because custom authorization headers are not supported by the native API.

## Edge WebSocket

Endpoint:

```text
WS /api/v1/edge/ws
```

Auth:

```http
Authorization: Bearer <edge_token>
```

The backend derives the connected `device_id` and `user_id` from the edge token. One active connection is tracked per device; a newer connection replaces the old one.

Command message example:

```json
{
  "type": "command.pan_camera",
  "request_id": "cmd_001",
  "device_id": "dev_123",
  "payload": {
    "angle": 90
  }
}
```

Command result example:

```json
{
  "type": "response.command_result",
  "request_id": "cmd_001",
  "status": "ok"
}
```

Snapshot command example:

```json
{
  "type": "command.get_live_snapshot",
  "request_id": "cmd_002",
  "device_id": "dev_123",
  "payload": {}
}
```

If an edge device is disconnected, user-facing command APIs return `503 edge_not_connected`. If the edge client does not respond within 10 seconds, they return `504 command_timeout`.

## Tool Actions

Tool endpoints are backend-controlled and should not expose unsafe direct device control to arbitrary clients.

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/api/v1/tools/pan-camera` | User session or internal Qwen/MCP policy | Request camera pan through audited relay. |
| `POST` | `/api/v1/tools/live-snapshot` | User session or internal Qwen/MCP policy | Request fresh snapshot through edge relay. |
| `GET` | `/api/v1/tools/audit` | User session | List tool audit records for current user. |

All tool calls must be permission checked, rate limited, and written to `TOOL_AUDIT`.

## Status Codes

| Status | Meaning |
|---|---|
| `200` | Successful read/update. |
| `201` | Resource created. |
| `202` | Accepted for async processing. |
| `204` | Successful delete/logout with no body. |
| `400` | Invalid request payload. |
| `401` | Missing or invalid authentication. |
| `403` | Authenticated but not allowed. |
| `404` | Resource not found or not owned by caller. |
| `409` | Duplicate or conflicting state, including idempotency conflict. |
| `422` | Validation error. |
| `429` | Rate limit exceeded. |
| `500` | Unexpected backend error. |
| `503` | Dependency unavailable or readiness failure. |

## Ownership Rules

- User APIs must filter resources by authenticated `user_id`.
- Edge APIs must derive `device_id` and `user_id` from the edge token.
- Edge event ingestion must verify that the agent belongs to the same device/user.
- Signed URL generation must reject deleted media and media not owned by the caller.
- Tool calls must verify target device ownership and write an audit record.

