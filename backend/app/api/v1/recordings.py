from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db_session
from app.core.config import REPO_ROOT, settings
from app.core.security import create_signed_token, verify_signed_token
from app.models.recording import Recording
from app.models.user import User
from app.schemas.media import RecordingPlaybackUrlRead
from app.services.media_url_service import media_url_service


router = APIRouter(prefix="/recordings", tags=["recordings"])

_RECORDING_PLAYBACK_TOKEN_PURPOSE = "recording_playback"
_DEV_SAMPLE_VIDEO = REPO_ROOT.parent / "SentinelEdge_LaptopEdge" / "src" / "demo_videos" / "family_living_room_footage.mp4"


@router.post("/{recording_id}/signed-url")
async def signed_recording_playback_url(
    recording_id: str,
    request: Request,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    result = await session.execute(
        select(Recording).where(
            Recording.recording_id == recording_id,
            Recording.user_id == current_user.user_id,
        )
    )
    recording = result.scalar_one_or_none()
    if recording is None or recording.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Recording was not found"},
        )

    if settings.app_env == "development" and _DEV_SAMPLE_VIDEO.exists():
        token = create_signed_token(
            {
                "recording_id": recording.recording_id,
                "user_id": current_user.user_id,
            },
            _RECORDING_PLAYBACK_TOKEN_PURPOSE,
            settings.signed_url_ttl_seconds,
        )
        base = str(request.base_url).rstrip("/")
        playback_url = f"{base}{settings.api_prefix}/recordings/{recording.recording_id}/media?token={token}"
        expires_at = media_url_service._expires_at()
    elif recording.oss_object_key:
        playback_url, expires_at = media_url_service.playback_url(recording.oss_object_key)
    else:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "recording_unavailable", "message": "Recording is not available for playback"},
        )

    data = RecordingPlaybackUrlRead(
        recording_id=recording.recording_id,
        playback_url=playback_url,
        expires_at=expires_at,
    )
    return {"data": data.model_dump(mode="json")}


@router.get("/{recording_id}/media")
async def stream_dev_recording_media(
    recording_id: str,
    token: str = Query(...),
    session: AsyncSession = Depends(get_db_session),
) -> FileResponse:
    payload = verify_signed_token(token, _RECORDING_PLAYBACK_TOKEN_PURPOSE)
    if payload is None or payload.get("recording_id") != recording_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_recording_token", "message": "Recording token is invalid or expired"},
        )

    user_id = payload.get("user_id")
    if not isinstance(user_id, str):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_recording_token", "message": "Recording token is invalid or expired"},
        )

    result = await session.execute(
        select(Recording).where(
            Recording.recording_id == recording_id,
            Recording.user_id == user_id,
        )
    )
    recording = result.scalar_one_or_none()
    if recording is None or recording.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Recording was not found"},
        )
    if settings.app_env != "development" or not _DEV_SAMPLE_VIDEO.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "media_not_found", "message": "Local recording media is not available"},
        )

    return FileResponse(
        path=Path(_DEV_SAMPLE_VIDEO),
        media_type=recording.mime_type or "video/mp4",
        filename=f"{recording.recording_id}.mp4",
        headers={"Cache-Control": "no-store"},
    )
