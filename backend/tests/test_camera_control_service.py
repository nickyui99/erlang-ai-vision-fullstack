"""Cloud camera-control decision service (app/services/camera_control_service.py).

Hermetic: no network. Uses a fake Qwen client and the offline MockQwenClient. Covers action
sanitization/clamping, valid-action pass-through, and the candidate fallback when the model
returns no usable action.

Run (from backend/): python -m pytest tests/test_camera_control_service.py -v
"""
import asyncio
import os
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{(Path(tempfile.gettempdir()) / 'sentineledge_ccs_pytest.db').as_posix()}"

from app.services.camera_control_service import decide_camera_control, sanitize_action  # noqa: E402
from app.services.qwen_client import MockQwenClient, QwenResponse  # noqa: E402


class _FakeClient:
    def __init__(self, content):
        self._content = content

    async def verify(self, request, *, repair=False):  # pragma: no cover - unused
        return ""

    async def chat(self, messages, *, tools=None):
        return QwenResponse(content=self._content, tool_calls=[])


# --------------------------------------------------------------------------- sanitize

def test_sanitize_clamps_pan_and_tilt():
    assert sanitize_action({"cmd": "pan", "angle": 999}) == {"cmd": "pan", "angle": 180}
    assert sanitize_action({"cmd": "pan", "angle": -5}) == {"cmd": "pan", "angle": 0}
    assert sanitize_action({"cmd": "tilt", "angle": 999}) == {"cmd": "tilt", "angle": 140}
    assert sanitize_action({"cmd": "tilt", "angle": 0}) == {"cmd": "tilt", "angle": 60}


def test_sanitize_clamps_deltas_and_drops_zero():
    assert sanitize_action({"cmd": "pan_delta", "delta": 999}) == {"cmd": "pan_delta", "delta": 25}
    assert sanitize_action({"cmd": "pan_delta", "delta": 0}) is None  # a no-move is a hold


def test_sanitize_rejects_unknown_and_hold():
    assert sanitize_action({"cmd": "spin"}) is None
    assert sanitize_action({"cmd": "hold"}) is None
    assert sanitize_action("nope") is None
    assert sanitize_action(None) is None


# --------------------------------------------------------------------------- decide

def test_decide_passes_through_valid_model_action():
    action = asyncio.run(
        decide_camera_control({"candidate": None}, client=_FakeClient('{"cmd":"pan_delta","delta":10}'))
    )
    assert action == {"cmd": "pan_delta", "delta": 10}


def test_decide_clamps_model_action():
    action = asyncio.run(
        decide_camera_control({"candidate": None}, client=_FakeClient('{"cmd":"tilt","angle":300}'))
    )
    assert action == {"cmd": "tilt", "angle": 140}


def test_decide_falls_back_to_candidate_when_model_unusable():
    # MockQwenClient returns a verdict JSON (no "cmd"); the service uses the edge candidate.
    action = asyncio.run(
        decide_camera_control(
            {"candidate": {"cmd": "pan", "angle": 120}}, client=MockQwenClient()
        )
    )
    assert action == {"cmd": "pan", "angle": 120}


def test_decide_holds_when_no_candidate_and_no_action():
    action = asyncio.run(decide_camera_control({"candidate": None}, client=MockQwenClient()))
    assert action is None
