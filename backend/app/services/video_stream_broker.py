from __future__ import annotations

import asyncio
from collections import defaultdict


class VideoStreamBroker:
    """In-memory fan-out of JPEG frames per device.

    Edge devices push frames over the edge stream WebSocket; browser viewers
    pull them as MJPEG. One upstream publisher fans out to any number of
    viewers, and the latest frame is retained so a new viewer paints instantly.
    Slow viewers drop the oldest frame rather than build latency.
    """

    def __init__(self, queue_size: int = 2) -> None:
        self._queue_size = queue_size
        self._subscribers: dict[str, set[asyncio.Queue[bytes]]] = defaultdict(set)
        self._latest: dict[str, bytes] = {}
        self._publishers: dict[str, int] = defaultdict(int)
        self._lock = asyncio.Lock()

    async def start_publishing(self, device_id: str) -> None:
        async with self._lock:
            self._publishers[device_id] += 1

    async def stop_publishing(self, device_id: str) -> None:
        async with self._lock:
            remaining = self._publishers.get(device_id, 0) - 1
            if remaining <= 0:
                self._publishers.pop(device_id, None)
                self._latest.pop(device_id, None)
            else:
                self._publishers[device_id] = remaining

    def is_publishing(self, device_id: str) -> bool:
        return self._publishers.get(device_id, 0) > 0

    def latest_frame(self, device_id: str) -> bytes | None:
        return self._latest.get(device_id)

    async def publish(self, device_id: str, frame: bytes) -> None:
        async with self._lock:
            self._latest[device_id] = frame
            queues = list(self._subscribers.get(device_id, set()))

        for queue in queues:
            if queue.full():
                try:
                    queue.get_nowait()
                except asyncio.QueueEmpty:
                    pass
            try:
                queue.put_nowait(frame)
            except asyncio.QueueFull:
                pass

    async def subscribe(self, device_id: str) -> asyncio.Queue[bytes]:
        queue: asyncio.Queue[bytes] = asyncio.Queue(maxsize=self._queue_size)
        async with self._lock:
            self._subscribers[device_id].add(queue)
            latest = self._latest.get(device_id)
        if latest is not None:
            try:
                queue.put_nowait(latest)
            except asyncio.QueueFull:
                pass
        return queue

    async def unsubscribe(self, device_id: str, queue: asyncio.Queue[bytes]) -> None:
        async with self._lock:
            queues = self._subscribers.get(device_id)
            if queues is None:
                return
            queues.discard(queue)
            if not queues:
                self._subscribers.pop(device_id, None)


video_stream_broker = VideoStreamBroker()

