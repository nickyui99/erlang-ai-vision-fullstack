# SentinelEdge Fullstack

SentinelEdge Fullstack contains the FastAPI backend and Flutter app for the SentinelEdge camera product. It owns users, devices, agent definitions, camera assignment, live video fan-out, edge command relay, event/media metadata, push alerts, and Qwen Cloud verification.

The physical camera firmware and local AI edge runtime live in sibling repos:

- `SentinelEdge_IOT`: ESP32-S3 camera firmware, QR provisioning, Wi-Fi/USB transports, pan/tilt firmware.
- `SentinelEdge_LaptopEdge`: laptop bridge and local detection pipeline, including YOLO video detection, optional YAMNet audio detection, and Ollama Qwen local triage.

## Current Architecture

```text
Flutter app
  -> FastAPI backend (this repo)
      - auth/session/device/agent APIs
      - live MJPEG stream broker
      - edge command relay over WebSocket
      - event/media/alert persistence
      - Qwen Cloud verification + MCP-style tools
  <- Laptop edge bridge (SentinelEdge_LaptopEdge)
      - receives ESP32 frames/health/commands
      - runs YOLO/YAMNet/Ollama local pipeline
      - posts candidate events and media metadata
  <- ESP32 camera firmware (SentinelEdge_IOT)
      - captures JPEG frames
      - scans pairing QR for Wi-Fi + bridge address
      - drives pan/tilt servos
```

The backend never talks directly to a LAN camera. The edge bridge keeps outbound connections open to the backend and relays commands to the camera.

## Implemented Backend Features

- Firebase Google login with backend session cookie.
- Device registration with one-time edge token display.
- Device list/detail/update/delete.
- Agent definition creation/update and per-camera assignment/unassignment.
- Active edge config pull for assigned/armed camera agents.
- Edge heartbeats with health, RSSI, FPS, pan, and tilt.
- Edge event ingestion with idempotency.
- Clip upload-url and completion metadata flow.
- Recording metadata ingestion.
- Live video push: edge sends binary JPEG frames to `WS /api/v1/edge/stream`; clients view signed MJPEG/frame URLs.
- User-facing pan, tilt, and snapshot commands relayed through `WS /api/v1/edge/ws`.
- Realtime SSE for device/event/clip/alert updates.
- Firebase Cloud Messaging push-token registration and high-severity alert delivery.
- Qwen Cloud verification for qualifying events with audited tools: live snapshot, pan camera, device status, recent events/clips.

## Current API Surface

Core:

- `GET /healthz`
- `GET /readyz`
- `GET /api/v1/version`
- `POST /api/v1/auth/firebase/login`
- `POST /api/v1/auth/logout`
- `GET /api/v1/users/me`

Devices:

- `POST /api/v1/devices`
- `GET /api/v1/devices`
- `GET /api/v1/devices/{device_id}`
- `PUT /api/v1/devices/{device_id}`
- `DELETE /api/v1/devices/{device_id}`
- `POST /api/v1/devices/{device_id}/pan` with angle `0..180`
- `POST /api/v1/devices/{device_id}/tilt` with angle `60..140`
- `POST /api/v1/devices/{device_id}/snapshot`
- `POST /api/v1/devices/{device_id}/stream-url`
- `GET /api/v1/devices/{device_id}/stream`
- `GET /api/v1/devices/{device_id}/stream-frame`

Agents:

- `POST /api/v1/agents`
- `GET /api/v1/agents`
- `GET /api/v1/agents/{agent_id}`
- `PUT /api/v1/agents/{agent_id}`
- `POST /api/v1/agents/{agent_id}/assign`
- `POST /api/v1/agents/{agent_id}/unassign`

Edge:

- `POST /api/v1/edge/heartbeat`
- `GET /api/v1/edge/agents/active`
- `POST /api/v1/edge/events`
- `POST /api/v1/edge/clips/upload-url`
- `POST /api/v1/edge/clips/{clip_id}/complete`
- `POST /api/v1/edge/recordings`
- `WS /api/v1/edge/ws`
- `WS /api/v1/edge/stream`

Events/media/realtime:

- `GET /api/v1/events`
- `GET /api/v1/events/{event_id}`
- `GET /api/v1/events/{event_id}/clips`
- `GET /api/v1/events/{event_id}/audit`
- `POST /api/v1/clips/{clip_id}/signed-url`
- `POST /api/v1/notifications/tokens`
- `DELETE /api/v1/notifications/tokens/{token}`
- `GET /api/v1/stream/events`
- `GET /api/v1/system/network`

Interactive OpenAPI docs are available at `http://localhost:8000/docs` in development.

## Repository Layout

