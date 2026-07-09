# SentinelEdge Backend API Endpoints

Base API prefix: `/api/v1`

Interactive docs are available at `http://localhost:8000/docs` in development.

All datetimes in responses are serialized as UTC with a trailing `Z` (e.g. `2026-07-06T11:34:45Z`). SQLite drops timezone info on storage, so the schema layer normalizes it — clients can parse as UTC and convert to local time.

## Authentication Model

| Actor | Auth method | Used for |
|---|---|---|
| Flutter user | Firebase Google sign-in, then backend session cookie | Device, agent, event, stream URL, command APIs |
| Edge bridge | `Authorization: Bearer <edge_token>` | Heartbeat, active configs, event/media ingestion, edge WebSockets |
| Qwen verifier tools | Internal backend call path | Snapshot, pan, status, recent event/clip reads with `tool_audit` |

The backend derives ownership from the session or edge token. Clients must not send trusted `user_id` values.

## Health and Version

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/healthz` | Public | Process health. |
| `GET` | `/readyz` | Public | Database readiness. |
| `GET` | `/api/v1/version` | Public | Backend version/build metadata. |

## Auth and Users

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/api/v1/auth/firebase/login` | Firebase bearer token | Verify Firebase ID token, upsert local user, create backend session cookie. |
| `POST` | `/api/v1/auth/logout` | User session | Clear current session. |
| `GET` | `/api/v1/users/me` | User session | Return current user profile. |

Login request header:

```http
Authorization: Bearer <firebase_id_token>
```

## Devices

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/api/v1/devices` | User session | Register a camera and return the raw edge token once. |
| `GET` | `/api/v1/devices` | User session | List current user's devices. |
| `GET` | `/api/v1/devices/{device_id}` | User session | Get device details. |
| `PUT` | `/api/v1/devices/{device_id}` | User session | Update device name/location. |
| `DELETE` | `/api/v1/devices/{device_id}` | User session | Unregister camera; dependent rows cascade by DB constraints. |
| `POST` | `/api/v1/devices/{device_id}/pan` | User session | Relay horizontal pan command, `angle: 0..180`. |
| `POST` | `/api/v1/devices/{device_id}/tilt` | User session | Relay vertical tilt command, `angle: 60..140`. |
| `POST` | `/api/v1/devices/{device_id}/snapshot` | User session | Request a fresh snapshot through the edge command channel. |
| `POST` | `/api/v1/devices/{device_id}/control` | User session | Relay a device control command (e.g. recording/resolution toggles). |
| `POST` | `/api/v1/devices/{device_id}/stream-url` | User session | Mint short-lived signed stream URL. |
| `GET` | `/api/v1/devices/{device_id}/stream` | Signed query token | MJPEG live stream. |
| `GET` | `/api/v1/devices/{device_id}/stream-frame` | Signed query token | Latest JPEG frame fallback for Flutter web polling. |
| `GET` | `/api/v1/devices/{device_id}/clips` | User session | List clips for a device (`limit`, `status`, `clip_type`). |
| `GET` | `/api/v1/devices/{device_id}/recordings` | User session | List recordings for a device (`limit`, `status`). |

Example device registration:

```json
{
  "name": "Living Room Camera",
  "location": "Living Room"
}
```

Response includes `edge_token` once. The backend stores only `edge_token_hash`.

Example pan request:

```json
{ "angle": 90 }
```

Example tilt request:

```json
{ "angle": 120 }
```

## Agents

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/api/v1/agents` | User session | Create an agent definition. `device_id` is optional for backward compatibility. |
| `GET` | `/api/v1/agents` | User session | List current user's agent definitions and assigned sub-agents. |
| `GET` | `/api/v1/agents/{agent_id}` | User session | Get agent details. |
| `PUT` | `/api/v1/agents/{agent_id}` | User session | Update name/location/rule and recompile edge config. |
| `POST` | `/api/v1/agents/{agent_id}/assign` | User session | Assign a definition to a camera; creates or returns an armed per-device sub-agent. |
| `POST` | `/api/v1/agents/{agent_id}/unassign` | User session | Remove a definition from a camera by deleting the per-device sub-agent. |
| `POST` | `/api/v1/agents/builder` | User session | Conversational agent builder: one chat turn in, `{reply, rule, name, compiled_edge_config}` out. |

