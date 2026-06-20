from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_env: str = Field(default="development", validation_alias="APP_ENV")
    app_name: str = Field(default="SentinelEdge Backend", validation_alias="APP_NAME")
    app_version: str = Field(default="0.1.0", validation_alias="APP_VERSION")
    api_prefix: str = Field(default="/api/v1", validation_alias="API_PREFIX")
    cors_allowed_origins: str = Field(
        default="http://localhost:3000,http://localhost:5000,http://localhost:5173,http://localhost:8080,http://localhost:8081,http://localhost:8082,http://localhost:8083,http://localhost:8084,http://localhost:8085",
        validation_alias="CORS_ALLOWED_ORIGINS",
    )
    cors_allowed_origin_regex: str = Field(
        default=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
        validation_alias="CORS_ALLOWED_ORIGIN_REGEX",
    )

    database_url: str = Field(
        default="sqlite+aiosqlite:///./data/sentineledge_demo.db",
        validation_alias="DATABASE_URL",
    )

    firebase_project_id: str = Field(default="", validation_alias="FIREBASE_PROJECT_ID")
    google_application_credentials: str = Field(default="", validation_alias="GOOGLE_APPLICATION_CREDENTIALS")

    session_secret_key: str = Field(default="change-me", validation_alias="SESSION_SECRET_KEY")
    session_cookie_name: str = Field(default="sentineledge_session", validation_alias="SESSION_COOKIE_NAME")
    session_expire_minutes: int = Field(default=1440, validation_alias="SESSION_EXPIRE_MINUTES")

    signed_url_ttl_seconds: int = Field(default=900, validation_alias="SIGNED_URL_TTL_SECONDS")
    media_retention_days: int = Field(default=7, validation_alias="MEDIA_RETENTION_DAYS")
    daily_recording_retention_hours: int = Field(
        default=72,
        validation_alias="DAILY_RECORDING_RETENTION_HOURS",
    )

    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parents[3] / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @property
    def cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.cors_allowed_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
