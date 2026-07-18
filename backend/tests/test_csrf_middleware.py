import os
import sys
from pathlib import Path

os.environ["APP_ENV"] = "test"
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))

from fastapi.testclient import TestClient  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.main import app  # noqa: E402


def test_cookie_mutation_rejects_missing_or_untrusted_origin(monkeypatch) -> None:
    monkeypatch.setattr(settings, "app_env", "production")
    monkeypatch.setattr(settings, "cors_allowed_origins", "https://app.example.com")
    client = TestClient(app)
    client.cookies.set(settings.session_cookie_name, "signed-session")

    missing = client.post("/api/v1/auth/logout")
    untrusted = client.post("/api/v1/auth/logout", headers={"Origin": "https://attacker.example"})

    assert missing.status_code == 403
    assert untrusted.status_code == 403
    assert missing.json()["detail"]["code"] == "csrf_origin_rejected"


def test_cookie_mutation_allows_the_configured_origin(monkeypatch) -> None:
    monkeypatch.setattr(settings, "app_env", "production")
    monkeypatch.setattr(settings, "cors_allowed_origins", "https://app.example.com")
    client = TestClient(app)
    client.cookies.set(settings.session_cookie_name, "signed-session")

    response = client.post("/api/v1/auth/logout", headers={"Origin": "https://app.example.com"})

    assert response.status_code == 204