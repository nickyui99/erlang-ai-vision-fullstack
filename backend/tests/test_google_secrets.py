import base64
import json
import os
from pathlib import Path
import sys
from types import SimpleNamespace

import pytest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))

from app.core.google_secrets import load_google_secret_manager_secrets  # noqa: E402


@pytest.fixture(autouse=True)
def clean_secret_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    for key in (
        "APP_ENV",
        "DATABASE_URL",
        "GOOGLE_APPLICATION_CREDENTIALS",
        "GOOGLE_SECRET_MANAGER_PROJECT",
        "GOOGLE_SECRET_MANAGER_SECRETS",
        "GOOGLE_SECRET_MANAGER_CREDENTIALS_B64",
        "GOOGLE_SECRET_MANAGER_CREDENTIALS_FILE",
        "QWEN_API_KEY",
        "SESSION_SECRET_KEY",
        "FIREBASE_PROJECT_ID",
        "ALIBABA_CLOUD_ACCESS_KEY_ID",
        "ALIBABA_CLOUD_ACCESS_KEY_SECRET",
        "ALICLOUD_OSS_ENDPOINT",
        "ALICLOUD_OSS_BUCKET",
        "ALICLOUD_OSS_SECURE",
    ):
        monkeypatch.delenv(key, raising=False)


def _credential_b64() -> str:
    return base64.b64encode(json.dumps(_credential_document()).encode()).decode()


def _credential_document() -> dict[str, str]:
    return {
        "type": "service_account",
        "project_id": "sentineledge-e069b",
        "private_key_id": "test-key-id",
        "private_key": "test-private-key-material",
        "client_email": "reader@example.iam.gserviceaccount.com",
        "token_uri": "https://oauth2.googleapis.com/token",
    }


class FakeClient:
    def __init__(self, payloads: dict[str, object], calls: list[str]) -> None:
        self.payloads = payloads
        self.calls = calls

    def access_secret_version(self, *, request: dict[str, str]) -> SimpleNamespace:
        name = request["name"]
        self.calls.append(name)
        secret_name = name.split("/secrets/", 1)[1].split("/", 1)[0]
        payload = self.payloads[secret_name]
        if isinstance(payload, Exception):
            raise payload
        return SimpleNamespace(payload=SimpleNamespace(data=str(payload).encode()))


