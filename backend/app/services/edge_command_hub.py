from __future__ import annotations

import asyncio
from dataclasses import dataclass
import threading
from typing import Any

from fastapi import WebSocket


class EdgeNotConnectedError(Exception):
    pass


class EdgeCommandTimeoutError(Exception):
    pass


@dataclass
class EdgeConnection:
    device_id: str
    websocket: WebSocket


class EdgeCommandHub:
    def __init__(self, timeout_seconds: float = 10) -> None:
        self._timeout_seconds = timeout_seconds
        self._connections: dict[str, EdgeConnection] = {}
        self._pending: dict[str, asyncio.Future[dict[str, Any]]] = {}
        self._pending_devices: dict[str, str] = {}
        self._lock = threading.Lock()

    async def connect(self, device_id: str, websocket: WebSocket) -> None:
        old_websocket: WebSocket | None = None
        with self._lock:
            old_connection = self._connections.get(device_id)
            if old_connection is not None and old_connection.websocket is not websocket:
                old_websocket = old_connection.websocket
                self._fail_pending_for_device(device_id, EdgeNotConnectedError("Edge connection was replaced"))
            self._connections[device_id] = EdgeConnection(device_id=device_id, websocket=websocket)

        if old_websocket is not None:
            await old_websocket.close(code=1000)

    async def disconnect(self, device_id: str, websocket: WebSocket) -> None:
        with self._lock:
            current = self._connections.get(device_id)
            if current is not None and current.websocket is websocket:
                self._connections.pop(device_id, None)
                self._fail_pending_for_device(device_id, EdgeNotConnectedError("Edge disconnected"))

    async def send_command(self, device_id: str, message: dict[str, Any]) -> dict[str, Any]:
        request_id = message["request_id"]
        loop = asyncio.get_running_loop()
        future: asyncio.Future[dict[str, Any]] = loop.create_future()

        with self._lock:
            connection = self._connections.get(device_id)
            if connection is None:
                raise EdgeNotConnectedError("Edge is not connected")
            self._pending[request_id] = future
            self._pending_devices[request_id] = device_id
            websocket = connection.websocket

        try:
            await websocket.send_json(message)
            return await asyncio.wait_for(future, timeout=self._timeout_seconds)
        except TimeoutError as exc:
            raise EdgeCommandTimeoutError("Edge command timed out") from exc
        except RuntimeError as exc:
            raise EdgeNotConnectedError("Edge is not connected") from exc
        finally:
            with self._lock:
                self._pending.pop(request_id, None)
                self._pending_devices.pop(request_id, None)

    async def handle_result(self, message: dict[str, Any]) -> None:
        request_id = message.get("request_id")
        if not isinstance(request_id, str):
            return

        with self._lock:
            future = self._pending.get(request_id)
            if future is None or future.done():
                return
            result = {
                "request_id": request_id,
                "status": message.get("status", "unknown"),
                "payload": message.get("payload") if isinstance(message.get("payload"), dict) else {},
            }
            future.get_loop().call_soon_threadsafe(future.set_result, result)

    def _fail_pending_for_device(self, device_id: str, exc: Exception) -> None:
        request_ids = [
            request_id for request_id, pending_device_id in self._pending_devices.items() if pending_device_id == device_id
        ]
        for request_id in request_ids:
            future = self._pending.pop(request_id, None)
            self._pending_devices.pop(request_id, None)
            if future is not None and not future.done():
                future.get_loop().call_soon_threadsafe(future.set_exception, exc)


edge_command_hub = EdgeCommandHub()
