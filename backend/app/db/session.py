from sqlalchemy import event
from sqlalchemy.engine import Engine
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import settings


connect_args = {}
if settings.database_url.startswith("sqlite"):
    connect_args["check_same_thread"] = False


engine = create_async_engine(
    settings.database_url,
    echo=settings.app_env == "development",
    future=True,
    connect_args=connect_args,
)

async_session_factory = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


@event.listens_for(Engine, "connect")
def enable_sqlite_pragmas(dbapi_connection, connection_record) -> None:
    if not settings.database_url.startswith("sqlite"):
        return

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
