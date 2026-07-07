"""Milestone 10 — media retention enforcement.

Marks expired media rows so lists and playback stop serving them. Byte deletion
in OSS is owned by the bucket lifecycle rules (scripts/deployment/media-bucket.ps1);
this sweep never talks to OSS and needs no delete credentials.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta
import logging

from sqlalchemy import update

from app.core.config import settings
from app.db.session import async_session_factory
from app.models.clip import Clip
from app.models.recording import Recording


_logger = logging.getLogger(__name__)

_STALE_UPLOAD_AGE = timedelta(hours=24)


def is_expired(moment: datetime | None) -> bool:
    if moment is None:
        return False
    aware = moment if moment.tzinfo else moment.replace(tzinfo=UTC)
    return aware <= datetime.now(UTC)


async def sweep_expired_media() -> dict[str, int]:
    now = datetime.now(UTC)
    async with async_session_factory() as session:
        expired_clips = await session.execute(
            update(Clip)
            .where(Clip.deleted_at.is_(None), Clip.expires_at.is_not(None), Clip.expires_at < now)
            .values(status="deleted", deleted_at=now, updated_at=now)
            .execution_options(synchronize_session=False)
        )
        stale_uploads = await session.execute(
            update(Clip)
            .where(
                Clip.deleted_at.is_(None),
                Clip.status.in_(("pending_upload", "uploading")),
                Clip.created_at < now - _STALE_UPLOAD_AGE,
            )
            .values(status="failed", upload_error="upload window expired", updated_at=now)
            .execution_options(synchronize_session=False)
        )
        expired_recordings = await session.execute(
            update(Recording)
            .where(
                Recording.deleted_at.is_(None),
                Recording.retention_until.is_not(None),
                Recording.retention_until < now,
            )
            .values(status="deleted", deleted_at=now, updated_at=now)
            .execution_options(synchronize_session=False)
        )
        await session.commit()
    return {
        "expired_clips": expired_clips.rowcount,
        "stale_uploads": stale_uploads.rowcount,
        "expired_recordings": expired_recordings.rowcount,
    }


async def run_sweep_loop() -> None:
    while True:
        try:
            counts = await sweep_expired_media()
            if any(counts.values()):
                _logger.info("media retention sweep: %s", counts)
        except Exception:
            _logger.exception("media retention sweep failed")
        await asyncio.sleep(settings.media_sweep_interval_seconds)
