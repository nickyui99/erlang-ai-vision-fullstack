from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any
from urllib.parse import quote_plus


def _escape_control_chars_in_json_strings(value: str) -> str:
    escaped: list[str] = []
    in_string = False
    escape_next = False

    for char in value:
        if escape_next:
            escaped.append(char)
            escape_next = False
            continue

        if char == "\\" and in_string:
            escaped.append(char)
            escape_next = True
            continue

        if char == '"':
            escaped.append(char)
            in_string = not in_string
            continue

        if in_string:
            if char == "\n":
                escaped.append("\\n")
                continue
            if char == "\r":
                escaped.append("\\r")
                continue
            if char == "\t":
                escaped.append("\\t")
                continue

        escaped.append(char)

    return "".join(escaped)

def _read_dotenv_key(env_file: Path, key: str) -> str | None:
    if key in os.environ:
        return os.environ[key]
    if not env_file.exists():
        return None

    prefix = f"{key}="
    for raw_line in env_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or not line.startswith(prefix):
            continue
        value = line[len(prefix) :].strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        return value
    return None


def _parse_secret_data(secret_data: str) -> dict[str, Any]:
    stripped = secret_data.strip()
    if not stripped:
        return {}

    if stripped.startswith("{"):
        try:
            parsed = json.loads(stripped)
        except json.JSONDecodeError:
            parsed = json.loads(_escape_control_chars_in_json_strings(stripped))
        if not isinstance(parsed, dict):
            raise ValueError("Secret payload JSON must be an object")
        return parsed

    values: dict[str, Any] = {}
    for raw_line in stripped.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def _write_firebase_credentials(firebase_credentials: Any) -> str:
    if isinstance(firebase_credentials, str):
        try:
            firebase_credentials = json.loads(firebase_credentials)
        except json.JSONDecodeError:
            firebase_credentials = json.loads(_escape_control_chars_in_json_strings(firebase_credentials))
    if not isinstance(firebase_credentials, dict):
        raise ValueError("GOOGLE_APPLICATION_CREDENTIALS_JSON must be a JSON object")

    path = Path(tempfile.gettempdir()) / "erlang-firebase-service-account.json"
    path.write_text(json.dumps(firebase_credentials), encoding="utf-8")
    return str(path)


def _secret_names(*raw_names: str | None) -> list[str]:
    names: list[str] = []
    for raw_name in raw_names:
        if not raw_name or raw_name == "change-me":
            continue
        names.extend(name.strip() for name in raw_name.split(",") if name.strip())
    return names

def _database_url_from_rds_parts(secret_values: dict[str, Any]) -> str | None:
    host = secret_values.get("RDS_HOST")
    if not host:
        return None
    user = quote_plus(str(secret_values.get("RDS_USER", "")))
    password = quote_plus(str(secret_values.get("RDS_PASSWORD", "")))
    port = str(secret_values.get("RDS_PORT", "5432"))
    database = secret_values.get("RDS_DB", "erlang")
    auth = f"{user}:{password}@" if user else ""
    return f"postgresql+asyncpg://{auth}{host}:{port}/{database}"


def _apply_secret_values(secret_values: dict[str, Any]) -> None:
    for key in ("SESSION_SECRET_KEY", "QWEN_API_KEY"):
        value = secret_values.get(key)
        if value:
            os.environ[key] = str(value)

    # An explicitly set DATABASE_URL always wins over the KMS value: tests and
    # local tooling pin their own database, and silently redirecting them to
    # the production RDS would let e.g. a test drop_all wipe live data.
    database_url = secret_values.get("DATABASE_URL") or _database_url_from_rds_parts(secret_values)
    if database_url and "DATABASE_URL" not in os.environ:
        os.environ["DATABASE_URL"] = str(database_url)

    firebase_credentials = secret_values.get("GOOGLE_APPLICATION_CREDENTIALS_JSON")
    if firebase_credentials:
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = _write_firebase_credentials(firebase_credentials)
        return

    firebase_credentials = secret_values.get("GOOGLE_APPLICATION_CREDENTIALS")
    if not firebase_credentials:
        return

    if isinstance(firebase_credentials, dict):
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = _write_firebase_credentials(firebase_credentials)
        return

    firebase_credentials_raw = str(firebase_credentials).strip()
    if firebase_credentials_raw.startswith("{"):
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = _write_firebase_credentials(firebase_credentials_raw)
    else:
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = firebase_credentials_raw
