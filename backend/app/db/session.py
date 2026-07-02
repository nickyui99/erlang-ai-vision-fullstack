from sqlalchemy import event
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.core.config import settings


_IS_SQLITE = settings.database_url.startswith("sqlite")

engine_kwargs: dict = {
    "echo": settings.app_env == "development",
    "future": True,
}
if _IS_SQLITE:
    engine_kwargs["connect_args"] = {"check_same_thread": False}

if settings.app_env == "test":
    # asyncpg binds connections to the event loop that created them; tests run
    # one loop per asyncio.run/TestClient request, so pooled reuse breaks.
    engine_kwargs["poolclass"] = NullPool
elif not _IS_SQLITE:
    # RDS PostgreSQL: pool_pre_ping survives failover/idle reaping; recycle
    # below typical RDS/proxy idle timeouts. Sized for a single ECI container.
    engine_kwargs.update(
        pool_pre_ping=True,
        pool_size=5,
        max_overflow=5,
        pool_timeout=30,
        pool_recycle=1800,
    )


engine = create_async_engine(settings.database_url, **engine_kwargs)

async_session_factory = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


if _IS_SQLITE:

    @event.listens_for(engine.sync_engine, "connect")
    def enable_sqlite_pragmas(dbapi_connection, connection_record) -> None:
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        # Concurrency: the edge writes a heartbeat every ~2 s (+ audit inserts) while
        # command/auth reads run on other connections. The default rollback journal
        # makes a writer exclusively lock the DB, so those reads stall multi-second
        # behind each write — the measured 2-5 s command latency. WAL lets readers run
        # concurrently with the single writer; busy_timeout waits for a lock instead of
        # erroring; synchronous=NORMAL is the safe, fast pairing with WAL.
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA busy_timeout=5000")
        cursor.execute("PRAGMA synchronous=NORMAL")
        cursor.close()
