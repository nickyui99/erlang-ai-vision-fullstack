import os
import sys
from pathlib import Path

os.environ["APP_ENV"] = "test"
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))

from fastapi.testclient import TestClient  # noqa: E402
import pytest  # noqa: E402

from app.core.config import Settings, settings  # noqa: E402
from app.core.middleware import RateLimitMiddleware  # noqa: E402
from app.main import create_app  # noqa: E402


def test_production_disables_openapi(monkeypatch) -> None:
    monkeypatch.setattr(settings, "app_env", "production")
    app = create_app()
    assert app.openapi_url is None


def test_login_rate_limit_applies_only_in_production(monkeypatch) -> None:
    monkeypatch.setattr(settings, "app_env", "production")
    RateLimitMiddleware.reset()
    client = TestClient(create_app())

    for _ in range(10):
        assert client.post("/api/v1/auth/firebase/login").status_code == 401

    blocked = client.post("/api/v1/auth/firebase/login")
    assert blocked.status_code == 429
    assert int(blocked.headers["retry-after"]) >= 1

def test_qwen_event_rate_limit_applies_only_in_production(monkeypatch) -> None:
    monkeypatch.setattr(settings, "app_env", "production")
    RateLimitMiddleware.reset()
    client = TestClient(create_app())

    for _ in range(30):
        assert client.post("/api/v1/edge/events").status_code == 401

    assert client.post("/api/v1/edge/events").status_code == 429


def test_production_rejects_oversized_api_bodies(monkeypatch) -> None:
    monkeypatch.setattr(settings, "app_env", "production")
    monkeypatch.setattr(settings, "max_request_body_bytes", 8)
    client = TestClient(create_app())

    response = client.post(
        "/api/v1/auth/firebase/login",
        content="123456789",
        headers={"content-type": "application/json"},
    )
    assert response.status_code == 413
    assert response.json()["detail"]["code"] == "request_too_large"

def test_production_settings_reject_mock_qwen() -> None:
    config = {
        "APP_ENV": "production",
        "DATABASE_URL": "postgresql+asyncpg://user:pass@db/app",
        "SESSION_SECRET_KEY": "x" * 32,
        "FIREBASE_PROJECT_ID": "project",
        "GOOGLE_APPLICATION_CREDENTIALS": "/tmp/credentials.json",
        "ALICLOUD_OSS_ENDPOINT": "oss.example",
        "ALICLOUD_OSS_BUCKET": "bucket",
        "ALIBABA_CLOUD_ACCESS_KEY_ID": "id",
        "ALIBABA_CLOUD_ACCESS_KEY_SECRET": "secret",
        "CORS_ALLOWED_ORIGINS": "https://example.com",
        "CORS_ALLOWED_ORIGIN_REGEX": "",
        "QWEN_API_KEY": "key",
        "QWEN_BASE_URL": "https://dash.example/v1",
    }
    assert Settings(**config).app_env == "production"

    config.pop("QWEN_API_KEY")
    with pytest.raises(ValueError, match="QWEN_API_KEY"):
        Settings(**config)