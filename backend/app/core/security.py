from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import time
from typing import Any

from app.core.config import settings


SESSION_PURPOSE = "session"
EDGE_TOKEN_PREFIX = "pbkdf2_sha256"
EDGE_TOKEN_ITERATIONS = 210_000
DEVICE_LINK_DERIVATION_LABEL = b"sentineledge-device-link-v1"


def _b64encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def _b64decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)


def _sign(value: str, purpose: str) -> str:
    key = settings.session_secret_key.encode("utf-8")
    message = f"{purpose}.{value}".encode("utf-8")
    return _b64encode(hmac.new(key, message, hashlib.sha256).digest())


def create_signed_token(payload: dict[str, Any], purpose: str, expires_in_seconds: int) -> str:
    body = dict(payload)
    body["exp"] = int(time.time()) + expires_in_seconds
    encoded_body = _b64encode(json.dumps(body, separators=(",", ":"), sort_keys=True).encode("utf-8"))
    signature = _sign(encoded_body, purpose)
    return f"{encoded_body}.{signature}"


def verify_signed_token(token: str, purpose: str) -> dict[str, Any] | None:
    try:
        encoded_body, signature = token.split(".", 1)
    except ValueError:
        return None

    expected_signature = _sign(encoded_body, purpose)
    if not hmac.compare_digest(signature, expected_signature):
        return None

    try:
        payload = json.loads(_b64decode(encoded_body))
    except (ValueError, json.JSONDecodeError):
        return None

    expires_at = payload.get("exp")
    if not isinstance(expires_at, int) or expires_at < int(time.time()):
        return None

    return payload


def create_session_token(user_id: str) -> str:
    return create_signed_token(
        {"user_id": user_id},
        SESSION_PURPOSE,
        settings.session_expire_minutes * 60,
    )


def verify_session_token(token: str) -> str | None:
    payload = verify_signed_token(token, SESSION_PURPOSE)
    if payload is None:
        return None

    user_id = payload.get("user_id")
    return user_id if isinstance(user_id, str) and user_id else None


def generate_edge_token() -> str:
    return f"se_edge_{secrets.token_urlsafe(32)}"


def derive_device_link_secret(raw_edge_token: str) -> str:
    if not raw_edge_token:
        raise ValueError("edge token is required")
    digest = hmac.new(raw_edge_token.encode("utf-8"), DEVICE_LINK_DERIVATION_LABEL, hashlib.sha256).digest()
    return _b64encode(digest)


def hash_edge_token(raw_token: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        raw_token.encode("utf-8"),
        salt,
        EDGE_TOKEN_ITERATIONS,
    )
    return f"{EDGE_TOKEN_PREFIX}${EDGE_TOKEN_ITERATIONS}${_b64encode(salt)}${_b64encode(digest)}"


def verify_edge_token(raw_token: str, token_hash: str) -> bool:
    try:
        prefix, iterations_raw, salt_raw, digest_raw = token_hash.split("$", 3)
        iterations = int(iterations_raw)
    except ValueError:
        return False

    if prefix != EDGE_TOKEN_PREFIX:
        return False

    salt = _b64decode(salt_raw)
    expected_digest = _b64decode(digest_raw)
    actual_digest = hashlib.pbkdf2_hmac(
        "sha256",
        raw_token.encode("utf-8"),
        salt,
        iterations,
    )
    return hmac.compare_digest(actual_digest, expected_digest)



