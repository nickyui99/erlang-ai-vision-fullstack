from fastapi import APIRouter, status
from sqlalchemy import text

from app.core.config import settings
from app.db.session import async_session_factory


router = APIRouter()


@router.get("/version")
async def version() -> dict:
    return {
        "data": {
            "app_name": settings.app_name,
            "version": settings.app_version,
            "environment": settings.app_env,
        },
    }


@router.get("/healthz", status_code=status.HTTP_200_OK)
async def healthz() -> dict:
    return {"data": {"status": "ok"}}


@router.get("/readyz", status_code=status.HTTP_200_OK)
async def readyz() -> dict:
    async with async_session_factory() as session:
        await session.execute(text("SELECT 1"))

    return {
        "data": {
            "status": "ready",
            "database": "ok",
        }
    }
