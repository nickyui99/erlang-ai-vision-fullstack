from fastapi import APIRouter

from app.api.v1 import agents, auth, devices, edge, health, users


api_router = APIRouter()
api_router.include_router(agents.router)
api_router.include_router(auth.router)
api_router.include_router(devices.router)
api_router.include_router(edge.router)
api_router.include_router(health.router, tags=["health"])
api_router.include_router(users.router)
