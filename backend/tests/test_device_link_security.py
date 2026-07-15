import asyncio
from datetime import UTC, datetime
import os
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{(Path(tempfile.gettempdir()) / 'sentinledge_device_link_pytest.db').as_posix()}"

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402

from app.core.security import create_session_token, derive_device_link_secret, hash_edge_token  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models.user import User  # noqa: E402


VECTOR_TOKEN = "se_edge_test_vector"


def setup_function() -> None:
    asyncio.run(_reset_db())


async def _reset_db() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as session:
        now = datetime.now(UTC)
        session.add(User(user_id="usr_link", google_sub="gsub_link", email="link@example.com", email_verified=True, role="user", created_at=now, updated_at=now))
        await session.commit()


def test_device_link_secret_matches_protocol_vector() -> None:
    assert derive_device_link_secret(VECTOR_TOKEN) == "GI-WZ0KItBFz1vXUdsxy8w13lu0pI0_F_GyC3WqNjy8"


def test_device_link_secret_is_urlsafe() -> None:
    value = derive_device_link_secret("se_edge_example")
    assert len(value) == 43
    assert value != "se_edge_example"
    assert all(ch.isalnum() or ch in "_-" for ch in value)


def test_registration_returns_derived_secret_without_persisting_raw_values() -> None:
    client = TestClient(app)
    client.cookies.set("erlang_session", create_session_token("usr_link"))
    response = client.post("/api/v1/devices", json={"name": "Link camera"})
    assert response.status_code == 201
    data = response.json()["data"]
    assert data["device_link_secret"] == derive_device_link_secret(data["edge_token"])
    assert data["device_link_secret"] != data["edge_token"]

    from app.models.device import Device
    from app.db.session import engine
    from sqlalchemy import select
    async def read_device() -> Device:
        async_session = async_sessionmaker(engine, expire_on_commit=False)
        async with async_session() as session:
            return (await session.execute(select(Device))).scalar_one()
    device = asyncio.run(read_device())
    assert device.edge_token_hash != data["edge_token"]
    assert data["edge_token"] not in device.edge_token_hash

