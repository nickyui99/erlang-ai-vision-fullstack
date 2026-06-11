# Edge Device Integration Guide

This document describes how the laptop edge service or camera gateway should communicate with the backend.

## Responsibilities

The edge service is responsible for:

- reading camera streams
- running local detection
- sending heartbeats
- pulling active agent configs
- submitting events
- registering clips and recordings
- uploading event clips when needed
- maintaining WebSocket connection for commands

The backend is responsible for:

- authenticating the edge token
- deriving device ownership
- storing event and media metadata
- generating signed upload/playback URLs
- relaying user or AI tool commands

## Authentication

Use a device-bound edge token:

```http
Authorization: Bearer <edge_token>
```

The backend derives `device_id` and `user_id` from the token. The edge service should not send trusted `user_id`.

## Startup Sequence

1. Load local edge token.
2. Send heartbeat to `/api/v1/edge/heartbeat`.
3. Pull active configs from `/api/v1/edge/agents/active`.
4. Connect to `WS /api/v1/edge/ws`.
5. Start camera capture and local detection.

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
  "current_pan": 90
}
```

The backend updates `devices.last_seen`, health fields, and emits `device.health_changed` through SSE when needed.

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
        "schedule": {
          "start": "22:00",
          "end": "06:00"
        },
        "min_confidence": 0.75
      }
    }
  ],
  "request_id": "req_123"
}
```

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
  "timestamp": "2026-06-11T12:45:00Z",
  "event_type": "person_detected",
  "stage1_result": {
    "detector": "person",
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
    "matched_rule": true,
    "reason": "Person present near front door"
  },
  "severity": "high",
  "confidence": 0.92,
  "summary": "Person detected near the front door.",
  "degraded": false,
  "idempotency_key": "dev_frontdoor_001-20260611T124500-person"
}
```

The backend should enforce uniqueness on `(device_id, idempotency_key)`.

## Clip Upload Flow

Preferred flow for event clips:

1. Edge submits event.
2. Edge requests signed upload URL.
3. Edge uploads clip directly to OSS.
4. Edge marks upload complete.
5. Backend marks clip `available`.
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

Daily or continuous recordings stay local by default.

Endpoint:

```text
POST /api/v1/edge/recordings
```

Example request:

```json
{
  "start_time": "2026-06-11T12:00:00Z",
  "end_time": "2026-06-11T12:30:00Z",
  "storage_type": "local_edge",
  "storage_path": "recordings/dev_frontdoor_001/2026-06-11/rec_001.mp4",
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

Command example:

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

Result example:

```json
{
  "type": "response.command_result",
  "request_id": "cmd_001",
  "status": "ok"
}
```

## Retry Rules

- Use stable `idempotency_key` values for events and clips.
- Retry network failures with backoff.
- Do not create new event IDs for the same physical event retry.
- If upload URL expires, request a new upload URL for the same clip or idempotency key.
