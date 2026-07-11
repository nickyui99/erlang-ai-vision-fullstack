from __future__ import annotations

import base64
from datetime import UTC, datetime, timedelta
import hmac
import hashlib
from urllib.parse import quote

from app.core.config import settings


class MediaUrlService:
    """Generate upload, playback, and download URLs for media objects.

    If Alibaba OSS is configured, this signs direct OSS URLs. Otherwise it keeps
    the placeholder URLs used by local tests and offline demos.
    """

    def upload_url(self, object_key: str) -> tuple[str, datetime]:
        expires_at = self._expires_at()
        if self.oss_configured:
            return self._signed_oss_url("PUT", object_key, expires_at), expires_at
        return self._placeholder_url("upload", object_key, expires_at), expires_at

    def playback_url(self, object_key: str) -> tuple[str, datetime]:
        expires_at = self._expires_at()
        if self.oss_configured:
            return self._signed_oss_url("GET", object_key, expires_at), expires_at
        return self._placeholder_url("playback", object_key, expires_at), expires_at

    def download_url(self, object_key: str) -> tuple[str, datetime]:
        expires_at = self._expires_at()
        if self.oss_configured:
            return self._signed_oss_url("GET", object_key, expires_at, download=True), expires_at
        return self._placeholder_url("download", object_key, expires_at), expires_at

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

    def recording_object_key(self, *, user_id: str, device_id: str, recording_id: str, start_time: datetime) -> str:
        stamp = start_time.astimezone(UTC).strftime("%Y%m%dT%H%M%SZ")
        return f"recordings/{user_id}/{device_id}/{stamp}_{recording_id}.mp4"

    def _expires_at(self) -> datetime:
        return datetime.now(UTC) + timedelta(seconds=settings.signed_url_ttl_seconds)

    @property
    def oss_configured(self) -> bool:
        return bool(
            settings.alicloud_oss_endpoint
            and settings.alicloud_oss_bucket
            and settings.alibaba_cloud_access_key_id
            and settings.alibaba_cloud_access_key_secret
        )

    def _placeholder_url(self, action: str, object_key: str, expires_at: datetime) -> str:
        return f"placeholder://{action}/{quote(object_key, safe='')}?expires_at={quote(expires_at.isoformat())}"

    def _signed_oss_url(
        self,
        method: str,
        object_key: str,
        expires_at: datetime,
        *,
        download: bool = False,
    ) -> str:
        expires = str(int(expires_at.timestamp()))
        bucket = settings.alicloud_oss_bucket
        response_params: dict[str, str] = {}
        if download:
            filename = object_key.rsplit("/", 1)[-1] or "erlang-media.mp4"
            response_params["response-content-disposition"] = f"attachment; filename=\"{filename}\""

        resource = f"/{bucket}/{object_key}"
        if response_params:
            canonical_params = "&".join(f"{key}={value}" for key, value in sorted(response_params.items()))
            resource = f"{resource}?{canonical_params}"
        string_to_sign = f"{method}\n\n\n{expires}\n{resource}"
        digest = hmac.new(
            settings.alibaba_cloud_access_key_secret.encode("utf-8"),
            string_to_sign.encode("utf-8"),
            hashlib.sha1,
        ).digest()
        signature = base64.b64encode(digest).decode("ascii")
        endpoint = _normalize_endpoint(settings.alicloud_oss_endpoint, secure=settings.alicloud_oss_secure)
        url = f"{endpoint}/{quote(object_key, safe='/')}"
        query_parts = [
            f"OSSAccessKeyId={quote(settings.alibaba_cloud_access_key_id, safe='')}",
            f"Expires={expires}",
            f"Signature={quote(signature, safe='')}",
        ]
        query_parts.extend(f"{key}={quote(value, safe='')}" for key, value in sorted(response_params.items()))
        return f"{url}?{'&'.join(query_parts)}"


def _normalize_endpoint(endpoint: str, *, secure: bool) -> str:
    endpoint = endpoint.strip().rstrip("/")
    if endpoint.startswith("http://") or endpoint.startswith("https://"):
        return endpoint
    scheme = "https" if secure else "http"
    bucket = settings.alicloud_oss_bucket
    if endpoint.startswith(f"{bucket}."):
        return f"{scheme}://{endpoint}"
    return f"{scheme}://{bucket}.{endpoint}"


def _extension_for_mime_type(mime_type: str | None) -> str:
    return {
        "video/mp4": ".mp4",
        "video/webm": ".webm",
        "image/jpeg": ".jpg",
        "image/png": ".png",
    }.get((mime_type or "").lower(), ".bin")


media_url_service = MediaUrlService()