```text
backend/
  app/
    api/v1/          FastAPI routes
    core/            settings, security, middleware
    db/              async SQLAlchemy session + Alembic migrations
    models/          ORM models
    schemas/         Pydantic request/response models
    services/        command hub, video broker, alerts, verification
    mcp/             in-process tool registry and permissions
  alembic.ini
  requirements.txt

frontend/sentineledge_app/
  lib/               Flutter app
  config/            firebase.example.json / firebase.json

data/
  sentineledge_demo.db

docs/
  backend/
  frontend/

scripts/
  generate_demo_sqlite.py
  inspect_demo_sqlite.py
  simulate_event.py
  stream_simulator.py
  verify_smoke.py
  start-dev.ps1
```

## Local Setup

Install backend dependencies:

```powershell
pip install -r backend\requirements.txt
```

Create a local environment file:

```powershell
Copy-Item .env.example .env
```

Default local database URL:

```env
DATABASE_URL=sqlite+aiosqlite:///./data/sentineledge_demo.db
```

Run the backend from the repository root:

```powershell
$env:PYTHONPATH="backend"
uvicorn app.main:app --reload
```

Run the Flutter web app:

```powershell
cd frontend\sentineledge_app
Copy-Item config\firebase.example.json config\firebase.json
flutter run -d web-server --web-port 8080 --dart-define-from-file=config/firebase.json
```

Or start both backend and Flutter web together:

```powershell
.\scripts\start-dev.ps1
```

## Demo Database

Regenerate the demo SQLite database:

```powershell
python scripts\generate_demo_sqlite.py
```

Inspect it:

```powershell
python scripts\inspect_demo_sqlite.py
```

Expected core tables include:

```text
users devices agents events clips recordings alerts push_tokens tool_audit
```

Note: `data/sentineledge_demo.db` is local runtime data. Do not commit changes to it unless you intentionally changed seed data.

## Live Camera Flow

For a real camera demo, run all three tiers:

1. Backend and Flutter app from this repo.
2. Edge console/bridge from `SentinelEdge_LaptopEdge` in `Real ESP32 WiFi` mode.
3. ESP32 firmware from `SentinelEdge_IOT`, usually the `xiao_s3` Wi-Fi build.

The app creates/registers a camera and shows the one-time edge token. The edge bridge uses that token to connect to this backend, forward frames to `WS /api/v1/edge/stream`, keep `WS /api/v1/edge/ws` open for commands, and post detected events.

The live view uses `POST /api/v1/devices/{device_id}/stream-url` to mint a short-lived signed URL for MJPEG (`/stream`) or latest-frame polling (`/stream-frame`).

## Local AI Detection

Automatic detection is not in this Fullstack repo. It is implemented by `SentinelEdge_LaptopEdge`:

- YOLO video detection for `person` and other object labels.
- Optional YAMNet audio detection when audio frames are available.
- Ollama `qwen3.5:0.8b` local VLM triage before events are posted to this backend.

This backend stores agent rules and exposes assigned active configs through `GET /api/v1/edge/agents/active`. The current rule compiler is intentionally simple: it compiles rules to a person detector config with `min_confidence: 0.75`. Richer natural-language rule compilation is still future work.

## Qwen Cloud Verification

After the edge posts a qualifying event, the backend can run Qwen Cloud verification. The verifier may call audited tools to fetch a live snapshot, pan the camera, read device status, and inspect recent events/clips. Results are stored in `events.stage3_verdict`; tool calls are stored in `tool_audit` and exposed via `GET /api/v1/events/{event_id}/audit`.

Enable in `.env`:

```env
VERIFICATION_ENABLED=true
QWEN_API_KEY=sk-...
```

Without a key, tests and local smoke flows can use deterministic mock behavior.

To submit a local test event:

```powershell
$env:PYTHONPATH="backend"
python scripts\simulate_event.py
python scripts\simulate_event.py --severity high --count 3 --interval 4
```

To smoke-test verification:

```powershell
python scripts\verify_smoke.py
```

## Alembic

Check migration state:

```powershell
alembic -c backend\alembic.ini current
```

Apply migrations:

```powershell
alembic -c backend\alembic.ini upgrade head
```

Generate future migrations after model changes:

```powershell
alembic -c backend\alembic.ini revision --autogenerate -m "message"
```

For throwaway local tests, point SQLite outside OneDrive:

```powershell
$env:DATABASE_URL="sqlite+aiosqlite:///C:/tmp/sentineledge_test.db"
alembic -c backend\alembic.ini upgrade head
```

## Documentation

Start with:

- [Backend setup](docs/backend/backend_setup.md)
- [Backend architecture](docs/backend/architecture.md)
- [API endpoints](docs/backend/api_endpoints.md)
- [Edge integration](docs/backend/edge_integration.md)
- [Media storage](docs/backend/media_storage.md)
- [Frontend setup](docs/frontend/frontend_setup.md)
- [Flutter app README](frontend/sentineledge_app/README.md)

## Remaining Work

- Replace the simple `_compile_agent_rule` stub with real natural-language rule compilation.
- Add production retention and cleanup jobs.
- Replace placeholder/local media URL handling with real OSS deployment settings.
- Complete Flutter push notification registration and native/mobile QA.
- Keep backend docs in sync with the separate LaptopEdge and IOT repos as their contracts evolve.
