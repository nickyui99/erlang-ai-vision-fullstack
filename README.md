# SentinelEdge Fullstack

SentinelEdge is a surveillance backend and edge-integration project spanning a FastAPI backend and a Flutter app. It covers user auth, device and agent management, edge event ingestion, media metadata, realtime updates, two-axis camera control, and push alerts — backed by SQLAlchemy models, Alembic migrations, and the documentation under `docs/`.

## Current Status

Milestones 1 through 8.5 are complete:

- FastAPI app scaffold
- environment-based configuration
- async SQLAlchemy engine
- SQLite local database support
- SQLite foreign key enforcement
- SQLAlchemy declarative base
- Alembic migration scaffold
- health/readiness/version endpoints
- Dockerfile and docker-compose skeleton
- demo SQLite database and generation scripts
- SQLAlchemy ORM models for all core MVP tables
- initial Alembic migration for the core schema
- ownership indexes and idempotency constraints
- Firebase Google sign-in through the Flutter frontend
- Firebase ID token verification in the backend
- backend session cookie authentication
- current-user and logout endpoints
- edge-token hashing and authentication dependency
- device registration, heartbeat, and agent arm/disarm loop
- edge event ingestion with idempotency and clip/recording metadata
- realtime updates over SSE (`event.created`, `clip.available`, `device.health_changed`, `alert.created`)
- edge command relay over WebSocket: two-axis SG90 gimbal control (pan + tilt) and live snapshot
- Firebase Cloud Messaging (FCM) push alerts for high-severity events (Milestone 8)
- Flutter smart-camera UX pass: camera-first dashboard, live/snapshot control surface, quick actions, PTZ controller, protection toggles, and event timeline (Milestone 8.5)

Implemented HTTP endpoints:

- `GET /healthz`
- `GET /readyz`
- `GET /api/v1/version`
- `POST /api/v1/auth/firebase/login`
- `POST /api/v1/auth/logout`
- `GET /api/v1/users/me`
- `POST /api/v1/devices`
- `GET /api/v1/devices`
- `GET /api/v1/devices/{device_id}`
- `PUT /api/v1/devices/{device_id}`
- `POST /api/v1/devices/{device_id}/pan`
- `POST /api/v1/devices/{device_id}/tilt`
- `POST /api/v1/devices/{device_id}/snapshot`
- `POST /api/v1/devices/{device_id}/stream-url`
- `GET /api/v1/devices/{device_id}/stream`
- `POST /api/v1/agents`
- `GET /api/v1/agents`
- `GET /api/v1/agents/{agent_id}`
- `PUT /api/v1/agents/{agent_id}`
- `POST /api/v1/agents/{agent_id}/arm`
- `POST /api/v1/agents/{agent_id}/disarm`
- `POST /api/v1/edge/heartbeat`
- `GET /api/v1/edge/agents/active`
- `POST /api/v1/edge/events`
- `POST /api/v1/edge/clips/upload-url`
- `POST /api/v1/edge/clips/{clip_id}/complete`
- `POST /api/v1/edge/recordings`
- `GET /api/v1/events`
- `GET /api/v1/events/{event_id}`
- `GET /api/v1/events/{event_id}/clips`
- `POST /api/v1/clips/{clip_id}/signed-url`
- `POST /api/v1/notifications/tokens`
- `DELETE /api/v1/notifications/tokens/{token}`
- `GET /api/v1/stream/events`
- `GET /api/v1/system/network`
- `WS /api/v1/edge/ws`
- `WS /api/v1/edge/stream`

Remaining work is tracked in later milestones: Flutter push-notification registration and native camera affordances, Qwen verification, MCP tooling, retention, and deployment.

## Repository Layout

```text
backend/
  app/
    api/
    core/
    db/
      migrations/
    models/
    main.py
  alembic.ini
  Dockerfile
  docker-compose.yml
  requirements.txt

frontend/
  sentineledge_app/
    lib/
    config/
      firebase.example.json
    pubspec.yaml

data/
  sentineledge_demo.db

docs/
  backend/
    api_endpoints.md
    architecture.md
    auth_flow.md
    backend_setup.md
    database_erd.md
    edge_integration.md
    media_storage.md
    mvp_checklist.md
    sentineledge_backend_implementation_plan.md
  frontend/
    frontend_setup.md

scripts/
  demo_sqlite_schema.sql
  generate_demo_sqlite.py
  inspect_demo_sqlite.py
```