def _configure(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GOOGLE_SECRET_MANAGER_PROJECT", "sentineledge-e069b")
    monkeypatch.setenv("GOOGLE_SECRET_MANAGER_SECRETS", "erlang-prod-secrets,erlang-db-secrets")
    monkeypatch.setenv("GOOGLE_SECRET_MANAGER_CREDENTIALS_B64", _credential_b64())


def test_unconfigured_loader_is_a_noop(tmp_path: Path) -> None:
    called = False

    def factory(_: dict[str, object]) -> FakeClient:
        nonlocal called
        called = True
        return FakeClient({}, [])

    assert load_google_secret_manager_secrets(tmp_path / ".env", factory) is False
    assert called is False


def test_development_can_read_credentials_from_external_file(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    credential_path = tmp_path / "reader.json"
    credential_path.write_text(json.dumps(_credential_document()), encoding="utf-8")
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setenv("GOOGLE_SECRET_MANAGER_PROJECT", "sentineledge-e069b")
    monkeypatch.setenv("GOOGLE_SECRET_MANAGER_SECRETS", "erlang-prod-secrets,erlang-db-secrets")
    monkeypatch.setenv("GOOGLE_SECRET_MANAGER_CREDENTIALS_FILE", str(credential_path))
    calls: list[str] = []
    client = FakeClient(
        {"erlang-prod-secrets": "{}", "erlang-db-secrets": "{}"}, calls
    )

    assert load_google_secret_manager_secrets(tmp_path / ".env", lambda _: client) is True
    assert len(calls) == 2


def test_production_rejects_file_only_credentials(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    credential_path = tmp_path / "reader.json"
    credential_path.write_text(json.dumps(_credential_document()), encoding="utf-8")
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("GOOGLE_SECRET_MANAGER_PROJECT", "sentineledge-e069b")
    monkeypatch.setenv("GOOGLE_SECRET_MANAGER_SECRETS", "erlang-prod-secrets,erlang-db-secrets")
    monkeypatch.setenv("GOOGLE_SECRET_MANAGER_CREDENTIALS_FILE", str(credential_path))

    with pytest.raises(RuntimeError, match="production.*Base64"):
        load_google_secret_manager_secrets(tmp_path / ".env", lambda _: FakeClient({}, []))


def test_loads_two_secrets_in_order_and_later_values_win(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    _configure(monkeypatch)
    calls: list[str] = []
    client = FakeClient(
        {
            "erlang-prod-secrets": json.dumps(
                {
                    "SESSION_SECRET_KEY": "prod-session",
                    "QWEN_API_KEY": "old-qwen",
                    "FIREBASE_PROJECT_ID": "sentineledge-e069b",
                    "ALIBABA_CLOUD_ACCESS_KEY_ID": "oss-key-id",
                    "ALIBABA_CLOUD_ACCESS_KEY_SECRET": "oss-key-secret",
                    "ALICLOUD_OSS_ENDPOINT": "oss-ap-southeast-3.aliyuncs.com",
                    "ALICLOUD_OSS_BUCKET": "erlang-vision",
                    "ALICLOUD_OSS_SECURE": "true",
                }
            ),
            "erlang-db-secrets": json.dumps(
                {
                    "QWEN_API_KEY": "new-qwen",
                    "RDS_HOST": "db.internal",
                    "RDS_USER": "app user",
                    "RDS_PASSWORD": "p@ss/word",
                    "RDS_DB": "erlang",
                }
            ),
        },
        calls,
    )

    assert load_google_secret_manager_secrets(tmp_path / ".env", lambda _: client) is True

    assert calls == [
        "projects/sentineledge-e069b/secrets/erlang-prod-secrets/versions/latest",
        "projects/sentineledge-e069b/secrets/erlang-db-secrets/versions/latest",
    ]
    assert os.environ["SESSION_SECRET_KEY"] == "prod-session"
    assert os.environ["QWEN_API_KEY"] == "new-qwen"
    assert os.environ["FIREBASE_PROJECT_ID"] == "sentineledge-e069b"
    assert os.environ["ALIBABA_CLOUD_ACCESS_KEY_ID"] == "oss-key-id"
    assert os.environ["ALIBABA_CLOUD_ACCESS_KEY_SECRET"] == "oss-key-secret"
    assert os.environ["ALICLOUD_OSS_ENDPOINT"] == "oss-ap-southeast-3.aliyuncs.com"
    assert os.environ["ALICLOUD_OSS_BUCKET"] == "erlang-vision"
    assert os.environ["ALICLOUD_OSS_SECURE"] == "true"
    assert os.environ["DATABASE_URL"] == (
        "postgresql+asyncpg://app+user:p%40ss%2Fword@db.internal:5432/erlang"
    )
    assert "GOOGLE_SECRET_MANAGER_CREDENTIALS_B64" not in os.environ


def test_explicit_database_url_is_preserved(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    _configure(monkeypatch)
    monkeypatch.setenv("DATABASE_URL", "sqlite+aiosqlite:///safe-test.db")
    client = FakeClient(
        {
            "erlang-prod-secrets": "{}",
            "erlang-db-secrets": json.dumps(
                {"DATABASE_URL": "postgresql+asyncpg://production"}
            ),
        },
        [],
    )

    load_google_secret_manager_secrets(tmp_path / ".env", lambda _: client)

    assert os.environ["DATABASE_URL"] == "sqlite+aiosqlite:///safe-test.db"


@pytest.mark.parametrize(
    "credentials",
    ["not-base64", base64.b64encode(b"not-json").decode()],
)
def test_rejects_malformed_credentials(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, credentials: str
) -> None:
    _configure(monkeypatch)
    monkeypatch.setenv("GOOGLE_SECRET_MANAGER_CREDENTIALS_B64", credentials)

    with pytest.raises(RuntimeError, match="credentials"):
        load_google_secret_manager_secrets(tmp_path / ".env", lambda _: FakeClient({}, []))

    assert "GOOGLE_SECRET_MANAGER_CREDENTIALS_B64" not in os.environ


def test_rejects_partial_configuration(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("GOOGLE_SECRET_MANAGER_PROJECT", "sentineledge-e069b")

    with pytest.raises(RuntimeError, match="incomplete"):
        load_google_secret_manager_secrets(tmp_path / ".env", lambda _: FakeClient({}, []))


def test_rejects_non_object_secret_payload(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    _configure(monkeypatch)
    client = FakeClient(
        {"erlang-prod-secrets": "[]", "erlang-db-secrets": "{}"}, []
    )

    with pytest.raises(RuntimeError, match="erlang-prod-secrets"):
        load_google_secret_manager_secrets(tmp_path / ".env", lambda _: client)


def test_access_error_is_sanitized_and_credential_is_removed(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    _configure(monkeypatch)
    leaked_value = "do-not-leak-this-private-value"
    client = FakeClient(
        {
            "erlang-prod-secrets": RuntimeError(leaked_value),
            "erlang-db-secrets": "{}",
        },
        [],
    )

    with pytest.raises(RuntimeError) as caught:
        load_google_secret_manager_secrets(tmp_path / ".env", lambda _: client)

    assert "erlang-prod-secrets" in str(caught.value)
    assert leaked_value not in str(caught.value)
    assert "GOOGLE_SECRET_MANAGER_CREDENTIALS_B64" not in os.environ
