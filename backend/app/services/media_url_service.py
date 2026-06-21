from __future__ import annotations

from datetime import UTC, datetime, timedelta
from urllib.parse import quote

from app.core.config import settings


class PlaceholderMediaUrlService:
    """Dev-only URL signer with stable object-key semantics for later OSS swap-in."""

    def upload_url(self, object_key: str) -> tuple[str, datetime]:
        expires_at = self._expires_at()
        return (
            f"placeholder://upload/{quote(object_key, safe='')}?expires_at={quote(expires_at.isoformat())}",
            expires_at,
        )

    def playback_url(self, object_key: str) -> tuple[str, datetime]:
        expires_at = self._expires_at()
        return (
            f"placeholder://playback/{quote(object_key, safe='')}?expires_at={quote(expires_at.isoformat())}",
            expires_at,
        )

    def event_clip_object_key(
        self,
        *,
        user_id: str,
        device_id: str,
        event_id: str,
        clip_id: str,
        mime_type: str | None,
        clip_type: str,
    ) -> str:
        extension = _extension_for_mime_type(mime_type)
        prefix = "thumb" if clip_type == "thumbnail" else "clip"
        return f"events/{user_id}/{device_id}/{event_id}/{prefix}_{clip_id}{extension}"

    def _expires_at(self) -> datetime:
        return datetime.now(UTC) + timedelta(seconds=settings.signed_url_ttl_seconds)


def _extension_for_mime_type(mime_type: str | None) -> str:
    return {
        "video/mp4": ".mp4",
        "video/webm": ".webm",
        "image/jpeg": ".jpg",
        "image/png": ".png",
    }.get((mime_type or "").lower(), ".bin")


media_url_service = PlaceholderMediaUrlService()
