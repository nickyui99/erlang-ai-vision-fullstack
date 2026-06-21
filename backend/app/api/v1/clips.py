from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db_session
from app.models.clip import Clip
from app.models.user import User
from app.schemas.media import ClipPlaybackUrlRead
from app.services.media_url_service import media_url_service


router = APIRouter(prefix="/clips", tags=["clips"])


@router.post("/{clip_id}/signed-url")
async def signed_clip_playback_url(
    clip_id: str,
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
    if clip.status != "available" or not clip.oss_object_key:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "clip_unavailable", "message": "Clip is not available for playback"},
        )

    playback_url, expires_at = media_url_service.playback_url(clip.oss_object_key)
    data = ClipPlaybackUrlRead(clip_id=clip.clip_id, playback_url=playback_url, expires_at=expires_at)
    return {"data": data.model_dump(mode="json")}
