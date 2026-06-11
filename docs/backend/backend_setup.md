# Backend Setup Guide

This guide covers the planned local backend setup for SentinelEdge.

## Project Paths

| Path | Purpose |
|---|---|
| `docs/backend/` | Backend planning and reference documentation. |
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

SESSION_SECRET_KEY=change-me
SESSION_COOKIE_NAME=sentineledge_session
SESSION_EXPIRE_MINUTES=1440

SIGNED_URL_TTL_SECONDS=900
MEDIA_RETENTION_DAYS=7
DAILY_RECORDING_RETENTION_HOURS=72
```

For early local work without real OSS/Qwen calls, use mock adapters or leave provider credentials unset until those phases are implemented.

## SQLite Rules

- Enable SQLite foreign keys on every connection.
- Store JSON values as text in SQLite, using app-level serialization.
- Keep schema choices portable to PostgreSQL.
- Avoid trusting SQLite behavior that differs from PostgreSQL, especially around enums, JSON queries, and datetime handling.

## Related Docs

- [API endpoints](api_endpoints.md)
- [Database ERD](database_erd.md)
- [Auth flow](auth_flow.md)
- [Edge integration](edge_integration.md)
- [Media storage](media_storage.md)
