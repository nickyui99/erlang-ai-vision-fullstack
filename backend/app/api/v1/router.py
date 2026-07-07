from fastapi import APIRouter

from app.api.v1 import agents, auth, chat, clips, devices, edge, events, health, notifications, recordings, stream, system, users


api_router = APIRouter()
api_router.include_router(agents.router)
api_router.include_router(auth.router)
api_router.include_router(chat.router)
api_router.include_router(clips.router)
api_router.include_router(devices.router)
api_router.include_router(edge.router)
api_router.include_router(events.router)
api_router.include_router(health.router, tags=["health"])
api_router.include_router(notifications.router)
api_router.include_router(recordings.router)
api_router.include_router(stream.router)
api_router.include_router(system.router)
api_router.include_router(users.router)
