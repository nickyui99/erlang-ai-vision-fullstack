"""Milestone 9A smoke test: run the configured Qwen client on one sample event
and print the raw reply + the parsed verdict. No backend / DB / edge needed.

    cd erlang-ai-vision-fullstack
    $env:PYTHONPATH = 'backend'
    python scripts/verify_smoke.py

Uses whatever is in .env. With a real QWEN_API_KEY (and APP_ENV != test) this
hits live Qwen; otherwise it exercises the offline MockQwenClient. Note this
does NOT require VERIFICATION_ENABLED — it calls the client directly.
"""

from __future__ import annotations

import asyncio
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from app.core.config import settings  # noqa: E402
from app.schemas.verification import VerificationRequest  # noqa: E402
from app.services import qwen_client  # noqa: E402
from app.services import verification_service  # noqa: E402
from app.services.qwen_client import QwenError  # noqa: E402


SAMPLE = VerificationRequest(
    event_id="evt_smoke",
    rule="Alert when a person loiters near the front door at night.",
    compiled_prompt="Watch for a person lingering near the entrance.",
    event_type="person_detected",
    severity="high",
    summary="A person has been standing near the front door for two minutes.",
    confidence=0.62,
    stage1_result={"detector": "yolo", "label": "person", "score": 0.88},
    stage2_verdict={"motion": "sustained", "zone": "doorway"},
    device_name="Front Door Cam",
    device_location="Porch",
    recent_events=[],
)


async def main() -> None:
    client = qwen_client.get_qwen_client()
    print(f"client   : {type(client).__name__}")
    print(f"app_env  : {settings.app_env}")
    print(f"model    : {settings.qwen_model}")
    print(f"base_url : {settings.qwen_base_url}")
    print(f"key set  : {bool(settings.qwen_api_key)}")
    print("-" * 60)

    try:
        raw = await client.verify(SAMPLE)
    except QwenError as exc:
        print(f"QwenError: {exc}")
        print("\nIf this is a model/input error, try a text model for 9A, e.g.")
        print("  QWEN_MODEL=qwen-plus   (qwen-plus-* is for the multimodal 9C path)")
        return

    print("RAW REPLY:")
    print(raw)
    print("-" * 60)

    obj = verification_service._extract_json(raw)
    verdict = verification_service._normalize(obj, SAMPLE.severity) if obj is not None else None
    if verdict is None:
        print("PARSED   : <none> -> event would be marked DEGRADED")
    else:
        print("PARSED VERDICT:")
        for key, value in verdict.model_dump().items():
            print(f"  {key}: {value}")


if __name__ == "__main__":
    asyncio.run(main())
