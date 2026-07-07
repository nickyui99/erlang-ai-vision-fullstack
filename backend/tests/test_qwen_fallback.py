"""QwenClient model-fallback chain.

Covers the free-tier / local-model fallback: quota errors advance to the next
provider, non-quota 4xx fail fast, image payloads select the vision chain, and
"model@base_url" entries route to a separate (local) endpoint. No network — the
HTTP transport is stubbed with httpx.MockTransport, so these run offline.
"""

import asyncio
import json
import os

os.environ["APP_ENV"] = "test"  # noqa: E402 — must precede settings import

import httpx  # noqa: E402
import pytest  # noqa: E402

from app.services import qwen_client  # noqa: E402
from app.services.qwen_client import (  # noqa: E402
    ModelProvider,
    QwenClient,
    QwenError,
    _is_quota_error,
    _parse_provider,
    _payload_has_image,
)


def _install_transport(monkeypatch, handler) -> None:
    """Route the client's HTTP calls through an in-memory MockTransport."""

    def factory(timeout: float) -> httpx.AsyncClient:
        return httpx.AsyncClient(timeout=timeout, transport=httpx.MockTransport(handler))

    monkeypatch.setattr(qwen_client, "_async_client", factory)


def _ok(model: str) -> httpx.Response:
    return httpx.Response(200, json={"choices": [{"message": {"content": f"ok:{model}"}}]})


# --- unit: quota detection --------------------------------------------------

def test_is_quota_error() -> None:
    assert _is_quota_error(429, "")  # rate limit, regardless of body
    assert _is_quota_error(400, "Free allocated quota exceeded")
    assert _is_quota_error(403, "Arrearage: insufficient balance")
    assert _is_quota_error(402, "quota used up")
    assert not _is_quota_error(400, "invalid request: unknown parameter")
    assert not _is_quota_error(401, "unauthorized")
    assert not _is_quota_error(404, "not found")


# --- unit: modality detection -----------------------------------------------

def test_payload_has_image() -> None:
    text = {"messages": [{"role": "user", "content": "hello"}]}
    vision = {
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "what is this"},
                    {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,AA"}},
                ],
            }
        ]
    }
    assert not _payload_has_image(text)
    assert _payload_has_image(vision)


# --- unit: provider parsing -------------------------------------------------

def test_parse_provider_local_endpoint() -> None:
    provider = _parse_provider("qwen3.5:0.8b@http://localhost:11434/v1/", "https://dash", "KEY")
    assert provider == ModelProvider(
        "qwen3.5:0.8b", "http://localhost:11434/v1", qwen_client.settings.qwen_local_api_key
    )


def test_parse_provider_default_endpoint() -> None:
    provider = _parse_provider("qwen3.7-plus", "https://dash.example/v1/", "KEY")
    assert provider == ModelProvider("qwen3.7-plus", "https://dash.example/v1", "KEY")


def test_parse_provider_blank_is_none() -> None:
    assert _parse_provider("   ", "https://dash", "KEY") is None


# --- integration: the fallback loop ----------------------------------------

def test_text_fallback_advances_on_quota(monkeypatch) -> None:
    monkeypatch.setattr(qwen_client.settings, "qwen_text_fallback_models", "free-2,free-3")
    calls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        model = json.loads(request.content)["model"]
        calls.append(model)
        if model == "primary-text":
            return httpx.Response(429, json={"error": {"message": "Requests rate limit exceeded"}})
        return _ok(model)

    _install_transport(monkeypatch, handler)
    client = QwenClient(api_key="KEY", base_url="https://dash.example/v1", model="primary-text")
    response = asyncio.run(client.chat([{"role": "user", "content": "hi"}]))

    assert response.content == "ok:free-2"
    assert calls == ["primary-text", "free-2"]  # stops at the first success


