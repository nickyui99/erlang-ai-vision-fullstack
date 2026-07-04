# SentinelEdge Backend Implementation Plan

## 1. Purpose

This document defines the implementation plan for the SentinelEdge backend. The backend is a FastAPI-based service deployed as a Docker container on Alibaba Cloud Elastic Container Instance (ECI). It provides APIs for users, devices, agents, events, clips, recordings, alerts, MCP tools, AI verification, and real-time client updates.

The backend is responsible for:

- User authentication and authorization
- Device and edge-client registration
- Agent CRUD and compiled rule management
- Event ingestion from the laptop edge tier
- Clip and recording metadata management
- Alibaba OSS upload/download reference handling
- Qwen Cloud verification orchestration
- MCP tool server for AI-controlled actions
- Alert dispatch through configured channels
- WebSocket/SSE updates to the web app and mobile WebView wrapper
- Audit logging for AI and user-triggered tool actions

---

## 2. Backend Scope

### In scope

- FastAPI backend application
- Relational database schema and migrations, starting with SQLite locally and targeting PostgreSQL for production
- SQLAlchemy ORM models
- Pydantic request/response schemas
- Firebase Google sign-in for users
- API token authentication for edge clients
- REST API routes
- WebSocket endpoint for laptop edge tier
- SSE endpoint for web/mobile clients
- Alibaba OSS integration
- Qwen API integration
- MCP tool server
- Notification service abstraction
- Docker deployment to Alibaba Cloud ECI

### Out of scope for initial backend MVP

- Full native mobile backend API
- Long-term cloud storage of continuous raw video
- Advanced multi-tenant organization hierarchy
- Complex autoscaling
- Native mobile push bridge
- Production-grade billing or subscription management

---

## 3. Recommended Backend Stack

| Layer | Technology |
|---|---|
| API framework | FastAPI |
| Language | Python 3.11+ |
| ORM | SQLAlchemy 2.x |
| Migration | Alembic |
| Validation | Pydantic v2 |
| Initial database | SQLite for local/MVP foundation |
| Production database | PostgreSQL / ApsaraDB for PostgreSQL |
| Object storage | Alibaba Cloud OSS |
| AI service | Qwen APIs through Alibaba Cloud Model Studio / DashScope |
| Agent orchestration | Qwen-Agent |
| Tool protocol | MCP-compatible tool layer |
| Auth | Firebase Auth for users, API token for edge clients |
| Deployment | Docker container on Alibaba Cloud ECI |
| Local development | Docker Compose |

---

## 4. Backend Architecture

```text
Web App / Mobile WebView
        |
        | HTTPS REST + SSE
        v
FastAPI Backend on Alibaba Cloud ECI
        |
        | SQLAlchemy
        v
PostgreSQL / ApsaraDB

Initial local development can use SQLite through the same SQLAlchemy model layer. PostgreSQL remains the production target for Alibaba Cloud deployment.

Laptop Edge Service
        |
        | HTTPS REST + WSS
        v
FastAPI Backend on Alibaba Cloud ECI
        |
        +--> Alibaba OSS
        +--> Qwen API
        +--> Notification Channels
        +--> MCP Tool Runtime
```

---

## 5. Repository Structure

