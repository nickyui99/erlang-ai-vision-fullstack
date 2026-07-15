"""NL-rule compiler tests.

APP_ENV=test forces the deterministic keyword compiler (no network), so these are
hermetic. Covers keyword mapping, LLM-output validation/sanitization, and the create ->
assign -> edge-config-pull path emitting the edge's `classes` schema (not `detectors`).

Run (from backend/): python -m pytest tests/test_agent_compiler.py -v
"""
import asyncio
from datetime import UTC, datetime
import os
from pathlib import Path
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{(Path(tempfile.gettempdir()) / 'erlang_compiler_pytest.db').as_posix()}"

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402

from app.agents import compiler  # noqa: E402
from app.agents.compiler import (  # noqa: E402
    _clean_camera_control,
    _clean_classes,
    _clean_roi,
    _clean_schedule,
    _validate_config,
    compile_agent_rule,
)
from app.core.security import create_session_token, hash_edge_token  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models.device import Device  # noqa: E402
from app.models.user import User  # noqa: E402


_SUPPORTED_KEYS = {
    "classes", "min_confidence", "dwell_s", "cooldown_s", "schedule", "roi", "camera_control",
}


# ------------------------------------------------------------------- keyword compiler

def test_keyword_person_with_overnight_schedule():
    prompt, config = asyncio.run(
        compile_agent_rule("Alert me if someone lingers at the front door after 9pm.")
    )
    assert config["classes"] == ["person"]
    assert config["schedule"] == {"start": "21:00", "end": "06:00"}
    assert prompt == "Alert me if someone lingers at the front door after 9pm."


def test_keyword_audio_multi_class():
    _, config = asyncio.run(compile_agent_rule("Tell me about breaking glass or a scream."))
    assert set(config["classes"]) == {"glass-break", "scream"}


def test_keyword_pet_expands_to_dog_and_cat():
    _, config = asyncio.run(compile_agent_rule("Let me know if a pet gets on the sofa."))
    assert "dog" in config["classes"] and "cat" in config["classes"]


def test_keyword_defaults_to_person_when_unmatched():
    _, config = asyncio.run(compile_agent_rule("Watch for anything unusual."))
    assert config["classes"] == ["person"]


def test_keyword_config_uses_only_supported_keys_and_no_detectors():
    _, config = asyncio.run(compile_agent_rule("A person after 10pm."))
    assert set(config).issubset(_SUPPORTED_KEYS)
    assert "detectors" not in config
    assert config["schedule"] == {"start": "22:00", "end": "06:00"}


# --------------------------------------------------------------------- validation

def test_validate_clamps_and_filters_classes():
    config = _validate_config({
        "classes": ["person", "dragon", "DOG"],  # unknown dropped, case-normalized
        "min_confidence": 5,                       # clamped to 1.0
        "dwell_s": -1,                             # invalid -> default
        "cooldown_s": "nope",                      # invalid -> default
    })
    assert config["classes"] == ["person", "dog"]
    assert config["min_confidence"] == 1.0
    assert config["dwell_s"] == 3.0 and config["cooldown_s"] == 30.0


def test_validate_empty_classes_defaults_to_person():
    assert _clean_classes([]) == ["person"]
    assert _clean_classes(["dragon", "unicorn"]) == ["person"]
    assert _clean_classes(None) == ["person"]


def test_validate_schedule_accepts_valid_rejects_junk():
    assert _clean_schedule({"start": "22:00", "end": "06:00", "days": [0, 1, 7]}) == {
        "start": "22:00", "end": "06:00", "days": [0, 1],
    }
    assert _clean_schedule({"start": "9pm", "end": "6am"}) is None
    assert _clean_schedule({"start": "22:00"}) is None
    assert _clean_schedule("nightly") is None


def test_validate_roi_shape():
    assert _clean_roi([1, 2, 3, 4]) == [1.0, 2.0, 3.0, 4.0]
    assert _clean_roi([1, 2]) is None
    assert _clean_roi("box") is None


def test_validate_omits_absent_optional_keys():
    config = _validate_config({"classes": ["person"]})
    assert "schedule" not in config and "roi" not in config


# ----------------------------------------------------------------- camera control

def test_validate_always_includes_camera_control_defaulting_to_none():
    config = _validate_config({"classes": ["person"]})
    cc = config["camera_control"]
    assert cc["behavior"] == "none"           # no motion implied -> fixed camera
    assert cc["target_classes"] == ["person"]  # defaults to the rule's video classes


def test_validate_camera_control_sanitizes_behavior_and_targets():
    cc = _clean_camera_control(
        {"behavior": "spin", "target_classes": ["person", "glass-break", "dragon"],
         "prompt": "  watch them  "},
        ["person"],
    )
    assert cc["behavior"] == "none"                 # unknown behavior rejected
    assert cc["target_classes"] == ["person"]        # audio/unknown classes dropped
    assert cc["prompt"] == "watch them"


def test_validate_camera_control_accepts_follow():
    cc = _clean_camera_control({"behavior": "FOLLOW"}, ["person", "dog"])
    assert cc["behavior"] == "follow"
    assert cc["target_classes"] == ["person", "dog"]


def test_keyword_follow_verb_sets_follow_behavior():
    _, config = asyncio.run(
        compile_agent_rule("Follow anyone who walks in and keep them on camera.")
    )
    assert config["camera_control"]["behavior"] == "follow"
    assert config["camera_control"]["target_classes"] == ["person"]


def test_keyword_no_motion_verb_defaults_to_none():
    _, config = asyncio.run(compile_agent_rule("Alert me if a person is at the door."))
    assert config["camera_control"]["behavior"] == "none"


# ----------------------------------------------------------------- endpoint wiring

EDGE_TOKEN = "edge-token-compiler"
EDGE_HEADERS = {"Authorization": f"Bearer {EDGE_TOKEN}"}


def setup_function() -> None:
    asyncio.run(_reset_db())


async def _reset_db() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as session:
        now = datetime.now(UTC)
        session.add(User(user_id="usr_c", google_sub="gsub_c", email="c@example.com",
                         email_verified=True, role="user", created_at=now, updated_at=now))
        await session.commit()
        session.add(Device(device_id="dev_c", user_id="usr_c",
                           edge_token_hash=hash_edge_token(EDGE_TOKEN), name="Front Door",
                           health_status="online", current_pan=90, created_at=now, updated_at=now))
        await session.commit()


def _client() -> TestClient:
    client = TestClient(app)
    client.cookies.set("erlang_session", create_session_token("usr_c"))
    return client


def test_create_and_assign_emits_edge_classes_config():
    client = _client()
    created = client.post(
        "/api/v1/agents",
        json={"name": "Night Door", "nl_rule": "Alert if a person is at the door after 10pm."},
    )
    assert created.status_code == 201
    definition = created.json()["data"]
    cfg = definition["compiled_edge_config"]
    assert cfg["classes"] == ["person"]          # edge schema key, not "detectors"
    assert "detectors" not in cfg
    assert cfg["schedule"] == {"start": "22:00", "end": "06:00"}

    assigned = client.post(f"/api/v1/agents/{definition['agent_id']}/assign",
                           json={"device_id": "dev_c"})
    assert assigned.status_code == 200

    active = client.get("/api/v1/edge/agents/active", headers=EDGE_HEADERS)
    assert active.status_code == 200
    item = active.json()["data"][0]
    assert item["compiled_edge_config"]["classes"] == ["person"]
    assert "detectors" not in item["compiled_edge_config"]
