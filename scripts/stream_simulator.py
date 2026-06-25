"""Local push-stream simulator for SentinelEdge live video.

Pretends to be an ESP32-CAM edge device: sends heartbeats (so the camera shows
"online" in the app) and pushes generated JPEG frames over the edge stream
WebSocket, so you can test the full device -> backend -> frontend live-video
path without real hardware.

Setup:
    pip install websockets pillow

You only need the device's edge token (the backend identifies the device from
the token). Register a device in the Flutter app and copy the token from the
"Device edge token" dialog, or via the API (returned once):
    POST /api/v1/devices  ->  { "data": { "device": {...}, "edge_token": ... } }

Run:
    python scripts/stream_simulator.py --edge-token se_edge_xxx

Then open that camera in the Flutter app; the live view shows the animated
test pattern. The simulator keeps the camera online via periodic heartbeats.
"""

from __future__ import annotations

import argparse
import asyncio
import io
import json
import math
import time
import urllib.request

try:
    from PIL import Image, ImageDraw
except ImportError as exc:  # pragma: no cover - dev tooling
    raise SystemExit("Pillow is required: pip install pillow websockets") from exc

import websockets


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="SentinelEdge push-stream simulator")
    parser.add_argument("--edge-token", required=True, help="Raw edge token from device registration")
    parser.add_argument("--backend", default="ws://localhost:8000", help="Backend WebSocket base URL")
    parser.add_argument("--fps", type=float, default=10.0, help="Frames per second to push")
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=360)
    parser.add_argument("--label", default="edge-cam", help="Text drawn on the frame (cosmetic only)")
    parser.add_argument("--no-heartbeat", action="store_true", help="Do not send online heartbeats")
    return parser


def render_frame(width: int, height: int, frame_index: int, label: str) -> bytes:
    image = Image.new("RGB", (width, height), (10, 20, 18))
    draw = ImageDraw.Draw(image)

    # A box that orbits the frame so motion is obvious in the live view.
    t = frame_index / 30.0
    cx = int((math.sin(t) * 0.5 + 0.5) * (width - 80)) + 40
    cy = int((math.cos(t * 0.7) * 0.5 + 0.5) * (height - 80)) + 40
    draw.rectangle([cx - 30, cy - 30, cx + 30, cy + 30], outline=(0, 220, 160), width=4)

    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    draw.text((12, 10), f"SentinelEdge SIM  {label}", fill=(230, 230, 230))
    draw.text((12, 28), f"{stamp}  frame {frame_index}", fill=(0, 220, 160))

    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=70)
    return buffer.getvalue()


def _connect(url: str, headers: dict[str, str]):
    """websockets renamed extra_headers -> additional_headers in v13."""
    try:
        return websockets.connect(url, additional_headers=headers, max_size=None)
    except TypeError:
        return websockets.connect(url, extra_headers=headers, max_size=None)


def _post_heartbeat(http_base: str, edge_token: str, fps: float) -> None:
    body = json.dumps(
        {
            "health_status": "online",
            "rssi": -55.0,
            "fps": fps,
            "current_pan": 90,
            "current_tilt": 90,
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        f"{http_base}/api/v1/edge/heartbeat",
        data=body,
        headers={"Authorization": f"Bearer {edge_token}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=5):
        pass


async def _heartbeat_loop(http_base: str, edge_token: str, fps: float, interval: float = 10.0) -> None:
    loop = asyncio.get_running_loop()
    while True:
        try:
            await loop.run_in_executor(None, _post_heartbeat, http_base, edge_token, fps)
        except Exception as exc:  # noqa: BLE001 - keep streaming even if heartbeat fails
            print(f"[heartbeat] failed: {exc}")
        await asyncio.sleep(interval)


async def run(args: argparse.Namespace) -> None:
    ws_base = args.backend.rstrip("/")
    http_base = ws_base.replace("wss://", "https://").replace("ws://", "http://")
    url = f"{ws_base}/api/v1/edge/stream"
    headers = {"Authorization": f"Bearer {args.edge_token}"}
    delay = 1.0 / args.fps if args.fps > 0 else 0.1

    heartbeat_task: asyncio.Task | None = None
    if not args.no_heartbeat:
        # Send one immediately so the camera is "online" before frames start.
        try:
            await asyncio.get_running_loop().run_in_executor(
                None, _post_heartbeat, http_base, args.edge_token, args.fps
            )
            print("Heartbeat sent — camera marked online.")
        except Exception as exc:  # noqa: BLE001
            print(f"[heartbeat] initial heartbeat failed: {exc}")
        heartbeat_task = asyncio.create_task(_heartbeat_loop(http_base, args.edge_token, args.fps))

    print(f"Connecting to {url} ...")
    try:
        async with _connect(url, headers) as ws:
            print(f"Connected. Pushing ~{args.fps:.0f} fps. Press Ctrl+C to stop.")
            frame_index = 0
            while True:
                frame = render_frame(args.width, args.height, frame_index, args.label)
                await ws.send(frame)
                frame_index += 1
                await asyncio.sleep(delay)
    finally:
        if heartbeat_task is not None:
            heartbeat_task.cancel()


def main() -> None:
    args = _build_parser().parse_args()
    try:
        asyncio.run(run(args))
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