```text
backend/
├── app/
│   ├── main.py
│   ├── core/
│   │   ├── config.py
│   │   ├── security.py
│   │   ├── logging.py
│   │   └── errors.py
│   ├── db/
│   │   ├── session.py
│   │   ├── base.py
│   │   └── migrations/
│   ├── models/
│   │   ├── user.py
│   │   ├── device.py
│   │   ├── agent.py
│   │   ├── event.py
│   │   ├── clip.py
│   │   ├── recording.py
│   │   ├── alert.py
│   │   └── tool_audit.py
│   ├── schemas/
│   │   ├── auth.py
│   │   ├── device.py
│   │   ├── agent.py
│   │   ├── event.py
│   │   ├── clip.py
│   │   ├── recording.py
│   │   ├── alert.py
│   │   └── tool.py
│   ├── api/
│   │   ├── deps.py
│   │   └── v1/
│   │       ├── router.py
│   │       ├── auth.py
│   │       ├── users.py
│   │       ├── devices.py
│   │       ├── agents.py
│   │       ├── events.py
│   │       ├── clips.py
│   │       ├── recordings.py
│   │       ├── alerts.py
│   │       ├── tools.py
│   │       ├── edge.py
│   │       └── health.py
│   ├── services/
│   │   ├── auth_service.py
│   │   ├── user_service.py
│   │   ├── device_service.py
│   │   ├── agent_service.py
│   │   ├── event_service.py
│   │   ├── clip_service.py
│   │   ├── recording_service.py
│   │   ├── storage_service.py
│   │   ├── qwen_service.py
│   │   ├── notification_service.py
│   │   ├── sse_service.py
│   │   └── audit_service.py
│   ├── agents/
│   │   ├── compiler.py
│   │   ├── runtime.py
│   │   └── prompts.py
│   ├── mcp/
│   │   ├── server.py
│   │   ├── tools.py
│   │   ├── permissions.py
│   │   └── relay.py
│   └── workers/
│       ├── verification_worker.py
│       ├── alert_worker.py
│       └── cleanup_worker.py
├── alembic.ini
├── Dockerfile
├── requirements.txt
├── docker-compose.yml
├── .env.example
└── README.md
```

---

## 6. Implementation Phases

## Phase 1 — Backend Foundation

### Goal

Create the FastAPI backend skeleton, configuration system, SQLite database connection, health checks, and a Docker-ready application structure.

### Tasks

1. Create FastAPI project structure.
2. Add environment-based configuration.
3. Add SQLite database session handling for the initial local backend.
4. Add SQLAlchemy base model setup.
5. Add Alembic migration support using SQLite locally, while keeping migrations compatible with PostgreSQL where practical.
6. Add standard API response and error format.
7. Add `/healthz` and `/readyz` endpoints.
8. Add Dockerfile.
9. Add local `docker-compose.yml` only if needed for app runtime; PostgreSQL is not required in Phase 1.
10. Add `.env.example`.

### Initial database choice

Phase 1 should use SQLite to reduce setup friction and allow the backend foundation to run without a separate database container.

Recommended local database URL:

```env
DATABASE_URL=sqlite+aiosqlite:///./sentineledge.db
```

Implementation notes:

- Use SQLAlchemy's async engine with `sqlite+aiosqlite` in local development.
- Keep model definitions database-portable and avoid SQLite-only behavior in application logic.
- Enable SQLite foreign key enforcement on connection.
- Use Alembic migrations from the start so the later PostgreSQL migration path remains controlled.
- Treat SQLite as a development/MVP foundation database, not the final ECI production database.

### Endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/healthz` | Basic process health |
| GET | `/readyz` | Backend readiness check |
| GET | `/api/v1/version` | Backend version info |

### Acceptance criteria

- Backend runs locally with `uvicorn`.
- Backend runs inside Docker without requiring PostgreSQL.
- SQLite database connection works.
- Alembic can generate and run migrations.
- `/healthz` returns `200 OK`.
- `/readyz` validates SQLite availability.

---

## Phase 2 — Data Model and Migrations

### Goal

Implement the full SentinelEdge data model.

### Tables

- `users`
- `devices`
- `agents`
- `events`
- `clips`
- `recordings`
- `alerts`
- `tool_audit`

### Important model rules

- Video binary files are never stored in the relational database.
- `clips` stores event clip metadata and storage references.
- `recordings` stores daily or continuous recording segment metadata and storage references.
- `user_id` must be used for ownership and authorization.
- `events.user_id` must match the related agent and device owner.
- `clips.user_id` must match the related event owner.
- `recordings.user_id` must match the related device owner.

### Recommended media fields

Both `clips` and `recordings` should include:

