from fastapi import APIRouter

from app.api.v1 import agents, auth, clips, devices, edge, events, health, notifications, stream, users


api_router = APIRouter()
api_router.include_router(agents.router)
api_router.include_router(auth.router)
api_router.include_router(clips.router)
api_router.include_router(devices.router)
api_router.include_router(edge.router)
api_router.include_router(events.router)
api_router.include_router(health.router, tags=["health"])
api_router.include_router(notifications.router)
api_router.include_router(stream.router)
api_router.include_router(users.router)