## Local Setup

Install backend dependencies:

```powershell
pip install -r backend\requirements.txt
```

Create a local `.env` from the example:

```powershell
Copy-Item .env.example .env
```

Default local database URL:

```env
DATABASE_URL=sqlite+aiosqlite:///./data/sentineledge_demo.db
```

Set up the Flutter frontend:

```powershell
cd frontend\sentineledge_app
Copy-Item config\firebase.example.json config\firebase.json
flutter run -d web-server --web-port 8080 --dart-define-from-file=config/firebase.json
```

See [Frontend setup](docs/frontend/frontend_setup.md) for Firebase config details, backend URL overrides, and validation steps.

## Demo SQLite Database

Regenerate the demo database:

```powershell
python scripts\generate_demo_sqlite.py
```

Inspect the demo database:

```powershell
python scripts\inspect_demo_sqlite.py
```

Expected seed tables:

```text
users
devices
agents
events
clips
recordings
alerts
push_tokens
tool_audit
```

## Run Backend Locally

From the repository root:

```powershell
$env:PYTHONPATH="backend"
uvicorn app.main:app --reload
```

Health endpoints:

```text
GET http://localhost:8000/healthz
GET http://localhost:8000/readyz
GET http://localhost:8000/api/v1/version
```

Auth endpoints:

```text
POST http://localhost:8000/api/v1/auth/firebase/login
POST http://localhost:8000/api/v1/auth/logout
GET  http://localhost:8000/api/v1/users/me
```

Device, agent, edge loop, camera control, and notification endpoints:

```text
POST   http://localhost:8000/api/v1/devices
GET    http://localhost:8000/api/v1/devices
GET    http://localhost:8000/api/v1/devices/{device_id}
PUT    http://localhost:8000/api/v1/devices/{device_id}
POST   http://localhost:8000/api/v1/devices/{device_id}/pan
POST   http://localhost:8000/api/v1/devices/{device_id}/tilt
POST   http://localhost:8000/api/v1/devices/{device_id}/snapshot
POST   http://localhost:8000/api/v1/agents
GET    http://localhost:8000/api/v1/agents
GET    http://localhost:8000/api/v1/agents/{agent_id}
PUT    http://localhost:8000/api/v1/agents/{agent_id}
POST   http://localhost:8000/api/v1/agents/{agent_id}/arm
POST   http://localhost:8000/api/v1/agents/{agent_id}/disarm
POST   http://localhost:8000/api/v1/edge/heartbeat
GET    http://localhost:8000/api/v1/edge/agents/active
POST   http://localhost:8000/api/v1/notifications/tokens
DELETE http://localhost:8000/api/v1/notifications/tokens/{token}
```

Pan and tilt drive the two SG90 servos of the camera gimbal (each `0–180°`, centered at `90°`); the edge reports `current_pan` and `current_tilt` back through the heartbeat. Push alerts are delivered via Firebase Cloud Messaging — register a client's FCM token with `POST /api/v1/notifications/tokens`, and the backend pushes a notification when the edge submits an event at or above `ALERT_MIN_SEVERITY` (default `high`).

## Live Video (Push Relay)

The edge device pushes JPEG frames to the backend over a WebSocket; the backend
fans them out to browser viewers as MJPEG. This works through home NAT because
the device makes the outbound connection — no inbound port or public camera IP.

```text
ESP32-CAM  ──WS binary JPEG──>  backend broker  ──MJPEG──>  Flutter <img>
(WS /api/v1/edge/stream)        (in-memory)      (GET /api/v1/devices/{id}/stream)
```

- Device side: connect to `WS /api/v1/edge/stream` with `Authorization: Bearer <edge_token>` and send one JPEG per binary message.
- Frontend: `POST /api/v1/devices/{device_id}/stream-url` mints a short-lived signed URL (a query-string token is used because a cross-origin `<img>` does not carry the session cookie), which the camera control screen feeds to the live view when the camera is `online`.

### Test live video locally (no hardware)

Register a device in the app and copy its `edge_token` from the "Device edge
token" dialog, then run the simulator — it pretends to be an ESP32-CAM, sends
heartbeats (so the camera shows online), and pushes an animated test pattern.
Only the edge token is needed; the backend identifies the device from it.

```powershell
pip install websockets pillow
python scripts\stream_simulator.py --edge-token se_edge_xxx
```

