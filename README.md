# SentinelEdge Fullstack

SentinelEdge is a surveillance backend and edge-integration project. The current implementation is focused on the backend foundation: FastAPI, SQLite local database connectivity, health checks, Alembic setup, and backend documentation.

## Current Status

Milestone 1 backend foundation is complete:

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

## Repository Layout

```text
backend/
  app/
    api/
    core/
    db/
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

Interactive docs are available in development:

```text
http://localhost:8000/docs
```

## Alembic

Check current migration state:

```powershell
alembic -c backend\alembic.ini current
```

Generate a migration after models are added:

```powershell
alembic -c backend\alembic.ini revision --autogenerate -m "message"
```

Apply migrations:

```powershell
alembic -c backend\alembic.ini upgrade head
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

## Next Milestone

Milestone 2 is the database model implementation:

- `users`
- `devices`
- `agents`
- `events`
- `clips`
- `recordings`
- `alerts`
- `tool_audit`

The schema should follow the ERD in [docs/backend/database_erd.md](docs/backend/database_erd.md).
