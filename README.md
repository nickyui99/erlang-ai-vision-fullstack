# SentinelEdge Fullstack

SentinelEdge is a surveillance backend and edge-integration project. The current implementation is focused on the backend foundation and database layer: FastAPI, SQLite local database connectivity, health checks, SQLAlchemy models, Alembic migrations, and backend documentation.

## Current Status

Milestones 1 and 2 are complete:

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

Implemented HTTP endpoints:

- `GET /healthz`
- `GET /readyz`
- `GET /api/v1/version`
- `GET /api/v1/auth/google/start`
- `GET /api/v1/auth/google/callback`
- `POST /api/v1/auth/firebase/login`
- `POST /api/v1/auth/logout`
- `GET /api/v1/users/me`

Device, agent, event, clip, recording, alert, edge, SSE, and WebSocket endpoints are documented as planned API surface and will be implemented in later milestones.

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

data/
  sentineledge_demo.db

docs/
  backend/
    api_endpoints.md
    auth_flow.md
    backend_setup.md
    database_erd.md
    edge_integration.md
    media_storage.md
    mvp_checklist.md
    sentineledge_backend_implementation_plan.md

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
GET  http://localhost:8000/api/v1/auth/google/start
GET  http://localhost:8000/api/v1/auth/google/callback
POST http://localhost:8000/api/v1/auth/firebase/login
POST http://localhost:8000/api/v1/auth/logout
GET  http://localhost:8000/api/v1/users/me
```

Google OAuth requires real `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, and `GOOGLE_OAUTH_REDIRECT_URI` values in `.env`. With placeholder credentials, `/api/v1/auth/google/start` returns `503 oauth_not_configured`.

Firebase Auth can also be used for Google login. The frontend signs in with Firebase, gets a Firebase ID token, and sends it to the backend:

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
- [API endpoints](docs/backend/api_endpoints.md)
- [Database ERD](docs/backend/database_erd.md)
- [Auth flow](docs/backend/auth_flow.md)
- [Edge integration](docs/backend/edge_integration.md)
- [Media storage](docs/backend/media_storage.md)
- [MVP checklist](docs/backend/mvp_checklist.md)

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

OAuth configuration check:

```powershell
Invoke-RestMethod http://localhost:8000/api/v1/auth/google/start
```

With placeholder Google credentials, expected result is `503 oauth_not_configured`. With real Google credentials, this endpoint redirects to Google.

Firebase login configuration check:

```powershell
Invoke-RestMethod -Method Post http://localhost:8000/api/v1/auth/firebase/login
```

Expected result without a bearer token is `401 not_authenticated`. With a fake bearer token and missing Firebase settings, expected result is `503 firebase_not_configured`.

## Next Milestone

Milestone 4 is the device and agent loop:

- register device
- return raw edge token once
- list and update user devices
- accept edge heartbeat
- create and manage agents
- compile edge config
- let edge pull active configs