- `storage_type`
- `storage_path`
- `oss_object_key`
- `duration_seconds`
- `file_size_bytes`
- `mime_type`
- `checksum_sha256`
- `status`
- `created_at`
- `updated_at`
- `deleted_at`
- `retention_until` or `expires_at`

### Acceptance criteria

- All tables are created through Alembic migrations.
- Foreign keys are correctly defined.
- Indexes exist for common query fields.
- Ownership fields are included.
- Media tables support local and OSS references.

---

## Phase 3 — Authentication and Authorization

### Goal

Implement secure access for users through Firebase Auth and for laptop edge clients through edge API tokens.

### Auth types

| Actor | Auth method |
|---|---|
| Web app user | Firebase Google sign-in with backend-managed session |
| Mobile WebView user | Firebase Google sign-in through the app |
| Laptop edge service | Edge API token |
| Admin/debug tools | Firebase-authenticated user with admin role |

### Tasks

1. Configure Firebase project ID and service account credentials.
2. Implement Firebase login endpoint.
3. Verify Firebase ID token and hosted user identity.
4. Create or update the local `users` row from Firebase token claims.
5. Issue a backend-managed session cookie after Firebase login succeeds.
6. Implement logout.
7. Implement current-user dependency based on the backend session or app token.
8. Implement role-based authorization.
9. Implement edge API token authentication.
10. Add ownership checks for users, devices, agents, events, clips, recordings, and alerts.

### Endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/api/v1/auth/firebase/login` | Complete Firebase login |
| POST | `/api/v1/auth/logout` | End current user session |
| GET | `/api/v1/users/me` | Current user profile |

### Firebase user mapping

The backend should maintain a local `users` table even though Firebase Auth is the identity broker.

Recommended user fields:

- `id`
- `google_sub`
- `email`
- `email_verified`
- `display_name`
- `avatar_url`
- `role`
- `last_login_at`
- `created_at`
- `updated_at`

The `google_sub` value stores the stable Firebase `uid`. Email can change and should not be the primary identity key.

### Acceptance criteria

- Users cannot access other users' data.
- Edge clients cannot call user-only APIs.
- User APIs reject missing or invalid backend sessions/app tokens.
- Firebase login rejects invalid ID tokens and unverified emails.
- Edge APIs reject missing or invalid API tokens.

---

## Phase 4 — Device APIs

### Goal

Support device registration, health status, and metadata updates.

### Endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/api/v1/devices` | List user devices |
| POST | `/api/v1/devices` | Register device |
| GET | `/api/v1/devices/{device_id}` | Get device detail |
| PUT | `/api/v1/devices/{device_id}` | Update device metadata |
| POST | `/api/v1/devices/{device_id}/heartbeat` | Update device health |
| POST | `/api/v1/devices/{device_id}/pan` | Manual pan request |

### Implementation notes

- User-facing device routes require a valid Firebase-authenticated backend session.
- Edge heartbeat can use edge API token.
- `pan` command should be relayed through the edge WebSocket, not sent directly from cloud to ESP32.
- Pan commands must be rate-limited and audit logged.

### Acceptance criteria

- User can register and list devices.
- Device health updates are stored.
- Offline devices are shown as unhealthy after timeout.
- Manual pan creates a tool audit record.

---

## Phase 5 — Agent APIs

### Goal

Allow users to create and manage natural-language surveillance agents.

### Endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/api/v1/agents` | List agents |
| POST | `/api/v1/agents` | Create agent |
| GET | `/api/v1/agents/{agent_id}` | Get agent |
| PUT | `/api/v1/agents/{agent_id}` | Update agent |
| DELETE | `/api/v1/agents/{agent_id}` | Delete agent |
| POST | `/api/v1/agents/{agent_id}/assign` | Assign agent definition to a camera |
| POST | `/api/v1/agents/{agent_id}/unassign` | Remove agent definition from a camera |
| GET | `/api/v1/agents/active` | Edge pulls active compiled configs |

### Agent compiler output

