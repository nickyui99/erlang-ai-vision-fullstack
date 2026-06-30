# Edge Device Integration Guide

This document describes how the LaptopEdge bridge connects the ESP32 camera to the SentinelEdge Fullstack backend.

The backend does not connect directly to a LAN camera. The edge bridge keeps outbound connections open to the backend, receives frames from the ESP32, runs local AI, and relays commands back to the camera.

## Repo Boundaries

| Repo | Responsibility |
|---|---|
| `SentinelEdge-Fullstack` | FastAPI backend, Flutter app, auth, devices, agents, live stream fan-out, command relay, events, media metadata, push alerts, Qwen Cloud verification. |
| `SentinelEdge_LaptopEdge` | Bridge process, ESP32 USB/Wi-Fi intake, YOLO video detection, optional YAMNet audio detection, Ollama `qwen3.5:0.8b` local triage, event posting. |
| `SentinelEdge_IOT` | ESP32-S3 camera firmware, QR provisioning, Wi-Fi/USB transport, JPEG capture, pan/tilt servo control. |

## Authentication

Use a device-bound edge token:

```http
Authorization: Bearer <edge_token>
```

The backend derives `device_id` and `user_id` from the token. The edge service must not send trusted ownership fields. If an edge payload includes a device id for correlation, it must match the token-bound device.

## Startup Sequence

1. Load the edge token issued once by `POST /api/v1/devices`.
2. Send `POST /api/v1/edge/heartbeat`.
3. Pull active camera-agent configs from `GET /api/v1/edge/agents/active`.
4. Connect to `WS /api/v1/edge/ws` for commands and command results.
5. Connect to `WS /api/v1/edge/stream` and send binary JPEG frames.
6. Start ESP32 frame intake over Wi-Fi WebSocket or USB serial.
7. Run local detection and post events when rules match.

## Heartbeat

Endpoint:

```text
POST /api/v1/edge/heartbeat
```

Example request:

```json
{
  "health_status": "online",
  "rssi": -58.2,
  "fps": 15.0,
  "current_pan": 90,
  "current_tilt": 90
}
```

`current_pan` reports the horizontal servo angle. `current_tilt` reports the vertical servo angle. Pan accepts `0..180`; tilt accepts `60..140`, matching the current mechanical safe range. Edges that do not yet report tilt default to `90` for backward compatibility.

The backend updates device health, `last_seen`, RSSI, FPS, pan, and tilt. It emits `device.health_changed` over SSE when visible state changes.

## Active Agent Config Pull

Endpoint:

```text
GET /api/v1/edge/agents/active
```

Example response:

```json
{
  "data": [
    {
      "agent_id": "agt_frontdoor_night",
      "device_id": "dev_frontdoor_001",
      "state": "armed",
      "compiled_edge_config": {
        "detectors": ["person"],
        "min_confidence": 0.75,
        "rule_text": "alert me when a person is visible"
      }
    }
  ],
  "request_id": "req_123"
}
```

Current rule compilation is intentionally simple: the backend normalizes the natural language rule and emits a person detector config. Rich NL-to-detector compilation remains future work.

## Live Video Stream

Endpoint:

```text
WS /api/v1/edge/stream
```

The edge bridge sends one JPEG frame per binary WebSocket message. The backend stores the latest frame in memory for that device and serves it to app clients through signed stream URLs:

- `POST /api/v1/devices/{device_id}/stream-url` mints a short-lived signed URL.
- `GET /api/v1/devices/{device_id}/stream` returns MJPEG.
- `GET /api/v1/devices/{device_id}/stream-frame` returns the latest JPEG frame for polling clients.

The stream socket is only a fan-out path. Detection should continue to happen in `SentinelEdge_LaptopEdge`.

## Local AI Detection

The current local edge pipeline is expected to run in `SentinelEdge_LaptopEdge`:

- YOLO for video object detection, including human/person detection.
- Optional YAMNet for audio labels when audio frames are available.
- Ollama `qwen3.5:0.8b` local triage before posting selected events.

The backend receives the result. It does not run YOLO, YAMNet, or local Ollama itself.

## Event Submission

Endpoint:

```text
POST /api/v1/edge/events
```

Example request:

