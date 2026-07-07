from functools import lru_cache
import os
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

from app.core.alicloud_secrets import load_alicloud_kms_secret


REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_SQLITE_URL = f"sqlite+aiosqlite:///{(REPO_ROOT / 'data' / 'sentineledge_demo.db').as_posix()}"
ENV_FILE = REPO_ROOT / ".env"


if os.environ.get("APP_ENV") != "test":
    load_alicloud_kms_secret(ENV_FILE)


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
        default=DEFAULT_SQLITE_URL,
        validation_alias="DATABASE_URL",
    )

    firebase_project_id: str = Field(default="", validation_alias="FIREBASE_PROJECT_ID")
    google_application_credentials: str = Field(default="", validation_alias="GOOGLE_APPLICATION_CREDENTIALS")

    session_secret_key: str = Field(default="change-me", validation_alias="SESSION_SECRET_KEY")
    session_cookie_name: str = Field(default="sentineledge_session", validation_alias="SESSION_COOKIE_NAME")
    session_expire_minutes: int = Field(default=1440, validation_alias="SESSION_EXPIRE_MINUTES")

    alerts_enabled: bool = Field(default=True, validation_alias="ALERTS_ENABLED")
    alert_min_severity: str = Field(default="high", validation_alias="ALERT_MIN_SEVERITY")

    # Milestone 9 — Qwen Cloud verification (DashScope OpenAI-compatible).
    # Verification is opt-in: it stays off until VERIFICATION_ENABLED=true so the
    # default ingestion/alert path is unchanged. Without a QWEN_API_KEY the
    # service falls back to a deterministic mock verdict (handy for offline demos).
    verification_enabled: bool = Field(default=False, validation_alias="VERIFICATION_ENABLED")
    verify_min_severity: str = Field(default="high", validation_alias="VERIFY_MIN_SEVERITY")
    qwen_api_key: str = Field(default="", validation_alias="QWEN_API_KEY")
    qwen_base_url: str = Field(
        default="https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
        validation_alias="QWEN_BASE_URL",
    )
    qwen_model: str = Field(default="qwen-vl-max", validation_alias="QWEN_MODEL")
    # NL-rule compilation is text-only, so it uses a cheaper text model (not the vision model).
    # Falls back to a deterministic keyword compiler in test/key-less environments.
    qwen_compiler_model: str = Field(default="qwen-plus", validation_alias="QWEN_COMPILER_MODEL")
    qwen_timeout_seconds: float = Field(default=20, validation_alias="QWEN_TIMEOUT_SECONDS")
    qwen_max_tool_turns: int = Field(default=4, validation_alias="QWEN_MAX_TOOL_TURNS")

    # MCP actuation guardrails (Milestone 9B). Pan is rate-limited per event.
    mcp_max_pans_per_event: int = Field(default=3, validation_alias="MCP_MAX_PANS_PER_EVENT")
    mcp_min_seconds_between_pans: float = Field(default=5, validation_alias="MCP_MIN_SECONDS_BETWEEN_PANS")

    signed_url_ttl_seconds: int = Field(default=900, validation_alias="SIGNED_URL_TTL_SECONDS")
    media_retention_days: int = Field(default=7, validation_alias="MEDIA_RETENTION_DAYS")
    daily_recording_retention_hours: int = Field(
        default=72,
        validation_alias="DAILY_RECORDING_RETENTION_HOURS",
    )

    # Demo simulation (judge/demo account only). When enabled, the backend can
    # play pre-extracted video frames into a demo camera's live view and triage
    # them with the cloud VLM API — no laptop edge required. Strictly gated to
    # devices whose id starts with demo_sim_device_prefix AND that have a frame
    # folder under data/demo_frames/, so normal accounts are never affected.
    demo_simulation_enabled: bool = Field(default=False, validation_alias="DEMO_SIMULATION_ENABLED")
    demo_sim_device_prefix: str = Field(default="dev_judge_", validation_alias="DEMO_SIM_DEVICE_PREFIX")
    # Where the pre-extracted demo frames live. Empty -> REPO_ROOT/data/demo_frames
    # (local dev). The Docker image sets this to the path it copies frames into.
    demo_frames_dir: str = Field(default="", validation_alias="DEMO_FRAMES_DIR")
    demo_sim_fps: float = Field(default=10.0, validation_alias="DEMO_SIM_FPS")
    demo_sim_triage_interval_seconds: float = Field(default=15.0, validation_alias="DEMO_SIM_TRIAGE_INTERVAL_SECONDS")
    # Faster cadence until the first detection lands, so opening a camera surfaces
    # an event quickly; then it settles to the slower steady-state interval above.
    demo_sim_first_triage_interval_seconds: float = Field(default=3.0, validation_alias="DEMO_SIM_FIRST_TRIAGE_INTERVAL_SECONDS")
    demo_sim_event_cooldown_seconds: float = Field(default=45.0, validation_alias="DEMO_SIM_EVENT_COOLDOWN_SECONDS")
    demo_sim_idle_timeout_seconds: float = Field(default=30.0, validation_alias="DEMO_SIM_IDLE_TIMEOUT_SECONDS")

    alibaba_cloud_access_key_id: str = Field(default="", validation_alias="ALIBABA_CLOUD_ACCESS_KEY_ID")
    alibaba_cloud_access_key_secret: str = Field(default="", validation_alias="ALIBABA_CLOUD_ACCESS_KEY_SECRET")
    alicloud_oss_endpoint: str = Field(default="", validation_alias="ALICLOUD_OSS_ENDPOINT")
    alicloud_oss_bucket: str = Field(default="", validation_alias="ALICLOUD_OSS_BUCKET")
    alicloud_oss_secure: bool = Field(default=True, validation_alias="ALICLOUD_OSS_SECURE")
    model_config = SettingsConfigDict(
        env_file=ENV_FILE,
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

