from __future__ import annotations

import asyncio

from fastapi import APIRouter, Depends, Request
from fastapi.responses import StreamingResponse

from app.api.deps import get_current_user
from app.models.user import User
from app.services.realtime_bus import realtime_bus


router = APIRouter(prefix="/stream", tags=["realtime"])


@router.get("/events")
async def stream_events(
    request: Request,
    current_user: User = Depends(get_current_user),
) -> StreamingResponse:
    subscription = await realtime_bus.subscribe(current_user.user_id)

    async def event_generator():
        try:
            yield "event: realtime.connected\ndata: {}\n\n"
            while not await request.is_disconnected():
                try:
                    event = await asyncio.wait_for(subscription.queue.get(), timeout=20)
                    yield event.to_sse()
                except asyncio.TimeoutError:
                    yield ": heartbeat\n\n"
        finally:
            await realtime_bus.unsubscribe(subscription)

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
