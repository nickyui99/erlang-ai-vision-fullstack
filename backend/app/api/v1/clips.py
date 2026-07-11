from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db_session
from app.core.config import REPO_ROOT, settings
from app.models.clip import Clip
from app.models.user import User
from app.schemas.media import ClipDownloadUrlRead, ClipPlaybackUrlRead
from app.core.security import create_signed_token, verify_signed_token
from app.services import media_retention_service
from app.services.media_url_service import media_url_service


router = APIRouter(prefix="/clips", tags=["clips"])

_PLAYBACK_TOKEN_PURPOSE = "clip_playback"
_DOWNLOAD_TOKEN_PURPOSE = "clip_download"
_DEV_SAMPLE_VIDEO = REPO_ROOT.parent / "SentinelEdge_LaptopEdge" / "src" / "demo_videos" / "family_living_room_footage.mp4"


@router.post("/{clip_id}/signed-url")
async def signed_clip_playback_url(
    clip_id: str,
    request: Request,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    result = await session.execute(select(Clip).where(Clip.clip_id == clip_id, Clip.user_id == current_user.user_id))
    clip = result.scalar_one_or_none()
    if clip is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Clip was not found"},
        )
    if clip.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Clip was not found"},
        )
    if media_retention_service.is_expired(clip.expires_at):
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail={"code": "clip_expired", "message": "Clip has passed its retention period"},
        )
    if clip.status != "available" or not clip.oss_object_key:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "clip_unavailable", "message": "Clip is not available for playback"},
        )

    if settings.app_env == "development" and not media_url_service.oss_configured and _DEV_SAMPLE_VIDEO.exists():
        token = create_signed_token(
            {
                "clip_id": clip.clip_id,
                "user_id": current_user.user_id,
                "object_key": clip.oss_object_key,
            },
            _PLAYBACK_TOKEN_PURPOSE,
            settings.signed_url_ttl_seconds,
        )
        base = str(request.base_url).rstrip("/")
        playback_url = f"{base}{settings.api_prefix}/clips/{clip.clip_id}/media?token={token}"
        expires_at = media_url_service._expires_at()
    else:
        playback_url, expires_at = media_url_service.playback_url(clip.oss_object_key)

    data = ClipPlaybackUrlRead(clip_id=clip.clip_id, playback_url=playback_url, expires_at=expires_at)
    return {"data": data.model_dump(mode="json")}



@router.post("/{clip_id}/download-url")
async def signed_clip_download_url(
    clip_id: str,
    request: Request,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    result = await session.execute(select(Clip).where(Clip.clip_id == clip_id, Clip.user_id == current_user.user_id))
    clip = result.scalar_one_or_none()
    if clip is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Clip was not found"},
        )
    if clip.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Clip was not found"},
        )
    if media_retention_service.is_expired(clip.expires_at):
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail={"code": "clip_expired", "message": "Clip has passed its retention period"},
        )
    if clip.status != "available" or not clip.oss_object_key:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "clip_unavailable", "message": "Clip is not available for download"},
        )

    if settings.app_env == "development" and not media_url_service.oss_configured and _DEV_SAMPLE_VIDEO.exists():
        token = create_signed_token(
            {
                "clip_id": clip.clip_id,
                "user_id": current_user.user_id,
                "object_key": clip.oss_object_key,
            },
            _DOWNLOAD_TOKEN_PURPOSE,
            settings.signed_url_ttl_seconds,
        )
        base = str(request.base_url).rstrip("/")
        download_url = f"{base}{settings.api_prefix}/clips/{clip.clip_id}/download?token={token}"
        expires_at = media_url_service._expires_at()
    else:
        download_url, expires_at = media_url_service.download_url(clip.oss_object_key)

    data = ClipDownloadUrlRead(clip_id=clip.clip_id, download_url=download_url, expires_at=expires_at)
    return {"data": data.model_dump(mode="json")}

@router.get("/{clip_id}/media")
async def stream_dev_clip_media(
    clip_id: str,
    token: str = Query(...),
    session: AsyncSession = Depends(get_db_session),
) -> FileResponse:
    payload = verify_signed_token(token, _PLAYBACK_TOKEN_PURPOSE)
    if payload is None or payload.get("clip_id") != clip_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_playback_token", "message": "Playback token is invalid or expired"},
        )

    user_id = payload.get("user_id")
    object_key = payload.get("object_key")
    if not isinstance(user_id, str) or not isinstance(object_key, str):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_playback_token", "message": "Playback token is invalid or expired"},
        )

    result = await session.execute(select(Clip).where(Clip.clip_id == clip_id, Clip.user_id == user_id))
    clip = result.scalar_one_or_none()
    if clip is None or clip.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Clip was not found"},
        )
    if media_retention_service.is_expired(clip.expires_at):
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail={"code": "clip_expired", "message": "Clip has passed its retention period"},
        )
    if clip.status != "available" or clip.oss_object_key != object_key:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "clip_unavailable", "message": "Clip is not available for playback"},
        )
    if settings.app_env != "development" or not _DEV_SAMPLE_VIDEO.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "media_not_found", "message": "Local playback media is not available"},
        )

    return FileResponse(
        path=Path(_DEV_SAMPLE_VIDEO),
        media_type=clip.mime_type or "video/mp4",
        filename=f"{clip.clip_id}.mp4",
        headers={"Cache-Control": "no-store"},
    )




@router.get("/{clip_id}/download")
async def download_dev_clip_media(
    clip_id: str,
    token: str = Query(...),
    session: AsyncSession = Depends(get_db_session),
) -> FileResponse:
    payload = verify_signed_token(token, _DOWNLOAD_TOKEN_PURPOSE)
    if payload is None or payload.get("clip_id") != clip_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_download_token", "message": "Download token is invalid or expired"},
        )

    user_id = payload.get("user_id")
    object_key = payload.get("object_key")
    if not isinstance(user_id, str) or not isinstance(object_key, str):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_download_token", "message": "Download token is invalid or expired"},
        )

    result = await session.execute(select(Clip).where(Clip.clip_id == clip_id, Clip.user_id == user_id))
    clip = result.scalar_one_or_none()
    if clip is None or clip.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Clip was not found"},
        )
    if media_retention_service.is_expired(clip.expires_at):
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail={"code": "clip_expired", "message": "Clip has passed its retention period"},
        )
    if clip.status != "available" or clip.oss_object_key != object_key:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "clip_unavailable", "message": "Clip is not available for download"},
        )
    if settings.app_env != "development" or not _DEV_SAMPLE_VIDEO.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "media_not_found", "message": "Local download media is not available"},
        )

    return FileResponse(
        path=Path(_DEV_SAMPLE_VIDEO),
        media_type=clip.mime_type or "video/mp4",
        filename=f"erlang-{clip.clip_id}.mp4",
        headers={"Cache-Control": "no-store"},
    )