Open that camera in the Flutter app and the live view shows the moving pattern.

### Test with a real USB camera bridge

To drive the live view from an actual ESP32 over USB instead of the simulator,
use the device-tier bridge in `SentinelEdge_IOT/`. The bridge forwards the
camera's frames into `WS /api/v1/edge/stream` exactly like the simulator, so the
backend and frontend are unchanged.

1. In the app, **Cameras → Add camera**, and copy the `edge_token` from the
   "Device edge token" dialog.
2. In `SentinelEdge_IOT/`, flash the USB-CDC build and run the bridge pointed at
   this backend with that token:

   ```powershell
   cd SentinelEdge_IOT\firmware
   pio run -e usb_stream -t upload
   cd ..\receiver
   python edge_bridge.py --serial-port COM5 `
       --api-base-url http://localhost:8000 --edge-token se_edge_xxx
   ```

3. Open that camera in the app — the live view shows the USB camera, and the
   heartbeat flips it to `online`.

For isolating the device→bridge hop, the bridge also serves a direct preview at
`http://localhost:8766/video.mjpg` (and `/health`, `/snapshot.jpg`). See
`SentinelEdge_IOT/README.md` → "Testing the stream end to end" and
`SentinelEdge_IOT/docs/USB_PIVOT_PLAN.md` for the USB transport design.

### Pair a real camera (QR onboarding)

The app's **Cameras → Add camera** wizard is a market-style flow: name the
camera, enter Wi-Fi + the receiver (laptop) address, then a pairing QR is shown
for the ESP32 camera to scan with its own lens. The QR carries Wi-Fi + the
laptop/bridge address (LAN IP pre-filled from `GET /api/v1/system/network`,
port `8765`); the edge token is shown separately to start the bridge — it is not
in the QR. The device firmware (QR provisioning) and the bridge live in the
device-tier repo `SentinelEdge_IOT/` (`firmware/` + `receiver/edge_bridge.py`),
which forwards the camera's frames into this backend's `/api/v1/edge/stream`.

Firebase Auth is used for Google login. The frontend signs in with Firebase, gets a Firebase ID token, and sends it to the backend:

```http
POST /api/v1/auth/firebase/login
Authorization: Bearer <firebase_id_token>
```

Backend Firebase settings:

```env
FIREBASE_PROJECT_ID=your-firebase-project-id
GOOGLE_APPLICATION_CREDENTIALS=C:\path\to\firebase-service-account.json
```

The backend verifies the Firebase ID token, creates or updates a local `users` row, and sets the SentinelEdge session cookie.

Interactive docs are available in development:

```text
http://localhost:8000/docs
```

## Run Full Stack Locally

Start the backend and Flutter web frontend together:

```powershell
.\scripts\start-dev.ps1
```

The script opens one PowerShell window for FastAPI and one for Flutter web-server, then opens `http://localhost:8080` in your default browser. Using web-server lets you reuse your normal browser profile, which reduces repeated Google security-code prompts during login.

It expects:

- backend `.env` at the repository root
- frontend Firebase config at `frontend\sentineledge_app\config\firebase.json`

Optional arguments:

```powershell
.\scripts\start-dev.ps1 -BackendPort 8000 -FlutterPort 8080
.\scripts\start-dev.ps1 -FlutterDevice edge -OpenBrowser:$false
```

## Alembic

Check current migration state:

```powershell
alembic -c backend\alembic.ini current
```

Render migration SQL without changing the database:

```powershell
alembic -c backend\alembic.ini upgrade head --sql
```

Apply migrations:

```powershell
alembic -c backend\alembic.ini upgrade head
```

For local testing, prefer a throwaway database outside OneDrive:

```powershell
$env:DATABASE_URL="sqlite+aiosqlite:///C:/tmp/sentineledge_m2_test.db"
alembic -c backend\alembic.ini upgrade head
```

Generate future migrations after model changes:

```powershell
alembic -c backend\alembic.ini revision --autogenerate -m "message"
```

## Backend Docs

Start with:

- [Backend setup](docs/backend/backend_setup.md)
- [Architecture](docs/backend/architecture.md)
- [API endpoints](docs/backend/api_endpoints.md)
- [Database ERD](docs/backend/database_erd.md)
- [Auth flow](docs/backend/auth_flow.md)
- [Edge integration](docs/backend/edge_integration.md)
- [Media storage](docs/backend/media_storage.md)
- [MVP checklist](docs/backend/mvp_checklist.md)

