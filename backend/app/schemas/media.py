from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


ClipType = Literal["event", "thumbnail"]
StorageType = Literal["local_edge", "oss", "pending_upload"]


class EdgeClipUploadCreate(BaseModel):
    event_id: str = Field(min_length=1, max_length=64)
    clip_type: ClipType = "event"
    mime_type: str | None = Field(default=None, max_length=255)
    duration_seconds: int | None = Field(default=None, ge=0)
    file_size_bytes: int | None = Field(default=None, ge=0)
    checksum_sha256: str | None = Field(default=None, min_length=64, max_length=64)
    idempotency_key: str = Field(min_length=1, max_length=255)


class EdgeClipComplete(BaseModel):
    file_size_bytes: int | None = Field(default=None, ge=0)
    checksum_sha256: str | None = Field(default=None, min_length=64, max_length=64)


class ClipRead(BaseModel):
    clip_id: str
    event_id: str
    user_id: str
    device_id: str
    idempotency_key: str | None = None
    storage_type: str
    storage_path: str | None = None
    oss_object_key: str | None = None
    clip_type: str
    duration_seconds: int | None = None
    file_size_bytes: int | None = None
    mime_type: str | None = None
    checksum_sha256: str | None = None
    status: str
    upload_id: str | None = None
    upload_started_at: datetime | None = None
    upload_completed_at: datetime | None = None
    upload_expires_at: datetime | None = None
    upload_error: str | None = None
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
    expires_at: datetime | None = None

    model_config = ConfigDict(from_attributes=True)


class ClipUploadUrlRead(BaseModel):
    clip_id: str
    upload_url: str
    oss_object_key: str
    upload_expires_at: datetime
    clip: ClipRead


class ClipPlaybackUrlRead(BaseModel):
    clip_id: str
    playback_url: str
    expires_at: datetime


class ClipDownloadUrlRead(BaseModel):
    clip_id: str
    download_url: str
    expires_at: datetime


class RecordingPlaybackUrlRead(BaseModel):
    recording_id: str
    playback_url: str
    expires_at: datetime

class EdgeRecordingCreate(BaseModel):
    recording_id: str | None = Field(default=None, max_length=64)
    start_time: datetime
    end_time: datetime
    storage_type: StorageType = "local_edge"
    storage_path: str | None = None
    oss_object_key: str | None = None
    duration_seconds: int | None = Field(default=None, ge=0)
    file_size_bytes: int | None = Field(default=None, ge=0)
    mime_type: str | None = Field(default=None, max_length=255)
    checksum_sha256: str | None = Field(default=None, min_length=64, max_length=64)
    status: str = Field(default="local_only", max_length=32)


class RecordingRead(BaseModel):
    recording_id: str
    user_id: str
    device_id: str
    start_time: datetime
    end_time: datetime
    storage_type: str
    storage_path: str | None = None
    oss_object_key: str | None = None
    duration_seconds: int | None = None
    file_size_bytes: int | None = None
    mime_type: str | None = None
    checksum_sha256: str | None = None
    status: str
    retention_until: datetime | None = None
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None

    model_config = ConfigDict(from_attributes=True)