When an agent is created or updated, the backend should generate:

- `compiled_prompt`
- `compiled_edge_config`
- schedule policy
- escalation policy
- actuation permission policy

### Acceptance criteria

- User can create, edit, arm, and disarm agents.
- Agents are linked to a valid owned device.
- Compiled config is generated and stored.
- Edge client can fetch active configs.

---

## Phase 6 — Event Ingestion APIs

### Goal

Allow the laptop edge tier to submit candidate or verified events.

### Endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/api/v1/events` | Edge submits event |
| GET | `/api/v1/events` | User lists events |
| GET | `/api/v1/events/{event_id}` | User gets event detail |
| PATCH | `/api/v1/events/{event_id}/status` | Update event status |
| POST | `/api/v1/events/{event_id}/dismiss` | User dismisses event |
| POST | `/api/v1/events/{event_id}/false-positive` | Mark false positive |

### Event ingestion payload

The edge service should submit:

- `event_id`
- `agent_id`
- `device_id`
- `timestamp`
- `event_type`
- `stage1_result`
- `stage2_verdict`
- `severity`
- `confidence`
- `summary`
- `degraded`
- `idempotency_key`

### Event lifecycle

```text
candidate
    ↓
local_resolved
    ↓
cloud_pending
    ↓
verified
    ↓
alerted
    ↓
dismissed / false_positive / archived
```

### Acceptance criteria

- Event upload is idempotent.
- Duplicate event uploads do not create duplicate rows.
- Event owner is validated from agent/device ownership.
- Events are queryable by user.
- Event updates are pushed to clients through SSE.

---

## Phase 7 — Clip and Recording APIs

### Goal

Store media metadata, not media binaries, and support playback through authorized references.

### Clip endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/api/v1/clips` | Create clip metadata |
| GET | `/api/v1/events/{event_id}/clips` | List event clips |
| GET | `/api/v1/clips/{clip_id}` | Get clip metadata |
| POST | `/api/v1/clips/{clip_id}/signed-url` | Generate temporary playback URL |
| DELETE | `/api/v1/clips/{clip_id}` | Mark clip deleted |

### Recording endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/api/v1/recordings` | Create recording segment metadata |
| GET | `/api/v1/recordings` | List user recordings |
| GET | `/api/v1/recordings/{recording_id}` | Get recording metadata |
| POST | `/api/v1/recordings/{recording_id}/signed-url` | Generate temporary playback URL if uploaded |
| DELETE | `/api/v1/recordings/{recording_id}` | Mark recording deleted |

### Storage rules

- Local edge video path should be stored as a relative path or storage key.
- OSS object keys should be stored, not permanent signed URLs.
- Signed URLs should be generated only on demand.
- Daily raw recordings should stay local by default.
- Event clips may be uploaded to OSS when escalation or review is needed.
- Retention and deletion status must be tracked.

### Acceptance criteria

- User can view only their own media metadata.
- Backend never stores raw video bytes in the relational database.
- Signed URL generation checks ownership.
- Deleted clips and recordings cannot be played.
- Recording metadata can identify which user and device owns each video segment.

---

## Phase 8 — Alibaba OSS Integration

### Goal

Allow event clips, thumbnails, and selected uploaded recordings to be stored in Alibaba OSS.

### Tasks

1. Add OSS client wrapper.
2. Implement object key generation.
3. Implement signed upload URL generation if direct upload is used.
4. Implement signed playback URL generation.
5. Implement delete object operation.
6. Add retry and error handling.
7. Add storage audit logs.

### Recommended object key patterns

```text
events/{user_id}/{device_id}/{event_id}/clip_{clip_id}.mp4
events/{user_id}/{device_id}/{event_id}/thumb_{clip_id}.jpg
recordings/{user_id}/{device_id}/{yyyy-mm-dd}/{recording_id}.mp4
```

### Acceptance criteria

