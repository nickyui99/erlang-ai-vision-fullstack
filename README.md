# Erlang AI Vision Fullstack

Erlang AI Vision Fullstack contains the FastAPI backend and Flutter web/mobile console for the Erlang AI Vision camera product. The repository and some technical identifiers still use SentinelEdge during the rebrand transition. It owns users, devices, agent definitions, camera assignment, live video fan-out, edge command relay, event/media metadata, push alerts, and Qwen Cloud verification.

The physical camera firmware and local AI edge runtime live in sibling repos:

- `SentinelEdge_IOT`: ESP32-S3 camera firmware, QR provisioning, Wi-Fi/USB transports, pan/tilt firmware.
- `SentinelEdge_LaptopEdge`: laptop bridge and local detection pipeline, including YOLO video detection, optional YAMNet audio detection, and Ollama Qwen local triage.

## Current Architecture

```text
Erlang AI Vision Flutter console
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

- Firebase Google and email/password login with backend session cookie.
- Device registration with one-time edge token display.
- Device list/detail/update/delete.
- Agent definition creation/update and per-camera assignment/unassignment.
- Natural-language agent rule compilation via Qwen Cloud, with a deterministic keyword fallback (no stub — see `app/agents/compiler.py`).
- Conversational AI agent builder (`POST /api/v1/agents/builder`): drafts and refines a rule through chat, then previews its compiled detector config.
- Backend demo camera simulation for the demo/judge account: the backend plays pre-extracted video frames into the live view and triages them with the Qwen-VL API — no laptop edge required (see `app/services/demo_simulator.py`).
- AI assistant chat sessions (`/api/v1/chat/*`).
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
- `POST /api/v1/devices/{device_id}/control`
- `POST /api/v1/devices/{device_id}/stream-url`
- `GET /api/v1/devices/{device_id}/stream`
- `GET /api/v1/devices/{device_id}/stream-frame`
- `GET /api/v1/devices/{device_id}/clips`
- `GET /api/v1/devices/{device_id}/recordings`

Agents:

- `POST /api/v1/agents`
- `GET /api/v1/agents`
- `GET /api/v1/agents/{agent_id}`
- `PUT /api/v1/agents/{agent_id}`
- `POST /api/v1/agents/{agent_id}/assign`
- `POST /api/v1/agents/{agent_id}/unassign`
- `POST /api/v1/agents/builder` — conversational rule builder (one chat turn -> reply + proposed rule + compiled preview)

Chat (AI assistant):

- `POST /api/v1/chat/sessions`
- `GET /api/v1/chat/sessions`
- `POST /api/v1/chat/sessions/{session_id}/messages`
- `GET /api/v1/chat/sessions/{session_id}/messages`
- `DELETE /api/v1/chat/sessions/{session_id}`

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
- `POST /api/v1/clips/{clip_id}/download-url`
- `POST /api/v1/recordings/{recording_id}/signed-url`
- `POST /api/v1/notifications/tokens`
- `DELETE /api/v1/notifications/tokens/{token}`
- `GET /api/v1/stream/events`
- `GET /api/v1/system/network`

Health (also mounted at the root, without the `/api/v1` prefix): `GET /healthz`, `GET /readyz`, `GET /version`.

All datetimes in API responses are serialized as UTC with a trailing `Z`, so clients render correct local time regardless of the storage backend (SQLite drops tz info; the API normalizes it).

Interactive OpenAPI docs are available at `http://localhost:8000/docs` in development.

## Repository Layout

```text
backend/
  app/
    agents/          NL-rule compiler + conversational agent builder
    api/v1/          FastAPI routes
    core/            settings, security, middleware
    db/              async SQLAlchemy session + Alembic migrations
    models/          ORM models
    schemas/         Pydantic request/response models
    services/        command hub, video broker, alerts, verification, demo simulator
    mcp/             in-process tool registry and permissions
  Dockerfile
  alembic.ini
  requirements.txt

frontend/sentineledge_app/
  lib/               Erlang AI Vision Flutter app
  config/            firebase.example.json / firebase.json

data/
  sentineledge_demo.db     local demo SQLite (git-tracked; do not commit reseeds)
  demo_videos/             source clips for the demo simulation (git-tracked)
  demo_frames/             frames extracted from the clips (git-ignored, generated)

docs/
  backend/
  frontend/
  deployment/        Alibaba Cloud architecture
  assets/            diagrams

scripts/
  create_judge_account.py  seed the judge/demo account (login + cameras + agents)
  extract_demo_frames.py   turn demo_videos into demo_frames for the simulator
  generate_demo_sqlite.py
  inspect_demo_sqlite.py
  seed_local_device.py
  seed_playback_clips.py
  simulate_event.py
  stream_simulator.py
  verify_smoke.py
  migrate_sqlite_to_rds.py
  start-dev.ps1
  deployment/              frontend.ps1 / backend.ps1 (Alibaba Cloud)
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

## Demo Simulation & Judge Account

For demos/judging you can drive the whole product without any camera hardware or the laptop edge: the backend plays a video into a camera's live view and runs AI detection on it via the Qwen-VL cloud API. This is strictly scoped to a demo account and never affects normal users.

1. Seed the demo account (a pre-verified Firebase email/password login plus a set of use-case cameras, each with an armed detection rule):

   ```powershell
   $env:PYTHONPATH="backend"
   python scripts\create_judge_account.py            # local SQLite
   # re-run with --reset to prune stale demo cameras/agents after catalog changes
   ```

2. Put a clip per camera in `data/demo_videos/` named by camera key (`house_frontdoor.mp4`, `house_backyard.mp4`, `office.mp4`, `street.mp4`, `baby.mp4`, `pets.mp4`), then extract frames (needs OpenCV; use the LaptopEdge venv):

   ```powershell
   ..\SentinelEdge_LaptopEdge\.venv\Scripts\python.exe scripts\extract_demo_frames.py --videos-dir
   ```

3. Enable it in `.env` and use a vision model:

   ```env
   DEMO_SIMULATION_ENABLED=true
   QWEN_MODEL=qwen-vl-plus        # a Qwen-VL model; the compiler/verifier keys come from KMS
   ```

Open a demo camera's live view and the backend starts looping its frames into the MJPEG broker (on-demand while watched) and, on a timer, sends a keyframe to Qwen-VL to triage against that camera's rule — producing real events. Gating: a camera is simulated only when `DEMO_SIMULATION_ENABLED=true`, its `device_id` starts with `DEMO_SIM_DEVICE_PREFIX` (default `dev_judge_`), and a frame folder exists for it. Tunable via `DEMO_SIM_FPS`, `DEMO_SIM_TRIAGE_INTERVAL_SECONDS`, `DEMO_SIM_EVENT_COOLDOWN_SECONDS`, `DEMO_SIM_IDLE_TIMEOUT_SECONDS`.

Deployment (Option A): the source clips are git-tracked; the extracted frames are git-ignored and generated locally. `backend/Dockerfile` copies `data/demo_frames/` into the image and sets `DEMO_FRAMES_DIR=/app/demo_frames`, and `scripts/deployment/backend.ps1` ensures the folder exists and reports how many frames it bundles. Extract frames locally before deploying, and set `DEMO_SIMULATION_ENABLED=true` in the deployed container env.

## Live Camera Flow

For a real camera demo, run all three tiers:

1. Backend and Erlang AI Vision Flutter app from this repo.
2. Edge console/bridge from `SentinelEdge_LaptopEdge` in `Real ESP32 WiFi` mode.
3. ESP32 firmware from `SentinelEdge_IOT`, usually the `xiao_s3` Wi-Fi build.

Erlang AI Vision creates/registers a camera and shows the one-time edge token. The edge bridge uses that token to connect to this backend, forward frames to `WS /api/v1/edge/stream`, keep `WS /api/v1/edge/ws` open for commands, and post detected events.

The live view uses `POST /api/v1/devices/{device_id}/stream-url` to mint a short-lived signed URL for MJPEG (`/stream`) or latest-frame polling (`/stream-frame`).

## Local AI Detection

Automatic detection is not in this Fullstack repo. It is implemented by `SentinelEdge_LaptopEdge`:

- YOLO video detection for `person` and other object labels.
- Optional YAMNet audio detection when audio frames are available.
- Ollama `qwen3.5:0.8b` local VLM triage before events are posted to this backend.

This backend stores agent rules and exposes assigned active configs through `GET /api/v1/edge/agents/active`. Natural-language rules are compiled by `app/agents/compiler.py`: a Qwen Cloud text model (`QWEN_COMPILER_MODEL`, default `qwen-plus`) turns the rule into the edge `compiled_edge_config` (`classes`, `min_confidence`, `dwell_s`, `cooldown_s`, optional `schedule`/`roi`) plus a `compiled_prompt`. It never fails agent creation — in test/key-less environments or on any LLM/parse error it falls back to a deterministic keyword compiler. Users can also draft rules conversationally via the agent builder (`POST /api/v1/agents/builder`).

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
- [Erlang AI Vision app README](frontend/sentineledge_app/README.md)

## Remaining Work

- Add production retention and cleanup jobs.
- Run and validate the SQLite-to-RDS migration against the existing cloud RDS instance and complete deployed ECI REST/SSE/WebSocket smoke tests.
- Configure and validate production HTTPS ingress in front of ECI.
- Add expired OSS object deletion and local recording deletion signaling.
- Complete Flutter push notification registration and native/mobile QA.
- Keep backend docs in sync with the separate LaptopEdge and IOT repos as their contracts evolve.

