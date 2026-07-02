"""One-shot copy of the local SQLite demo DB into Alibaba ApsaraDB RDS PostgreSQL.

Runbook (PowerShell; DATABASE_URL may come from the KMS secret via .env):

    cd SentinelEdge-Fullstack
    alembic -c backend\\alembic.ini upgrade head
    python scripts\\migrate_sqlite_to_rds.py --dry-run
    python scripts\\migrate_sqlite_to_rds.py

The target must be at alembic head and empty (re-run with --truncate to wipe
and reload). Everything runs in a single transaction: any verification
mismatch rolls the whole copy back. Naive SQLite datetimes are UTC wall times
(every writer uses datetime.now(UTC); SQLite's storage format drops the
offset) and are re-labelled +00:00, never shifted.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from sqlalchemy import JSON, Boolean, DateTime, Table, text  # noqa: E402
from sqlalchemy.exc import OperationalError, ProgrammingError  # noqa: E402
from sqlalchemy.ext.asyncio import AsyncConnection, create_async_engine  # noqa: E402
from sqlalchemy.pool import NullPool  # noqa: E402

from app.core.config import settings  # noqa: E402  (import loads KMS secret -> DATABASE_URL)
from app.db.base import Base  # noqa: E402
import app.models  # noqa: E402,F401

ALEMBIC_HEAD = "20260623_0005"
EXPECTED_TABLES = {
    "users",
    "devices",
    "agents",
    "events",
    "clips",
    "recordings",
    "alerts",
    "push_tokens",
    "tool_audit",
}


def resolve_target_url() -> str:
    url = os.environ.get("DATABASE_URL") or settings.database_url
    if url.startswith("postgresql://"):
        url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
    if not url.startswith("postgresql+asyncpg://"):
        scheme = url.split("://", 1)[0]
        sys.exit(
            f"Refusing target scheme {scheme!r}: DATABASE_URL must be postgresql+asyncpg "
            "(the settings default is the SQLite source itself)."
        )
    return url


def parse_sqlite_datetime(raw: str) -> datetime:
    s = raw.strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    if " " in s and "T" not in s:
        s = s.replace(" ", "T", 1)
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def convert_value(column, raw):
    if raw is None:
        return None
    if isinstance(column.type, Boolean):
        return bool(raw)
    if isinstance(column.type, JSON):
        return json.loads(raw) if isinstance(raw, str) else raw
    if isinstance(column.type, DateTime):
        return parse_sqlite_datetime(raw)
    return raw


def read_source(source_path: Path) -> dict[str, list[dict]]:
    src = sqlite3.connect(f"file:{source_path.as_posix()}?mode=ro", uri=True)
    src.row_factory = sqlite3.Row
    try:
        data: dict[str, list[dict]] = {}
        for table in Base.metadata.sorted_tables:
            rows = src.execute(f"SELECT * FROM {table.name}").fetchall()
            data[table.name] = [
                {c.name: convert_value(c, row[c.name]) for c in table.columns} for row in rows
            ]
        return data
    finally:
        src.close()


def ordered_batches(table: Table, rows: list[dict]) -> list[list[dict]]:
    if table.name != "agents":
        return [rows]
    parents = [r for r in rows if r["parent_agent_id"] is None]
    children = [r for r in rows if r["parent_agent_id"] is not None]
    return [parents, children]


async def check_alembic_head(conn: AsyncConnection) -> None:
    try:
        version = (await conn.execute(text("SELECT version_num FROM alembic_version"))).scalar()
    except (ProgrammingError, OperationalError):
        version = None
    if version != ALEMBIC_HEAD:
        sys.exit(
            f"Target schema is not at alembic head ({version!r} != {ALEMBIC_HEAD!r}).\n"
            "Run first:  alembic -c backend/alembic.ini upgrade head"
        )


async def target_counts(conn: AsyncConnection) -> dict[str, int]:
    counts = {}
    for table in Base.metadata.sorted_tables:
        counts[table.name] = (
            await conn.execute(text(f"SELECT COUNT(*) FROM {table.name}"))
        ).scalar()
    return counts


async def verify(conn: AsyncConnection, source: dict[str, list[dict]]) -> None:
    failures: list[str] = []
    for table in Base.metadata.sorted_tables:
        expected = source[table.name]
        got = (await conn.execute(table.select())).mappings().all()
        status = "OK" if len(got) == len(expected) else "MISMATCH"
        print(f"  {table.name:<14} source={len(expected):>4} target={len(got):>4}  {status}")
        if len(got) != len(expected):
            failures.append(f"{table.name}: row count {len(got)} != {len(expected)}")
            continue
        pk_cols = [c.name for c in table.primary_key.columns]
        got_by_pk = {tuple(r[c] for c in pk_cols): r for r in got}
        for src_row in expected:
            key = tuple(src_row[c] for c in pk_cols)
            dst_row = got_by_pk.get(key)
            if dst_row is None:
                failures.append(f"{table.name}: missing pk {key}")
                continue
            for col in table.columns:
                src_val, dst_val = src_row[col.name], dst_row[col.name]
                if isinstance(src_val, datetime) and isinstance(dst_val, datetime):
                    if src_val != dst_val.astimezone(timezone.utc):
                        failures.append(f"{table.name}.{col.name} pk={key}: {src_val!r} != {dst_val!r}")
                elif src_val != dst_val:
                    failures.append(f"{table.name}.{col.name} pk={key}: {src_val!r} != {dst_val!r}")
    if failures:
        for failure in failures[:20]:
            print(f"  VERIFY FAIL: {failure}")
        raise RuntimeError(f"verification failed with {len(failures)} mismatch(es); transaction rolled back")


async def run(source_path: Path, truncate: bool, dry_run: bool) -> None:
    if not source_path.exists():
        sys.exit(f"Source database not found: {source_path}")

    print(f"Source : {source_path}")
    source = read_source(source_path)
    total = sum(len(rows) for rows in source.values())

    names = {t.name for t in Base.metadata.sorted_tables}
    if names != EXPECTED_TABLES:
        sys.exit(f"Model metadata tables changed: {sorted(names ^ EXPECTED_TABLES)} — update this script.")

    url = resolve_target_url()
    engine = create_async_engine(url, poolclass=NullPool)
    print(f"Target : {engine.url.render_as_string(hide_password=True)}")
    print(f"Rows   : {total} across {len(names)} tables")
    print(f"WARNING: copying real user PII (emails, google subs) for {len(source['users'])} users.")

    try:
        if dry_run:
            async with engine.connect() as conn:
                await check_alembic_head(conn)
                existing = await target_counts(conn)
            print("\nDry run - no writes. Converted sample per table:")
            for table in Base.metadata.sorted_tables:
                rows = source[table.name]
                occupied = f" (target already has {existing[table.name]} rows)" if existing[table.name] else ""
                print(f"  {table.name:<14} {len(rows):>4} rows{occupied}")
                if rows:
                    sample = {k: repr(v)[:60] for k, v in rows[0].items()}
                    print(f"    sample: {sample}")
            if any(existing.values()) and not truncate:
                print("\nNOTE: target is not empty; the real run will abort without --truncate.")
            return

        async with engine.begin() as conn:
            await check_alembic_head(conn)
            existing = await target_counts(conn)
            if any(existing.values()):
                if not truncate:
                    occupied = {k: v for k, v in existing.items() if v}
                    sys.exit(
                        f"Target is not empty: {occupied}\n"
                        "Re-run with --truncate to wipe and reload."
                    )
                print("Truncating target tables (CASCADE)...")
                await conn.execute(text(f"TRUNCATE {', '.join(sorted(EXPECTED_TABLES))} CASCADE"))

            for table in Base.metadata.sorted_tables:
                for batch in ordered_batches(table, source[table.name]):
                    if batch:
                        await conn.execute(table.insert(), batch)

            print("\nVerification (inside the copy transaction):")
            await verify(conn, source)

        print(f"\nDone: {total} rows migrated and verified.")
    finally:
        await engine.dispose()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source", type=Path, default=ROOT / "data" / "sentineledge_demo.db")
    parser.add_argument("--truncate", action="store_true", help="wipe non-empty target tables before copying")
    parser.add_argument("--dry-run", action="store_true", help="read, convert and precheck only; no writes")
    args = parser.parse_args()
    asyncio.run(run(args.source, args.truncate, args.dry_run))


if __name__ == "__main__":
    main()