Example create:

```json
{
  "name": "Detect people",
  "location": "Living Room",
  "nl_rule": "Alert me when a person is visible."
}
```

Example assign:

```json
{ "device_id": "dev_123" }
```

Compiler behavior (`app/agents/compiler.py`): a Qwen Cloud text model (`QWEN_COMPILER_MODEL`, default `qwen-plus`) compiles `nl_rule` into the edge `compiled_edge_config` — `classes` (COCO video + YAMNet audio labels), `min_confidence`, `dwell_s`, `cooldown_s`, and optional `schedule`/`roi` — plus a `compiled_prompt`. It never fails agent creation: in test/key-less environments or on any LLM/parse error it falls back to a deterministic keyword compiler.

Builder example (`POST /api/v1/agents/builder`):

```json
{ "messages": [{ "role": "user", "content": "tell me if a car pulls into the driveway" }] }
```

Response:

```json
{
  "data": {
    "reply": "Got it — I'll watch for vehicles entering the driveway.",
    "rule": "Alert me when a vehicle pulls into the driveway.",
    "name": "Driveway Vehicle Watch",
    "compiled_edge_config": { "classes": ["car", "truck", "motorcycle", "bus"], "min_confidence": 0.5, "dwell_s": 2.0, "cooldown_s": 45.0 }
  }
}
```

`rule`/`name` are `null` while the assistant still needs more detail; send the running conversation back each turn.

## Chat (AI assistant)

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/api/v1/chat/sessions` | User session | Create a chat session (optionally seed the first message). |
| `GET` | `/api/v1/chat/sessions` | User session | List the user's chat sessions. |
| `POST` | `/api/v1/chat/sessions/{session_id}/messages` | User session | Post a message and get the assistant reply. |
| `GET` | `/api/v1/chat/sessions/{session_id}/messages` | User session | List messages in a session. |
| `DELETE` | `/api/v1/chat/sessions/{session_id}` | User session | Delete a session. |

## Edge APIs

Edge APIs require `Authorization: Bearer <edge_token>`.

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/api/v1/edge/heartbeat` | Edge token | Update health, RSSI, FPS, current pan, and current tilt. |
| `GET` | `/api/v1/edge/agents/active` | Edge token | Pull active assigned agent configs for this device. |
| `POST` | `/api/v1/edge/events` | Edge token | Submit detected/triaged event. |
| `POST` | `/api/v1/edge/clips/upload-url` | Edge token | Create clip metadata and return upload URL info. |
| `POST` | `/api/v1/edge/clips/{clip_id}/complete` | Edge token | Mark clip upload complete. |
| `POST` | `/api/v1/edge/recordings` | Edge token | Register recording metadata. |
| `WS` | `/api/v1/edge/ws` | Edge token | Bidirectional command/result channel. |
| `WS` | `/api/v1/edge/stream` | Edge token | Binary JPEG upstream live-video channel. |

Heartbeat example:

```json
{
  "health_status": "online",
  "rssi": -58.2,
  "fps": 15.0,
  "current_pan": 90,
  "current_tilt": 90
}
```

Event submission example:

```json
{
  "event_id": "evt_edge_001",
  "agent_id": "agt_123",
  "timestamp": "2026-06-30T12:45:00Z",
  "event_type": "person_detected",
  "stage1_result": {"detector": "yolo", "label": "person"},
  "stage2_verdict": {"triggered": true, "confidence": 0.86},
  "severity": "high",
  "confidence": 0.92,
  "summary": "Person detected in the living room.",
  "degraded": false,
  "idempotency_key": "dev_123-20260630T124500-person"
}
```