- Backend can generate short-lived signed playback URLs.
- OSS credentials are not exposed to clients.
- OSS object keys map clearly to users, devices, events, and recordings.
- Failed upload/delete operations are logged.

---

## Phase 9 — Qwen Cloud Verification

### Goal

Use Qwen Cloud models to verify high-severity or uncertain events.

### Tasks

1. Add Qwen API client wrapper.
2. Define verification request schema.
3. Define verification response schema.
4. Add prompt templates.
5. Add timeout and retry policy.
6. Add fallback behavior if Qwen API fails.
7. Store output in `events.stage3_verdict`.
8. Trigger alert decision after verification.

### Verification input

- User rule
- Agent compiled prompt
- Stage 1 detector result
- Stage 2 local verdict
- Keyframe or clip reference
- Device metadata
- Recent related events

### Verification output

```json
{
  "verified": true,
  "confidence": 0.91,
  "severity": "high",
  "summary": "A person appears to be lingering near the front door after the configured time.",
  "recommended_action": "notify",
  "tool_requests": []
}
```

### Acceptance criteria

- Cloud verification can be triggered for selected events.
- Verification result is stored in the event row.
- Invalid AI output is rejected or repaired safely.
- Timeout fallback marks event as degraded or locally verified.

---

## Phase 10 — MCP Tool Server and Tool Relay

### Goal

Allow Qwen-Agent to call approved tools through a controlled MCP-compatible layer.

### Tools

| Tool | Purpose | Autonomy level |
|---|---|---|
| `get_live_snapshot` | Fetch a fresh frame | Allowed for active verification |
| `pan_camera` | Move camera servo | Allowed with strict limits |
| `get_device_status` | Check device status | Allowed |
| `query_recent_events` | Retrieve context | Allowed |
| `get_event_clip` | Fetch clip metadata or signed URL | Allowed with authorization |
| `send_emergency_alert` | Send emergency alert | High severity only |
| `arm_agent` | Arm an agent | User confirmation recommended |
| `disarm_agent` | Disarm an agent | User confirmation required |

### Safety rules

- Maximum 3 automatic pans per event.
- Minimum 5 seconds between automatic pans.
- Servo angle must be clamped between 0 and 180 degrees.
- Tool calls must be audit logged.
- High-risk tools require confirmation or strict severity rules.
- Observed scene text must never override tool policy.

### Acceptance criteria

- Tool calls are permission checked.
- Tool calls are audit logged.
- Pan commands are relayed to the correct edge client.
- Tool failures do not crash verification.

---

## Phase 11 — Edge WebSocket Hub

### Goal

Maintain a bidirectional command and event channel between backend and laptop edge service.

### Endpoint

| Method | Endpoint | Purpose |
|---|---|---|
| WS | `/api/v1/edge/ws` | Edge command/config/event channel |

### Message types

```json
{
  "type": "command.pan_camera",
  "request_id": "cmd_001",
  "device_id": "esp32cam_01",
  "payload": {
    "angle": 90
  }
}
```

```json
{
  "type": "event.config_updated",
  "agent_id": "agt_front_door_night"
}
```

```json
{
  "type": "response.command_result",
  "request_id": "cmd_001",
  "status": "ok"
}
```

### Acceptance criteria

- Edge connects with API token.
- Backend can push config updates.
- Backend can send pan/snapshot commands.
- Edge sends command results.
- Reconnect behavior is supported.

---

## Phase 12 — Client SSE and Realtime Updates

### Goal

Push live event, alert, and status updates to web app and mobile WebView wrapper.

