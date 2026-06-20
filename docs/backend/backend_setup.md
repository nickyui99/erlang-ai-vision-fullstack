# Backend Setup Guide

This guide covers the local backend setup for SentinelEdge.

## Project Paths

| Path | Purpose |
|---|---|
| `docs/backend/` | Backend planning and reference documentation. |
| `backend/app/models/` | SQLAlchemy ORM models for the core MVP tables. |
| `backend/app/db/migrations/versions/` | Alembic migration revisions. |
| `scripts/demo_sqlite_schema.sql` | Demo SQLite schema. |
| `scripts/generate_demo_sqlite.py` | Recreates the demo SQLite database with seed data. |
| `scripts/inspect_demo_sqlite.py` | Prints demo database tables and row counts. |
| `data/sentineledge_demo.db` | Generated demo SQLite database. |

## Local Database

Initial backend development uses SQLite.

Recommended local database URL:

```env
DATABASE_URL=sqlite+aiosqlite:///./data/sentineledge_demo.db
```

Regenerate the demo database:

```powershell
python scripts\generate_demo_sqlite.py
```

Inspect the demo database:

```powershell
python scripts\inspect_demo_sqlite.py
```

The demo database contains one row for each core table:

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

## Environment Variables

Minimum local `.env` values:

```env
APP_ENV=development
APP_NAME=SentinelEdge Backend
API_PREFIX=/api/v1

DATABASE_URL=sqlite+aiosqlite:///./data/sentineledge_demo.db

GOOGLE_OAUTH_CLIENT_ID=change-me
GOOGLE_OAUTH_CLIENT_SECRET=change-me
GOOGLE_OAUTH_REDIRECT_URI=http://localhost:8000/api/v1/auth/google/callback

FIREBASE_PROJECT_ID=change-me
GOOGLE_APPLICATION_CREDENTIALS=C:\path\to\firebase-service-account.json

SESSION_SECRET_KEY=change-me
SESSION_COOKIE_NAME=sentineledge_session
SESSION_EXPIRE_MINUTES=1440

SIGNED_URL_TTL_SECONDS=900
MEDIA_RETENTION_DAYS=7
DAILY_RECORDING_RETENTION_HOURS=72
```

For early local work without real OSS/Qwen calls, use mock adapters or leave provider credentials unset until those phases are implemented.

## Firebase Auth Setup

Firebase Auth can handle Google sign-in on the frontend. The backend verifies the Firebase ID token with the Firebase Admin SDK.

Install dependencies:

```powershell
pip install -r backend\requirements.txt
```

If `uvicorn.exe` is locked by a running dev server, stop the server first. As a fallback, install Firebase Admin only:

```powershell
python -m pip install --user firebase-admin==6.6.0
```

Create a Firebase service account key in Firebase Console, store it outside Git, and set:

```env
FIREBASE_PROJECT_ID=your-firebase-project-id
GOOGLE_APPLICATION_CREDENTIALS=C:\Users\nicho\secrets\firebase-service-account.json
```

Frontend flow:

```text
Firebase Google sign-in -> user.getIdToken() -> POST /api/v1/auth/firebase/login
```

Backend flow:

```text
verify Firebase ID token -> upsert local users row -> issue SentinelEdge session cookie
```

## SQLite Rules

- Enable SQLite foreign keys on every connection.
- Use SQLAlchemy `JSON` fields in models; SQLite stores them with SQLite-compatible JSON/text behavior.
- Keep schema choices portable to PostgreSQL.
- Avoid trusting SQLite behavior that differs from PostgreSQL, especially around enums, JSON queries, and datetime handling.

## Milestone 2 Checks

Confirm the ORM model metadata includes all core tables:

```powershell
$env:PYTHONDONTWRITEBYTECODE="1"
$env:PYTHONPATH="backend"
python -c "import app.models; from app.db.base import Base; print(sorted(Base.metadata.tables.keys()))"
```

Render the current Alembic migration SQL without changing a database:

```powershell
$env:PYTHONDONTWRITEBYTECODE="1"
alembic -c backend\alembic.ini upgrade head --sql
```

Apply migrations to a throwaway local database:

```powershell
$env:DATABASE_URL="sqlite+aiosqlite:///C:/tmp/sentineledge_m2_test.db"
alembic -c backend\alembic.ini upgrade head
alembic -c backend\alembic.ini current
```

Expected current revision:

```text
20260620_0001
```

Avoid running migration experiments against `data/sentineledge_demo.db`; keep that file as the seeded demo database.

## Related Docs

- [API endpoints](api_endpoints.md)
- [Database ERD](database_erd.md)
- [Auth flow](auth_flow.md)
- [Edge integration](edge_integration.md)
- [Media storage](media_storage.md)
