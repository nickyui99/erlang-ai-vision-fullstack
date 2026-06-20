# SentinelEdge Fullstack

SentinelEdge is a surveillance backend and edge-integration project. The current implementation is focused on the backend foundation and database layer: FastAPI, SQLite local database connectivity, health checks, SQLAlchemy models, Alembic migrations, and backend documentation.

## Current Status

Milestones 1, 2, and 3 are complete:

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
- `POST /api/v1/agents`
- `GET /api/v1/agents`
- `GET /api/v1/agents/{agent_id}`
- `PUT /api/v1/agents/{agent_id}`
- `POST /api/v1/agents/{agent_id}/arm`
- `POST /api/v1/agents/{agent_id}/disarm`
- `POST /api/v1/edge/heartbeat`
- `GET /api/v1/edge/agents/active`

Event, clip, recording, alert, SSE, WebSocket, pan command, Qwen, and MCP endpoints are documented as planned API surface and will be implemented in later milestones.

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

<<Device, agent, and edge loop endpoints:

```text
POST http://localhost:8000/api/v1/devices
GET  http://localhost:8000/api/v1/devices
GET  http://localhost:8000/api/v1/devices/{device_id}
PUT  http://localhost:8000/api/v1/devices/{device_id}
POST http://localhost:8000/api/v1/agents
GET  http://localhost:8000/api/v1/agents
GET  http://localhost:8000/api/v1/agents/{agent_id}
PUT  http://localhost:8000/api/v1/agents/{agent_id}
POST http://localhost:8000/api/v1/agents/{agent_id}/arm
POST http://localhost:8000/api/v1/agents/{agent_id}/disarm
POST http://localhost:8000/api/v1/edge/heartbeat
GET  http://localhost:8000/api/v1/edge/agents/active
```

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

<<Milestone 3 is complete when Firebase Google login succeeds from the Flutter app and `/api/v1/users/me` returns the current user using the backend session cookie.

## Milestone 4 Validation

Milestone 4 covers the first device and agent loop after login: register a device, receive the raw edge token once, create and arm an agent, send an edge heartbeat, and pull active edge configs.

Register a device with an authenticated browser session cookie:

```powershell
Invoke-RestMethod -Method Post http://localhost:8000/api/v1/devices -ContentType 'application/json' -Body '{"name":"Front Door Camera","location":"Front Door"}' -WebSession $session
```

Save the returned `edge_token`, then send heartbeat as the edge service:

```powershell
Invoke-RestMethod -Method Post http://localhost:8000/api/v1/edge/heartbeat -Headers @{ Authorization = "Bearer <edge_token>" } -ContentType 'application/json' -Body '{"health_status":"online","rssi":-58.2,"fps":15.0,"current_pan":90}'
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

Milestone 5 is the event and media loop:

- accept edge event submission
- enforce event idempotency
- list and inspect user events
- register clip metadata
- support upload and playback URL flows
- register recording metadata



