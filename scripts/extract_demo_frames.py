"""Extract demo camera frames for backend-side simulation (judge account).

The backend has no opencv/ffmpeg, so we pre-extract JPEG frames offline and the
backend just loops them into a demo camera's live view (see
app/services/demo_simulator.py). Run this whenever you place a new video for a
camera.

Needs opencv — run it with the LaptopEdge venv (it has cv2), e.g.:

    cd SentinelEdge-Fullstack
    ../SentinelEdge_LaptopEdge/.venv/Scripts/python.exe scripts/extract_demo_frames.py \
        --camera driveway --video path/to/driveway_clip.mp4

Camera keys match the seeded cameras (create_judge_account.py):
    house_frontdoor, house_backyard, office, street, baby, pets

Frames land in data/demo_frames/<camera>/frame_XXXX.jpg. The folder is cleared
and rewritten each run (idempotent).

EASIEST: drop your AI-generated clips in data/demo_videos/ named after each camera
(house_frontdoor.mp4, house_backyard.mp4, office.mp4, street.mp4, baby.mp4,
pets.mp4) and run one command:
    ... extract_demo_frames.py --videos-dir

Batch explicit paths instead:
    ... extract_demo_frames.py --map baby=a.mp4 street=b.mp4 pets=c.mp4

Quick smoke test with the bundled sample clip into every camera:
    ... extract_demo_frames.py --all-sample
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
FRAMES_ROOT = ROOT / "data" / "demo_frames"
DEFAULT_VIDEOS_DIR = ROOT / "data" / "demo_videos"
SAMPLE_VIDEO = ROOT.parent / "SentinelEdge_LaptopEdge" / "src" / "demo_videos" / "family_living_room_footage.mp4"

CAMERA_KEYS = ["house_frontdoor", "house_backyard", "office", "street", "baby", "pets"]
VIDEO_EXTS = (".mp4", ".mov", ".mkv", ".webm", ".avi", ".m4v")


def _import_cv2():
    try:
        import cv2  # noqa: PLC0415
    except ImportError:
        sys.exit(
            "opencv (cv2) is required. Run this with the LaptopEdge venv, e.g.\n"
            "  ../SentinelEdge_LaptopEdge/.venv/Scripts/python.exe scripts/extract_demo_frames.py ..."
        )
    return cv2


def extract(cv2, camera: str, video: Path, fps: float, width: int, max_frames: int) -> int:
    if not video.exists():
        sys.exit(f"video not found: {video}")
    out_dir = FRAMES_ROOT / camera
    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("*.jpg"):
        old.unlink()

    cap = cv2.VideoCapture(str(video))
    if not cap.isOpened():
        sys.exit(f"could not open video: {video}")
    src_fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
    stride = max(1, round(src_fps / max(0.1, fps)))

    written = 0
    read_idx = 0
    while written < max_frames:
        ok, frame = cap.read()
        if not ok:
            break
        if read_idx % stride == 0:
            h, w = frame.shape[:2]
            if w > width:
                frame = cv2.resize(frame, (width, round(h * width / w)), interpolation=cv2.INTER_AREA)
            cv2.imwrite(str(out_dir / f"frame_{written:04d}.jpg"), frame, [cv2.IMWRITE_JPEG_QUALITY, 75])
            written += 1
        read_idx += 1
    cap.release()

    if written == 0:
        sys.exit(f"no frames extracted from {video}")
    print(f"  {camera:11} <- {video.name}: {written} frames @ ~{fps:g}fps, {width}px -> {out_dir}")
    return written


def _scan_dir(videos_dir: Path) -> dict[str, Path]:
    """Map <camera_key>.<ext> files in a folder to their camera keys."""

    if not videos_dir.is_dir():
        sys.exit(f"videos dir not found: {videos_dir}")
    found: dict[str, Path] = {}
    for path in sorted(videos_dir.iterdir()):
        if path.suffix.lower() in VIDEO_EXTS and path.stem in CAMERA_KEYS:
            found[path.stem] = path
    if not found:
        sys.exit(
            f"no videos named <camera_key>.<ext> in {videos_dir}.\n"
            f"Name each clip after its camera, e.g. baby.mp4, street.mp4. Keys: {', '.join(CAMERA_KEYS)}"
        )
    skipped = [
        p.name for p in videos_dir.iterdir()
        if p.suffix.lower() in VIDEO_EXTS and p.stem not in CAMERA_KEYS
    ]
    if skipped:
        print(f"  (ignored {len(skipped)} file(s) whose name isn't a camera key: {', '.join(skipped)})")
    return found


def _parse_map(pairs: list[str]) -> dict[str, Path]:
    mapping: dict[str, Path] = {}
    for pair in pairs:
        if "=" not in pair:
            sys.exit(f"--map entries must be key=path, got: {pair!r}")
        key, path = pair.split("=", 1)
        mapping[key.strip()] = Path(path.strip())
    return mapping


def main() -> None:
    ap = argparse.ArgumentParser(description="Pre-extract JPEG frames for backend demo simulation.")
    ap.add_argument("--camera", help=f"single camera key ({', '.join(CAMERA_KEYS)})")
    ap.add_argument("--video", help="video file for --camera")
    ap.add_argument("--map", nargs="+", default=None, metavar="KEY=VIDEO", help="batch: key=path ...")
    ap.add_argument(
        "--videos-dir",
        nargs="?",
        const=str(DEFAULT_VIDEOS_DIR),
        default=None,
        metavar="DIR",
        help=f"scan a folder for <camera_key>.<ext> clips (default {DEFAULT_VIDEOS_DIR}).",
    )
    ap.add_argument("--all-sample", action="store_true", help="extract the bundled sample clip into every camera")
    ap.add_argument("--fps", type=float, default=10.0, help="frames per second to extract (default 10)")
    ap.add_argument("--width", type=int, default=640, help="max frame width in px (default 640)")
    ap.add_argument("--max-frames", type=int, default=300, help="cap frames per camera (default 300)")
    args = ap.parse_args()

    cv2 = _import_cv2()

    jobs: dict[str, Path] = {}
    if args.all_sample:
        jobs = {key: SAMPLE_VIDEO for key in CAMERA_KEYS}
    elif args.videos_dir:
        jobs = _scan_dir(Path(args.videos_dir))
    elif args.map:
        jobs = _parse_map(args.map)
    elif args.camera and args.video:
        jobs = {args.camera: Path(args.video)}
    else:
        ap.error("provide --camera + --video, or --map key=path..., or --videos-dir DIR, or --all-sample")

    print(f"Extracting demo frames into {FRAMES_ROOT} ...")
    total = 0
    for camera, video in jobs.items():
        total += extract(cv2, camera, video, args.fps, args.width, args.max_frames)
    print(f"Done. {total} frames across {len(jobs)} camera(s).")
    print("Enable it on the backend with DEMO_SIMULATION_ENABLED=true, then open a camera's live view.")


if __name__ == "__main__":
    main()
