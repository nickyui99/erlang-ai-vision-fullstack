"""Post simulated edge events for LOCAL testing of the verification pipeline.

The real detection/agent tier (which would analyze video and POST events) is not
built yet, so armed agents never produce activity on their own. This script posts
events to ``/api/v1/edge/events`` exactly like that tier would, so you can watch
the full loop: event -> AI verification -> alert -> frontend activity + AI trail.

    cd erlang-ai-vision-fullstack
    $env:PYTHONPATH = 'backend'
    python scripts/simulate_event.py                          # one high-severity event
    python scripts/simulate_event.py --count 3 --interval 4
    python scripts/simulate_event.py --severity medium --summary "Package left at door"

Requirements:
  - the backend is running (default http://localhost:8000),
  - an agent is ARMED on the camera (Protection toggle in the app) so a
    per-device sub-agent exists,
  - set VERIFICATION_ENABLED=true (+ QWEN_API_KEY) in .env to get an AI verdict.

Uses the seeded local device token (see scripts/seed_local_device.py) by default.
"""

from __future__ import annotations

import argparse
import asyncio
from datetime import UTC, datetime
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

import httpx  # noqa: E402
from sqlalchemy import select  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker  # noqa: E402

from app.core.security import verify_edge_token  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.models.agent import Agent  # noqa: E402
from app.models.device import Device  # noqa: E402


DEFAULT_EDGE_TOKEN = "se_edge_3brh7i_7khh5B26A4AiSwCsIIw65N3i9dX_c8Vrx0CY"
DEFAULT_BASE_URL = "http://localhost:8000"


async def _resolve_device_and_agent(edge_token: str, agent_id: str | None):
    """Find the device for this edge token and a valid (armed) agent on it.

    The edge event endpoint requires an agent whose device_id + user_id match the
    token's device, i.e. a sub-agent created by arming a definition on the camera.
    """

    factory = async_sessionmaker(engine, expire_on_commit=False)
    async with factory() as session:
        # Edge token hashes are salted (pbkdf2), so we can't look up by hash
        # equality — verify against each device, exactly like the backend does.
        devices = (await session.execute(select(Device))).scalars().all()
        device = next((d for d in devices if verify_edge_token(edge_token, d.edge_token_hash)), None)
        if device is None:
            return None, None, "no device matches that edge token (check the token, or run scripts/seed_local_device.py)"

        query = select(Agent).where(Agent.device_id == device.device_id)
        if agent_id:
            query = query.where(Agent.agent_id == agent_id)
        agent = (await session.execute(query.order_by(Agent.created_at.desc()))).scalars().first()

        if agent is None:
            if agent_id:
                return device, None, f"agent {agent_id} is not assigned to device {device.device_id}"
            return device, None, (
                f"no agent is armed on device {device.device_id} ({device.name}). "
                "Arm an agent on the camera (Protection toggle), then rerun."
            )
        return device, agent, None


async def main(args: argparse.Namespace) -> None:
    device, agent, error = await _resolve_device_and_agent(args.edge_token, args.agent_id)
    if error:
        print(f"!! {error}")
        return

    print(f"device : {device.device_id} ({device.name})")
    print(f"agent  : {agent.agent_id} ({agent.name})")
    print(f"target : {args.api_base_url}/api/v1/edge/events")
    print("-" * 64)

    headers = {"Authorization": f"Bearer {args.edge_token}"}
    sent = 0
    async with httpx.AsyncClient(base_url=args.api_base_url, timeout=15) as client:
        for i in range(args.count):
            stamp = datetime.now(UTC)
            body = {
                "agent_id": agent.agent_id,
                "timestamp": stamp.isoformat(),
                "event_type": args.event_type,
                "severity": args.severity,
                "summary": args.summary,
                "confidence": args.confidence,
                "stage1_result": {"detector": "simulated", "label": args.event_type, "score": args.confidence},
                "stage2_verdict": {"source": "simulate_event.py", "match": True},
                "idempotency_key": f"sim-{stamp.strftime('%Y%m%d%H%M%S%f')}-{i}",
            }
            try:
                response = await client.post("/api/v1/edge/events", headers=headers, json=body)
            except httpx.HTTPError as exc:
                print(f"[{i + 1}/{args.count}] request failed: {exc} (is the backend running?)")
                continue

            if response.status_code in (200, 201):
                data = response.json().get("data", {})
                sent += 1
                print(
                    f"[{i + 1}/{args.count}] {response.status_code} "
                    f"event_id={data.get('event_id')} severity={data.get('severity')} "
                    f"status={data.get('status')}"
                )
            else:
                print(f"[{i + 1}/{args.count}] {response.status_code} {response.text[:300]}")

            if i + 1 < args.count:
                await asyncio.sleep(args.interval)

    print("-" * 64)
    print(f"submitted {sent}/{args.count} event(s).")
    print(
        "Verification runs in the background after each 201 — watch the app's "
        "Events tab (or the camera's Recent activity) for the AI verdict + trail."
    )


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Post simulated edge events for pipeline testing.")
    parser.add_argument("--api-base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--edge-token", default=DEFAULT_EDGE_TOKEN)
    parser.add_argument("--agent-id", default=None, help="defaults to the most recent armed agent on the device")
    parser.add_argument("--event-type", default="person_detected")
    parser.add_argument(
        "--severity", default="high", choices=["low", "medium", "high", "critical"]
    )
    parser.add_argument("--summary", default="Person detected near the front door")
    parser.add_argument("--confidence", type=float, default=0.82)
    parser.add_argument("--count", type=int, default=1)
    parser.add_argument("--interval", type=float, default=5.0, help="seconds between events when --count > 1")
    return parser.parse_args()


if __name__ == "__main__":
    asyncio.run(main(_parse_args()))
