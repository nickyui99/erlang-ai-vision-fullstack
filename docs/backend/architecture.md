# SentinelEdge Architecture

This document gives a high-level view of the current MVP architecture and the next device/agent loop.

## Current MVP Architecture

```mermaid
flowchart LR
    Flutter[Flutter Web App] --> Firebase[Firebase Auth]
    Firebase --> Flutter
    Flutter --> Backend[FastAPI Backend]
    Backend --> FirebaseAdmin[Firebase Admin SDK]
    FirebaseAdmin --> Firebase
    Backend --> Database[(SQLite local / PostgreSQL target)]
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

## Milestone 4 Target Loop

```mermaid
flowchart LR
    Flutter[Flutter Web App] --> Backend[FastAPI Backend]
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