### Endpoint

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/api/v1/stream/events` | SSE event updates |

### Event types

- `event.created`
- `event.verified`
- `event.alerted`
- `device.health_changed`
- `agent.state_changed`
- `clip.available`

### Acceptance criteria

- Web app receives live updates.
- Mobile WebView can receive or gracefully fall back to polling.
- SSE requires the same authenticated user session/app token as the web app.
- User receives only their own updates.

---

## Phase 13 — Alert Service

### Goal

Send alerts through configured channels.

### Channels

- Telegram bot
- Web push or browser notification
- Email
- Local LAN fallback, if available

### Tasks

1. Implement alert service interface.
2. Implement Telegram adapter.
3. Implement email adapter if needed.
4. Add deduplication logic.
5. Store alert status.
6. Push alert status through SSE.

### Acceptance criteria

- Alert is sent for verified high-severity events.
- Duplicate alerts are suppressed.
- Alert failures are stored.
- User can see alert status in event detail.

---

## Phase 14 — Retention, Cleanup, and Privacy Controls

### Goal

Prevent unlimited storage growth and support deletion.

### Tasks

1. Add retention config.
2. Add cleanup worker or scheduled endpoint.
3. Delete expired clips from OSS.
4. Mark local recordings for edge deletion.
5. Store `deleted_at`.
6. Prevent playback after deletion.
7. Keep audit record of deletion.

### Recommended defaults

| Media type | Default retention |
|---|---|
| Daily local recordings | 24–72 hours |
| Event clips | 7 days |
| Emergency clips | 30 days |
| Thumbnails/keyframes | Same as event clip |

### Acceptance criteria

- Expired media is deleted or marked for deletion.
- Deleted media cannot be accessed.
- Retention settings are documented.
- Cleanup failures are logged.

---

## Phase 15 — ECI Deployment

### Goal

Deploy the backend container to Alibaba Cloud Elastic Container Instance.

### Tasks

1. Create production Dockerfile.
2. Build backend image.
3. Push image to container registry.
4. Create ECI container group.
5. Configure environment variables.
6. Configure VPC/security group.
7. Configure public HTTPS ingress.
8. Configure database connection.
9. Configure OSS credentials.
10. Configure Qwen API credentials.
11. Configure health checks.
12. Test REST, WebSocket, and SSE endpoints.

### Required environment variables

```env
APP_ENV=production
APP_NAME=SentinelEdge Backend
API_PREFIX=/api/v1

DATABASE_URL=postgresql+asyncpg://user:password@host:5432/sentineledge

FIREBASE_PROJECT_ID=change-me
GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/firebase-service-account.json
SESSION_SECRET_KEY=change-me
SESSION_COOKIE_NAME=sentineledge_session
SESSION_EXPIRE_MINUTES=1440

EDGE_API_TOKEN=change-me

OSS_ENDPOINT=https://oss-region.aliyuncs.com
OSS_BUCKET=sentineledge-media
OSS_ACCESS_KEY_ID=change-me
OSS_ACCESS_KEY_SECRET=change-me

QWEN_API_KEY=change-me
QWEN_BASE_URL=https://dashscope.aliyuncs.com

