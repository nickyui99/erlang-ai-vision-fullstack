from __future__ import annotations

import base64
import binascii
import json
import os
from pathlib import Path
from typing import Any, Callable, Protocol

from app.core.alicloud_secrets import (
    _apply_secret_values,
    _parse_secret_data,
    _read_dotenv_key,
    _secret_names,
)


class _SecretManagerClient(Protocol):
    def access_secret_version(self, *, request: dict[str, str]) -> Any: ...


ClientFactory = Callable[[dict[str, Any]], _SecretManagerClient]


def _default_client_factory(service_account_info: dict[str, Any]) -> _SecretManagerClient:
    try:
        from google.cloud import secretmanager
        from google.oauth2 import service_account
    except ImportError as exc:
        raise RuntimeError(
            "Google Secret Manager loading is enabled, but google-cloud-secret-manager "
            "is not installed. Install backend requirements before starting the app."
        ) from exc

    credentials = service_account.Credentials.from_service_account_info(service_account_info)
    return secretmanager.SecretManagerServiceClient(credentials=credentials)


def _parse_credentials(raw: bytes) -> dict[str, Any]:
    try:
        parsed = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("Google Secret Manager credentials are not valid JSON") from exc
    if not isinstance(parsed, dict):
        raise RuntimeError("Google Secret Manager credentials JSON must be an object")
    return parsed


def _decode_credentials(encoded: str) -> dict[str, Any]:
    try:
        raw = base64.b64decode(encoded, validate=True)
    except binascii.Error as exc:
        raise RuntimeError("Google Secret Manager credentials are not valid Base64") from exc
    return _parse_credentials(raw)


def _read_credentials_file(path_value: str, env_file: Path) -> dict[str, Any]:
    path = Path(path_value).expanduser()
    if not path.is_absolute():
        path = env_file.parent / path
    try:
        return _parse_credentials(path.read_bytes())
    except OSError as exc:
        raise RuntimeError(
            f"Google Secret Manager credentials file cannot be read: {path}"
        ) from exc


def load_google_secret_manager_secrets(
    env_file: Path,
    client_factory: ClientFactory | None = None,
) -> bool:
    """Load configured Google secrets into the process environment at startup."""

    project = _read_dotenv_key(env_file, "GOOGLE_SECRET_MANAGER_PROJECT")
    raw_names = _read_dotenv_key(env_file, "GOOGLE_SECRET_MANAGER_SECRETS")
    encoded_credentials = _read_dotenv_key(env_file, "GOOGLE_SECRET_MANAGER_CREDENTIALS_B64")
    credentials_file = _read_dotenv_key(
        env_file, "GOOGLE_SECRET_MANAGER_CREDENTIALS_FILE"
    )
    app_env = (_read_dotenv_key(env_file, "APP_ENV") or "development").lower()
    configured = (project, raw_names, encoded_credentials, credentials_file)
    if not any(configured):
        return False
    if not project or not raw_names:
        raise RuntimeError(
            "Google Secret Manager configuration is incomplete; project, secret names, "
            "and credentials are all required"
        )
    if app_env == "production" and not encoded_credentials:
        raise RuntimeError(
            "Google Secret Manager production configuration requires Base64 credentials "
            "injected by the deployment script"
        )
    if not encoded_credentials and not credentials_file:
        raise RuntimeError(
            "Google Secret Manager configuration is incomplete; a credentials file is "
            "required for development"
        )

    secret_names = _secret_names(raw_names)
    if not secret_names:
        raise RuntimeError("Google Secret Manager configuration has no secret names")

    dotenv_database_url = _read_dotenv_key(env_file, "DATABASE_URL")
    if dotenv_database_url and "DATABASE_URL" not in os.environ:
        os.environ["DATABASE_URL"] = dotenv_database_url

    try:
        service_account_info = (
            _decode_credentials(encoded_credentials)
            if encoded_credentials
            else _read_credentials_file(credentials_file or "", env_file)
        )
        client = (client_factory or _default_client_factory)(service_account_info)
        merged: dict[str, Any] = {}
        for secret_name in secret_names:
            resource_name = f"projects/{project}/secrets/{secret_name}/versions/latest"
            try:
                response = client.access_secret_version(request={"name": resource_name})
                payload = response.payload.data.decode("utf-8")
                if not payload.lstrip().startswith("{"):
                    raise ValueError("Secret payload must be a JSON object")
                parsed = _parse_secret_data(payload)
            except Exception as exc:
                raise RuntimeError(
                    f"Unable to load Google Secret Manager secret {secret_name!r}"
                ) from exc
            merged.update(parsed)
        _apply_secret_values(merged)
        return True
    finally:
        os.environ.pop("GOOGLE_SECRET_MANAGER_CREDENTIALS_B64", None)