The backend derives `device_id` and `user_id` from the token. If a payload includes a device id, it must match the token-bound device.

## Edge WebSocket Commands

Endpoint: `WS /api/v1/edge/ws`

Command sent by backend:

```json
{
  "type": "command.pan_camera",
  "request_id": "cmd_001",
  "device_id": "dev_123",
  "payload": {"angle": 90}
}
```

Supported command types:

- `command.pan_camera`
- `command.tilt_camera`
- `command.get_live_snapshot`

Result returned by edge:

```json
{
  "type": "response.command_result",
  "request_id": "cmd_001",
  "status": "ok",
  "payload": {"angle": 90}
}
```

If the edge is disconnected, user-facing command APIs return `503 edge_not_connected`. If the edge does not respond in time, they return `504 command_timeout`.

## Live Video

The edge bridge connects to `WS /api/v1/edge/stream` and sends one JPEG frame per binary WebSocket message. The backend stores the latest frame in memory and fans out MJPEG responses from `/devices/{id}/stream`. `/stream-frame` returns the latest frame as a single `image/jpeg` response for polling clients.

## Events, Clips, and Audit

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/api/v1/events` | User session | List current user's events. Optional `device_id`, `agent_id`, `limit`. |
| `GET` | `/api/v1/events/{event_id}` | User session | Get event details. |
| `GET` | `/api/v1/events/{event_id}/clips` | User session | List clips for an event. |
| `GET` | `/api/v1/events/{event_id}/audit` | User session | List Qwen/tool command audit trail for an event. |
| `POST` | `/api/v1/clips/{clip_id}/signed-url` | User session | Generate temporary clip playback URL. |
| `POST` | `/api/v1/clips/{clip_id}/download-url` | User session | Generate temporary clip download URL. |
| `POST` | `/api/v1/recordings/{recording_id}/signed-url` | User session | Generate temporary recording playback URL. |

### Local media serving (development only)

When `APP_ENV=development` and OSS is not configured, the signed-url/download-url
endpoints above return URLs that point back at the backend instead of at OSS, and
these `GET` routes serve the bytes of a local sample video. They are authenticated
by the same signed **query token** as `/stream` (not the session cookie), and
return `404 media_not_found` outside development or when the sample video is
absent. They exist only so the full playback/download flow is demoable without a
storage bucket.

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/api/v1/clips/{clip_id}/media` | Signed query token | Serve local clip playback bytes (dev fallback). |
| `GET` | `/api/v1/clips/{clip_id}/download` | Signed query token | Serve local clip download bytes (dev fallback). |
| `GET` | `/api/v1/recordings/{recording_id}/media` | Signed query token | Serve local recording playback bytes (dev fallback). |

In production (OSS configured), the signed-url/download-url endpoints return OSS
URLs directly and these routes are not used.

## Notifications and Realtime

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/api/v1/notifications/tokens` | User session | Register FCM token. |
| `DELETE` | `/api/v1/notifications/tokens/{token}` | User session | Remove FCM token. |
| `GET` | `/api/v1/stream/events` | User session | Server-Sent Events stream. |

Common SSE events include `device.health_changed`, `event.created`, `clip.available`, and `alert.created`.

## System

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/api/v1/system/network` | User session | Return LAN backend host/port hints used by the camera pairing QR. |

## Status Codes

| Status | Meaning |
|---|---|
| `200` | Successful read/update. |
| `201` | Resource created. |
| `204` | Successful delete/logout with no body. |
| `400` | Invalid request payload. |
| `401` | Missing or invalid authentication. |
| `403` | Authenticated but not allowed. |
| `404` | Resource not found or not owned. |
| `409` | Idempotency conflict or duplicate state. |
| `410` | Media past its retention period (`clip_expired` / `recording_expired`). |
| `422` | Validation error. |
| `500` | Unexpected backend error. |
| `503` | Dependency unavailable or edge disconnected. |
| `504` | Edge command timed out. |
