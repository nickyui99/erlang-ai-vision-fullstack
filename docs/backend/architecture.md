# SentinelEdge Architecture

This document gives a high-level view of the current MVP architecture: auth, the device/agent loop, edge command relay, and push alerts.

## Current MVP Architecture

```mermaid
flowchart LR
    Flutter[Flutter App] --> Firebase[Firebase Auth]
    Firebase --> Flutter
    Flutter --> Backend[FastAPI Backend]
    Backend --> FirebaseAdmin[Firebase Admin SDK]
    FirebaseAdmin --> Firebase
    Backend --> Database[(SQLite local / PostgreSQL target)]
    Backend -->|SSE| Flutter
    Backend -->|FCM push| FCM[Firebase Cloud Messaging]
    FCM --> Flutter
    Edge[Laptop Edge Service] -->|REST + WebSocket| Backend
    Backend -->|command relay| Edge
    Edge --> Camera[Camera / ESP32-CAM + SG90 gimbal]
```

## Authentication Flow

```mermaid
sequenceDiagram
    participant User
    participant Flutter as Flutter Web App
    participant Firebase as Firebase Auth
    participant Backend as FastAPI Backend
    participant DB as Database

    User->>Flutter: Sign in with Google
    Flutter->>Firebase: Firebase Google sign-in
    Firebase-->>Flutter: Firebase ID token
    Flutter->>Backend: POST /api/v1/auth/firebase/login
    Backend->>Firebase: Verify ID token
    Firebase-->>Backend: Verified identity claims
    Backend->>DB: Create or update user
    Backend-->>Flutter: Set SentinelEdge session cookie
    Flutter->>Backend: GET /api/v1/users/me
    Backend-->>Flutter: Current user profile
```

## Device and Agent Loop

```mermaid
flowchart LR
    Flutter[Flutter App] --> Backend[FastAPI Backend]
    Backend --> DB[(Database)]
    Backend --> Edge[Laptop Edge Service]
    Edge --> Camera[Camera / ESP32-CAM]
    Edge --> Backend

    Flutter -->|Register device| Backend
    Backend -->|Return edge token once| Flutter
    Edge -->|Heartbeat with edge token| Backend
    Flutter -->|Create and arm agent| Backend
    Edge -->|Pull active agent config| Backend
```

## Edge Command Relay

User-initiated camera commands are relayed to the edge service over the
WebSocket channel, never sent directly to the camera. Pan and tilt drive the
two SG90 servos of the gimbal (each `0–180°`, centered at `90°`); snapshot
requests a fresh frame. Every command is audit-logged in `tool_audit`.

```mermaid
sequenceDiagram
    participant Flutter as Flutter App
    participant Backend as FastAPI Backend
    participant Edge as Laptop Edge Service
    participant Camera as Camera + SG90 gimbal

    Flutter->>Backend: POST /devices/{id}/pan|tilt|snapshot
    Backend->>Edge: command.* over WebSocket (request_id)
    Edge->>Camera: drive servo / capture frame
    Edge-->>Backend: response.command_result (request_id)
    Backend->>Backend: write tool_audit row
    Backend-->>Flutter: command result
```

## Alert Flow (Milestone 8 — Firebase Cloud Messaging)

When the edge submits an event whose severity is at or above
`ALERT_MIN_SEVERITY` (default `high`), the backend creates a deduplicated alert,
pushes it to every FCM token the owner has registered, stores the delivery
result, and emits `alert.created` over SSE. Delivery is best-effort and never
blocks event ingestion.

```mermaid
sequenceDiagram
    participant Edge as Laptop Edge Service
    participant Backend as FastAPI Backend
    participant DB as Database
    participant FCM as Firebase Cloud Messaging
    participant Flutter as Flutter App

    Edge->>Backend: POST /api/v1/edge/events (severity)
    Backend->>DB: store event
    Backend->>Backend: severity >= threshold?
    alt qualifies
        Backend->>DB: insert alert (dedup on event+channel)
        Backend->>FCM: send push to user's tokens
        FCM-->>Flutter: notification
        Backend->>DB: update alert status (sent / failed / no_recipients)
        Backend-->>Flutter: SSE alert.created
    end
```

Clients register an FCM registration token with
`POST /api/v1/notifications/tokens` and remove it on logout with
`DELETE /api/v1/notifications/tokens/{token}`. FCM reuses the same Firebase
Admin SDK and service-account credentials configured for auth.