def test_vision_fallback_routes_to_local_endpoint(monkeypatch) -> None:
    monkeypatch.setattr(
        qwen_client.settings,
        "qwen_vision_fallback_models",
        "qwen3.5:0.8b@http://localhost:11434/v1",
    )
    seen: list[tuple[str, str]] = []

    def handler(request: httpx.Request) -> httpx.Response:
        model = json.loads(request.content)["model"]
        seen.append((str(request.url), model))
        if model == "qwen3-vl-plus":
            return httpx.Response(429, json={"error": {"message": "free quota exceeded"}})
        return _ok(model)

    _install_transport(monkeypatch, handler)
    client = QwenClient(api_key="KEY", base_url="https://dash.example/v1", model="qwen3-vl-plus")
    image_msg = [
        {
            "role": "user",
            "content": [
                {"type": "text", "text": "verify"},
                {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,AA"}},
            ],
        }
    ]
    response = asyncio.run(client.chat(image_msg))

    assert response.content == "ok:qwen3.5:0.8b"
    # Primary hit DashScope; fallback hit the local Ollama endpoint.
    assert seen[0] == ("https://dash.example/v1/chat/completions", "qwen3-vl-plus")
    assert seen[1] == ("http://localhost:11434/v1/chat/completions", "qwen3.5:0.8b")


def test_text_chain_ignored_for_vision_and_vice_versa(monkeypatch) -> None:
    # A text request must NOT try the vision (local) fallback, and vice versa.
    monkeypatch.setattr(qwen_client.settings, "qwen_text_fallback_models", "text-fb")
    monkeypatch.setattr(qwen_client.settings, "qwen_vision_fallback_models", "vision-fb")
    calls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        model = json.loads(request.content)["model"]
        calls.append(model)
        return httpx.Response(429, json={"error": {"message": "quota"}})  # everyone is out

    _install_transport(monkeypatch, handler)
    client = QwenClient(api_key="KEY", base_url="https://dash.example/v1", model="primary")
    with pytest.raises(QwenError):
        asyncio.run(client.chat([{"role": "user", "content": "text only"}]))
    assert calls == ["primary", "text-fb"]  # never touched vision-fb


def test_non_quota_4xx_fails_fast(monkeypatch) -> None:
    monkeypatch.setattr(qwen_client.settings, "qwen_text_fallback_models", "free-2")
    calls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(json.loads(request.content)["model"])
        return httpx.Response(400, json={"error": {"message": "invalid request: bad role"}})

    _install_transport(monkeypatch, handler)
    client = QwenClient(api_key="KEY", base_url="https://dash.example/v1", model="primary-text")
    with pytest.raises(QwenError):
        asyncio.run(client.chat([{"role": "user", "content": "hi"}]))
    assert calls == ["primary-text"]  # did NOT waste the fallback on a real bad request


def test_server_error_advances(monkeypatch) -> None:
    monkeypatch.setattr(qwen_client.settings, "qwen_text_fallback_models", "free-2")
    calls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        model = json.loads(request.content)["model"]
        calls.append(model)
        return _ok(model) if model == "free-2" else httpx.Response(500, text="upstream error")

    _install_transport(monkeypatch, handler)
    client = QwenClient(api_key="KEY", base_url="https://dash.example/v1", model="primary-text")
    response = asyncio.run(client.chat([{"role": "user", "content": "hi"}]))
    assert response.content == "ok:free-2"
    assert calls == ["primary-text", "free-2"]


def test_connection_error_advances_to_local(monkeypatch) -> None:
    monkeypatch.setattr(
        qwen_client.settings, "qwen_text_fallback_models", "backup@http://localhost:9/v1"
    )
    calls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        model = json.loads(request.content)["model"]
        calls.append(model)
        if model == "primary-text":
            raise httpx.ConnectError("connection refused")
        return _ok(model)

    _install_transport(monkeypatch, handler)
    client = QwenClient(api_key="KEY", base_url="https://dash.example/v1", model="primary-text")
    response = asyncio.run(client.chat([{"role": "user", "content": "hi"}]))
    assert response.content == "ok:backup"
    assert calls == ["primary-text", "backup"]