## Frontend Docs

- [Frontend setup](docs/frontend/frontend_setup.md)
- [Flutter app README](frontend/sentineledge_app/README.md)

## Milestone 2 Validation

Check that SQLAlchemy sees all core tables:

```powershell
$env:PYTHONDONTWRITEBYTECODE="1"
$env:PYTHONPATH="backend"
python -c "import app.models; from app.db.base import Base; print(sorted(Base.metadata.tables.keys()))"
```

Expected tables:

```text
agents
alerts
clips
devices
events
push_tokens
recordings
tool_audit
users
```

## Milestone 3 Validation

Unauthenticated user check:

```powershell
Invoke-RestMethod http://localhost:8000/api/v1/users/me
```

Expected result without a session is `401 not_authenticated`.

Firebase login configuration check:

```powershell
Invoke-RestMethod -Method Post http://localhost:8000/api/v1/auth/firebase/login
```

Expected result without a bearer token is `401 not_authenticated`. With a fake bearer token and missing Firebase settings, expected result is `503 firebase_not_configured`.

Milestone 3 is complete when Firebase Google login succeeds from the Flutter app and `/api/v1/users/me` returns the current user using the backend session cookie.

## Milestone 4 Validation

Milestone 4 covers the first device and agent loop after login: register a device, receive the raw edge token once, create and arm an agent, send an edge heartbeat, and pull active edge configs.

Register a device with an authenticated browser session cookie:

```powershell
Invoke-RestMethod -Method Post http://localhost:8000/api/v1/devices -ContentType 'application/json' -Body '{"name":"Front Door Camera","location":"Front Door"}' -WebSession $session
```

Save the returned `edge_token`, then send heartbeat as the edge service:

```powershell
Invoke-RestMethod -Method Post http://localhost:8000/api/v1/edge/heartbeat -Headers @{ Authorization = "Bearer <edge_token>" } -ContentType 'application/json' -Body '{"health_status":"online","rssi":-58.2,"fps":15.0,"current_pan":90,"current_tilt":90}'
```

Create and arm an agent for the device:

```powershell
Invoke-RestMethod -Method Post http://localhost:8000/api/v1/agents -ContentType 'application/json' -Body '{"device_id":"<device_id>","name":"Night Front Door Watch","location":"Front Door","nl_rule":"Alert me if a person is lingering near the front door after 10 PM."}' -WebSession $session
Invoke-RestMethod -Method Post http://localhost:8000/api/v1/agents/<agent_id>/arm -WebSession $session
```

Pull active configs as the edge service:

```powershell
Invoke-RestMethod http://localhost:8000/api/v1/edge/agents/active -Headers @{ Authorization = "Bearer <edge_token>" }
```

## Next Milestone

Milestone 8 (alert loop) is complete, delivered as Firebase Cloud Messaging push:

- alert service interface (`backend/app/services/alert_service.py`)
- first alert adapter - FCM push (`backend/app/services/notification_service.py`)
- duplicate alerts suppressed per event + channel
- alert delivery results stored on `alerts.status`
- alert status pushed through SSE (`alert.created`)

Milestone 8.5 (Flutter smart-camera UX) is complete:

- Cameras are now the primary frontend tab.
- Device rows are replaced with smart-camera style cards.
- The camera control screen now has a live/snapshot surface, quick action dock, circular PTZ control, favorite position chips, protection toggles, and recent activity.
- Event review now uses a camera-app timeline, with technical event IDs and stage output behind an expander.
- Unsupported market-style actions remain visible but disabled until backend APIs exist: recording, mute, talk, alarm, fill light, resolution switching, fullscreen stream, presets, and PTZ correction.

Milestone 9 is next - AI verification and the MCP tool layer:

- add the Qwen client wrapper and verification schema
- validate or repair model output and store `stage3_verdict`
- add MCP tool permissions and audit logging
- enforce pan/tilt limits and high-risk tool rules

Remaining parallel frontend work:

- register FCM tokens from Flutter and display push notifications
- add backend + UI support for recording, audio mute/talk, alarm, fill light, resolution switching, fullscreen live video, presets, and PTZ correction
- live video is delivered as an MJPEG push relay (see "Live Video"); remaining: fullscreen surface and resolution switching
- run mobile/emulator visual QA for the camera screens