SIGNED_URL_TTL_SECONDS=900
MEDIA_RETENTION_DAYS=7
DAILY_RECORDING_RETENTION_HOURS=72
```

### Acceptance criteria

- Container starts successfully on ECI.
- `/healthz` and `/readyz` pass.
- Web app can call API.
- Edge laptop can call API.
- OSS and Qwen integrations work.
- WebSocket and SSE work from deployed environment.

---

## 7. API Summary

| Area | Main endpoints |
|---|---|
| Auth | `/api/v1/auth/firebase/login`, `/api/v1/auth/logout` |
| Users | `/api/v1/users/me` |
| Devices | `/api/v1/devices`, `/api/v1/devices/{id}`, `/api/v1/devices/{id}/heartbeat`, `/api/v1/devices/{id}/pan` |
| Agents | `/api/v1/agents`, `/api/v1/agents/{id}`, `/api/v1/agents/{id}/assign`, `/api/v1/agents/{id}/unassign` |
| Events | `/api/v1/events`, `/api/v1/events/{id}`, `/api/v1/events/{id}/dismiss` |
| Clips | `/api/v1/clips`, `/api/v1/events/{id}/clips`, `/api/v1/clips/{id}/signed-url` |
| Recordings | `/api/v1/recordings`, `/api/v1/recordings/{id}`, `/api/v1/recordings/{id}/signed-url` |
| Edge | `/api/v1/edge/ws`, `/api/v1/edge/stream`, `/api/v1/edge/agents/active` |
| Realtime | `/api/v1/stream/events` |
| Health | `/healthz`, `/readyz` |

---

## 8. Suggested Implementation Order

1. FastAPI skeleton and Docker setup
2. Database models and migrations
3. Authentication and authorization
4. Device APIs
5. Agent APIs
6. Event ingestion
7. Clips and recordings metadata
8. OSS integration
9. SSE updates
10. Edge WebSocket hub
11. Qwen verification
12. MCP tool server
13. Alert service
14. Retention cleanup
15. ECI deployment
16. End-to-end testing

---

## 9. End-to-End Backend Flow

```text
1. User creates an agent in the web app.
2. Backend stores the agent and compiles edge config.
3. Laptop edge pulls active agent configs.
4. ESP32 streams video to laptop edge.
5. Laptop edge runs Stage 1 and Stage 2 detection.
6. Suspicious event is submitted to backend.
7. Backend stores event metadata.
8. Edge uploads or registers clip metadata.
9. Backend optionally verifies event with Qwen Cloud.
10. Qwen-Agent may call MCP tools.
11. Backend relays allowed tool commands to edge.
12. Backend stores final verdict and audit logs.
13. Backend sends alert if needed.
14. Web app and mobile WebView receive realtime update.
15. User reviews event, clip, or recording.
```

---

## 10. Testing Plan

### Unit tests

- Firebase ID token verification and backend session validation
- Ownership checks
- Agent compiler
- Event ingestion validation
- Clip and recording schema validation
- OSS object key generation
- Qwen response validation
- MCP permission checks
- Alert deduplication

### Integration tests

- Firebase Google sign-in to protected API
- Device registration and heartbeat
- Agent creation and config pull
- Edge event upload
- Clip metadata creation
- Signed URL generation
- Qwen verification mock
- MCP tool command relay
- SSE event delivery
- Alert dispatch mock

### Deployment tests

- Docker build
- Local container boot
- ECI deployment
- Database connection
- OSS connection
- Qwen API connection
- WebSocket test
- SSE test
- HTTPS endpoint test

---

## 11. MVP Definition

The backend MVP is complete when:

- A user can log in.
- A user can register a device.
- A user can create and arm an agent.
- The edge laptop can fetch active agent config.
- The edge laptop can submit an event.
- The backend stores the event.
- The backend stores clip metadata.
- The web app can list events.
- The backend can generate a signed URL for a clip.
- The backend can send an alert for a high-severity event.
- The backend is deployed to Alibaba Cloud ECI.
- The deployed backend passes `/healthz` and `/readyz`.

---

### Current MVP status

As of 2026-07-03, the local/backend implementation covers the functional MVP path through Milestones 1-9: auth, device registration, agent assignment, edge event ingestion, media metadata, signed playback URLs, SSE, edge command relay, FCM alert records, Qwen verification, and audited MCP-style tools.

The remaining backend plan work is Milestone 10 / deployment hardening:

- Add a production cleanup job or scheduled endpoint.
- Delete expired OSS objects.
- Mark local-edge recordings for deletion after retention expiry.
- Use the already-provisioned cloud ApsaraDB RDS PostgreSQL instance for SQLite-to-RDS migration verification.
- Validate ECI deployment end to end, including REST, SSE, WebSocket, and health checks.
- Put production HTTPS ingress in front of ECI and validate WSS/SSE behavior.

## 12. Future Improvements

- Native mobile notification bridge
- Organization/team support
- More detailed role-based access control
- Background task queue using Redis or message queue
- Autoscaling beyond single ECI container
- Advanced analytics dashboard
- Fine-grained retention settings per user/device
- WebRTC live streaming instead of MJPEG proxy
- Encrypted local media storage
- Multi-camera event correlation
