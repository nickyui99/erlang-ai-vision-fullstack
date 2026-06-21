from __future__ import annotations

import asyncio
from collections import defaultdict
from dataclasses import dataclass
from datetime import UTC, datetime
import itertools
import json
from typing import Any


@dataclass(frozen=True)
class RealtimeEvent:
    event: str
    data: dict[str, Any]
    event_id: str

    def to_sse(self) -> str:
        payload = json.dumps(self.data, separators=(",", ":"), default=str)
        return f"id: {self.event_id}\nevent: {self.event}\ndata: {payload}\n\n"


class RealtimeSubscription:
    def __init__(self, user_id: str, queue: asyncio.Queue[RealtimeEvent]) -> None:
        self.user_id = user_id
        self.queue = queue


class RealtimeBus:
    def __init__(self, queue_size: int = 100) -> None:
        self._queue_size = queue_size
        self._subscribers: dict[str, set[asyncio.Queue[RealtimeEvent]]] = defaultdict(set)
        self._lock = asyncio.Lock()
        self._counter = itertools.count(1)

    async def subscribe(self, user_id: str) -> RealtimeSubscription:
        queue: asyncio.Queue[RealtimeEvent] = asyncio.Queue(maxsize=self._queue_size)
        async with self._lock:
            self._subscribers[user_id].add(queue)
        return RealtimeSubscription(user_id=user_id, queue=queue)

    async def unsubscribe(self, subscription: RealtimeSubscription) -> None:
        async with self._lock:
            queues = self._subscribers.get(subscription.user_id)
            if queues is None:
                return
            queues.discard(subscription.queue)
            if not queues:
                self._subscribers.pop(subscription.user_id, None)

    async def publish(self, user_id: str, event: str, data: dict[str, Any]) -> None:
        realtime_event = RealtimeEvent(
            event=event,
            data={**data, "emitted_at": datetime.now(UTC).isoformat()},
            event_id=f"rt_{next(self._counter)}",
        )
        async with self._lock:
            queues = list(self._subscribers.get(user_id, set()))

        for queue in queues:
            if queue.full():
                try:
                    queue.get_nowait()
                except asyncio.QueueEmpty:
                    pass
            try:
                queue.put_nowait(realtime_event)
            except asyncio.QueueFull:
                pass


realtime_bus = RealtimeBus()