```json
{
  "event_id": "evt_edge_001",
  "agent_id": "agt_frontdoor_night",
  "timestamp": "2026-06-30T12:45:00Z",
  "event_type": "person_detected",
  "stage1_result": {
    "detector": "yolo",
    "label": "person",
    "boxes": [
      {
        "x": 0.42,
        "y": 0.2,
        "w": 0.18,
        "h": 0.55
      }
    ]
  },
  "stage2_verdict": {
    "triggered": true,
    "confidence": 0.86,
    "reason": "Person visible in camera frame"
  },
  "severity": "high",
  "confidence": 0.92,
  "summary": "Person detected near the front door.",
  "degraded": false,
  "idempotency_key": "dev_frontdoor_001-20260630T124500-person"
}
```

The backend enforces idempotency per device. Use a stable `idempotency_key` when retrying the same physical event.

Events at or above `ALERT_MIN_SEVERITY` trigger best-effort Firebase Cloud Messaging alerts to registered user devices. Alert delivery never blocks event ingestion.

## Clip Upload Flow

Preferred flow for event clips:

1. Edge submits event.
2. Edge requests an upload URL.
3. Edge uploads the clip directly to object storage when configured.
4. Edge marks the clip complete.
5. Backend marks the clip `available`.
6. Backend emits `clip.available` through SSE.

Create upload URL:

```text
POST /api/v1/edge/clips/upload-url
```

Example request:

```json
{
  "event_id": "evt_edge_001",
  "clip_type": "event",
  "mime_type": "video/mp4",
  "duration_seconds": 12,
  "file_size_bytes": 8241120,
  "checksum_sha256": "sha256-hex-value",
  "idempotency_key": "dev_frontdoor_001-evt_edge_001-main-clip"
}
```

Complete upload:

```text
POST /api/v1/edge/clips/{clip_id}/complete
```

Example request:

```json
{
  "file_size_bytes": 8241120,
  "checksum_sha256": "sha256-hex-value"
}
```

## Recording Metadata

Daily or continuous recordings can stay local by default. The edge can still register metadata so the app knows what exists.

Endpoint:

```text
POST /api/v1/edge/recordings
```

Example request:

```json
{
  "start_time": "2026-06-30T12:00:00Z",
  "end_time": "2026-06-30T12:30:00Z",
  "storage_type": "local_edge",
  "storage_path": "recordings/dev_frontdoor_001/2026-06-30/rec_001.mp4",
  "duration_seconds": 1800,
  "file_size_bytes": 256000000,
  "mime_type": "video/mp4",
  "checksum_sha256": "sha256-hex-value",
  "status": "local_only"
}
```

## WebSocket Commands

Endpoint:

```text
WS /api/v1/edge/ws
```

The backend sends user and Qwen tool commands over this socket. The edge must answer every command with `response.command_result` using the same `request_id`.

Supported command types:

- `command.pan_camera`
- `command.tilt_camera`
- `command.get_live_snapshot`

Pan command example:

```json
{
  "type": "command.pan_camera",
  "request_id": "cmd_001",
  "device_id": "dev_frontdoor_001",
  "payload": {
    "angle": 90
  }
}
```

Tilt command example:

```json
{
  "type": "command.tilt_camera",
  "request_id": "cmd_002",
  "device_id": "dev_frontdoor_001",
  "payload": {
    "angle": 120
  }
}
```

Snapshot command example:

```json
{
  "type": "command.get_live_snapshot",
  "request_id": "cmd_003",
  "device_id": "dev_frontdoor_001",
  "payload": {}
}
```

Result example:

```json
{
  "type": "response.command_result",
  "request_id": "cmd_001",
  "status": "ok",
  "payload": {
    "angle": 90
  }
}
```

If the edge is disconnected, user-facing command APIs return `503 edge_not_connected`. If the edge does not answer before timeout, the backend returns `504 command_timeout`.

## Qwen Cloud Verification

When an event qualifies for verification, the backend can call Qwen Cloud with audited tools. Tool calls can read device status, request a live snapshot, pan the camera, and inspect recent events or clips. Tool actions are persisted in `tool_audit`.

This is separate from local Ollama triage in LaptopEdge:

- Local Ollama filters or explains edge candidates before event submission.
- Qwen Cloud verifies selected backend events and may request camera tools through the backend command relay.

## Retry Rules

- Use stable `idempotency_key` values for events and clips.
- Retry network failures with backoff.
- Do not create new event IDs for the same physical event retry.
- If an upload URL expires, request a new upload URL for the same clip or idempotency key.
- Reconnect both WebSockets after disconnect and send heartbeat after reconnect.
