# SentinelEdge Backend Architecture

This document describes the current backend architecture in `SentinelEdge-Fullstack` and how it connects to the sibling edge repositories.

## Scope

This repo owns:

- FastAPI HTTP/WebSocket API.
- Firebase login and backend session cookies.
- Device, agent, event, clip, recording, alert, and tool-audit persistence.
- Live JPEG stream fan-out to web clients.
- Command relay between the app/Qwen tools and the edge bridge.
- Qwen Cloud verification for events posted by the edge tier.
- Flutter app UI for camera management, live view, rules, PTZ controls, and event review.

This repo does not own the camera firmware or local detection runtime:

- `SentinelEdge_IOT` owns ESP32 firmware, QR provisioning, Wi-Fi/USB transport, camera capture, and servo control.
- `SentinelEdge_LaptopEdge` owns the local bridge and AI pipeline: YOLO video detection, optional YAMNet audio detection, Ollama Qwen local triage, event posting, and local preview.

## System View

```mermaid
flowchart LR
    App[Flutter App] -->|session APIs| Backend[FastAPI Backend]
    App -->|signed stream URL| Stream[Backend MJPEG/frame endpoints]
    Backend --> DB[(SQLite local / PostgreSQL target)]
    Backend --> FCM[Firebase Cloud Messaging]
    Backend --> Qwen[Qwen Cloud]

    Edge[LaptopEdge bridge + local AI] -->|edge token REST| Backend
    Edge -->|WS commands| Backend
    Edge -->|WS binary JPEG stream| Backend
    Backend -->|command.pan/tilt/snapshot| Edge

    Camera[ESP32 camera firmware] -->|LAN Wi-Fi WS or USB serial| Edge
    Edge -->|pan/tilt/snapshot commands| Camera
```

## Authentication

```mermaid
sequenceDiagram
    participant App as Flutter App
    participant Firebase as Firebase Auth
    participant Backend as FastAPI Backend
    participant DB as Database

    App->>Firebase: Google sign-in
    Firebase-->>App: Firebase ID token
    App->>Backend: POST /api/v1/auth/firebase/login
    Backend->>Firebase: verify ID token
    Backend->>DB: create/update user
    Backend-->>App: SentinelEdge session cookie
    App->>Backend: GET /api/v1/users/me
```

User-facing APIs use the backend session cookie. Edge APIs use a device-bound edge token in `Authorization: Bearer <edge_token>`.

## Device and Agent Model

```mermaid
flowchart TD
    User[User] --> Device[Device / camera]
    User --> Definition[Agent definition]
    Definition -->|assign to camera| SubAgent[Per-device assigned agent]
    SubAgent -->|active config| Edge[Edge pipeline]
    Edge -->|candidate event| Event[Backend event]
```

Agents are now definition-first. Creating an agent can leave `device_id` null. Assigning an agent to a camera creates a per-device sub-agent with `parent_agent_id`, `device_id`, state `armed`, and a compiled edge config. Unassigning deletes that sub-agent.

The current compiler is intentionally simple and emits a person-detection config. Rich natural-language compilation is future work.

## Live Video Flow

```mermaid
sequenceDiagram
    participant Camera as ESP32 Camera
    participant Edge as LaptopEdge Bridge
    participant Backend as Backend Broker
    participant App as Flutter App

    Camera->>Edge: JPEG frames + health
    Edge->>Backend: WS /api/v1/edge/stream binary JPEG
    App->>Backend: POST /devices/{id}/stream-url
    Backend-->>App: signed stream/frame URL
    App->>Backend: GET /devices/{id}/stream or /stream-frame
    Backend-->>App: MJPEG stream or latest JPEG frame
```

The backend broker is in-memory. It keeps only the latest frame per device and fans frames out to active subscribers. The signed stream token is used because browser image requests cannot attach custom auth headers.

## Command Relay

```mermaid
sequenceDiagram
    participant App as Flutter App or Qwen Tool
    participant Backend as FastAPI Backend
    participant Edge as LaptopEdge Bridge
    participant Camera as ESP32 Gimbal

    App->>Backend: POST /devices/{id}/pan|tilt|snapshot
    Backend->>Backend: write tool_audit request
    Backend->>Edge: command.* over WS /api/v1/edge/ws
    Edge->>Camera: pan/tilt/snapshot command
    Camera-->>Edge: state/frame
    Edge-->>Backend: response.command_result
    Backend->>Backend: update tool_audit result
    Backend-->>App: command result
```

Pan accepts `0..180`. Tilt accepts `60..140`, matching the mechanical safe range of the current rig. The device reports `current_pan` and `current_tilt` through heartbeat.

## Event and Verification Flow

```mermaid
sequenceDiagram
    participant Edge as LaptopEdge AI Pipeline
    participant Backend as FastAPI Backend
    participant Qwen as Qwen Cloud
    participant App as Flutter App

    Edge->>Backend: POST /api/v1/edge/events
    Backend->>Backend: persist event, emit SSE
    Backend->>Qwen: verify qualifying event
    Qwen->>Backend: optional tool calls
    Backend->>Edge: snapshot/pan/status tools via command hub
    Backend->>Backend: store stage3_verdict + tool_audit
    Backend->>App: SSE event/alert updates
```

The local LaptopEdge pipeline does Stage 1/2 detection and triage before posting events. The backend Stage 3 verifier is optional and controlled by `VERIFICATION_ENABLED` / `QWEN_API_KEY`.

## Realtime and Alerts

The backend emits SSE at `GET /api/v1/stream/events` for user-visible changes such as device health, events, clips, and alerts. High-severity events create alert records and trigger Firebase Cloud Messaging when push tokens are registered.

## Storage

Local development uses SQLite through async SQLAlchemy. Production targets PostgreSQL-compatible relational storage. Media bytes are not stored in the relational database; clip/recording rows hold metadata and local/OSS paths. The current media URL service is placeholder/local-oriented and should be replaced with real OSS deployment settings for production.
