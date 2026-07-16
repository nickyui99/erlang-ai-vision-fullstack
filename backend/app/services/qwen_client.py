"""Milestone 9 — Qwen Cloud client for event verification.

Two implementations behind one interface:

* :class:`QwenClient` calls DashScope's OpenAI-compatible chat endpoint.
* :class:`MockQwenClient` returns a deterministic verdict with no network — used
  in tests and as the offline fallback when no ``QWEN_API_KEY`` is configured.

Both return the raw assistant text (expected to contain a JSON verdict); parsing
and repair live in :mod:`app.services.verification_service`.
"""

from __future__ import annotations

import json
import logging
import re
from abc import ABC, abstractmethod
from dataclasses import dataclass, field

import httpx

from app.agents.prompts import build_verification_messages
from app.core.config import settings
from app.schemas.verification import VerificationRequest


log = logging.getLogger("app.services.qwen_client")


class QwenError(Exception):
    """Qwen verification failed (network, HTTP, or transport error)."""


class QwenTimeoutError(QwenError):
    """Qwen did not respond within the configured timeout."""


@dataclass(frozen=True)
class ModelProvider:
    """One model endpoint to try: a model name plus where to call it."""

    model: str
    base_url: str
    api_key: str


def _parse_provider(entry: str, default_base: str, default_key: str) -> ModelProvider | None:
    """Parse a chain entry: ``"model"`` (default endpoint) or ``"model@base_url"``.

    ``model@base_url`` points at a separate OpenAI-compatible server (e.g. a local
    Ollama VLM) and uses the local api key. Returns None for blank entries.
    """

    entry = entry.strip()
    if not entry:
        return None
    if "@" in entry:
        model, _, base_url = entry.partition("@")
        model, base_url = model.strip(), base_url.strip().rstrip("/")
        if not model or not base_url:
            return None
        return ModelProvider(model=model, base_url=base_url, api_key=settings.qwen_local_api_key)
    return ModelProvider(model=entry, base_url=default_base.rstrip("/"), api_key=default_key)


def _split_models(raw: str) -> list[str]:
    return [item.strip() for item in (raw or "").split(",") if item.strip()]


def _payload_has_image(payload: dict) -> bool:
    """True if any message carries image content (an OpenAI-style image_url part)."""

    for message in payload.get("messages") or []:
        content = message.get("content")
        if isinstance(content, list):
            for part in content:
                if isinstance(part, dict) and part.get("type") == "image_url":
                    return True
    return False


# Substrings that mark a quota / rate-limit / arrears failure (case-insensitive).
_QUOTA_PATTERN = re.compile(
    r"quota|arrear|insufficient|balance|throttl|allocat|rate\s*limit|exceeded",
    re.IGNORECASE,
)


def _is_quota_error(status_code: int, body: str) -> bool:
    """Whether an HTTP error means "out of quota / rate-limited" (so try the next model)."""

    if status_code == 429:
        return True
    if status_code in (400, 402, 403):
        return bool(_QUOTA_PATTERN.search(body or ""))
    return False


def _async_client(timeout: float) -> httpx.AsyncClient:
    """Construct the HTTP client. Indirected so tests can stub the transport."""

    return httpx.AsyncClient(timeout=timeout)


@dataclass
class QwenToolCall:
    """A single tool/function call the model asked us to run."""

    id: str
    name: str
    arguments: dict


@dataclass
class QwenResponse:
    """One assistant turn: free-text content and/or a batch of tool calls."""

    content: str | None = None
    tool_calls: list[QwenToolCall] = field(default_factory=list)


class BaseQwenClient(ABC):
    @abstractmethod
    async def verify(self, request: VerificationRequest, *, repair: bool = False) -> str:
        """Return the raw assistant message text for a single-shot verification."""

    @abstractmethod
    async def chat(
        self,
        messages: list[dict],
        *,
        tools: list[dict] | None = None,
        thinking: bool | None = None,
    ) -> QwenResponse:
        """Run one chat turn with optional tool specs; return content + tool calls.

        ``thinking=False`` disables the model's hidden reasoning (DashScope
        ``enable_thinking``) — use it for structured/low-latency calls (NL-rule
        compiler, camera control) where reasoning multiplies latency and tokens
        without improving the JSON. ``None`` keeps the provider default.
        """


class QwenClient(BaseQwenClient):
    """Calls the real Qwen model via DashScope's OpenAI-compatible API."""

    def __init__(
        self,
        *,
        api_key: str | None = None,
        base_url: str | None = None,
        model: str | None = None,
        timeout_seconds: float | None = None,
    ) -> None:
        default_key = api_key if api_key is not None else settings.qwen_api_key
        default_base = (base_url or settings.qwen_base_url).rstrip("/")
        entry = model or settings.qwen_model
        # The primary may itself carry an "@base_url" (e.g. to make a local VLM primary).
        self._primary = _parse_provider(entry, default_base, default_key) or ModelProvider(
            model=entry, base_url=default_base, api_key=default_key
        )
        self._default_base = default_base
        self._default_key = default_key
        self._timeout = timeout_seconds if timeout_seconds is not None else settings.qwen_timeout_seconds
        # Keep connections alive across model turns: an agentic chat may make
        # several calls, and recreating the client repeats TCP/TLS setup.
        self._http_client = _async_client(self._timeout)

    async def aclose(self) -> None:
        await self._http_client.aclose()

    def _candidate_providers(self, *, is_vision: bool) -> list[ModelProvider]:
        """Primary first, then the modality-matched fallback chain, de-duped by model."""

        raw = settings.qwen_vision_fallback_models if is_vision else settings.qwen_text_fallback_models
        providers = [self._primary]
        seen = {self._primary.model}
        for item in _split_models(raw):
            provider = _parse_provider(item, self._default_base, self._default_key)
            if provider and provider.model not in seen:
                providers.append(provider)
                seen.add(provider.model)
        return providers

    async def _try_provider(self, provider: ModelProvider, payload: dict) -> dict:
        """POST one request to a single provider. Raises QwenError/QwenTimeoutError."""

        headers = {"Authorization": f"Bearer {provider.api_key}"}
        body = {**payload, "model": provider.model}
        try:
            response = await self._http_client.post(
                f"{provider.base_url}/chat/completions",
                headers=headers,
                json=body,
            )
        except httpx.TimeoutException as exc:
            raise QwenTimeoutError("Qwen request timed out") from exc
        except httpx.HTTPError as exc:
            raise QwenError(f"Qwen request failed: {exc}") from exc

        if response.status_code >= 400:
            raise QwenError(f"Qwen returned HTTP {response.status_code}: {response.text[:500]}")
        try:
            return response.json()
        except ValueError as exc:
            raise QwenError("Qwen response was not valid JSON") from exc

    async def _post_chat(self, payload: dict) -> dict:
        """Try each candidate model in turn, advancing on quota/transport failures.

        Advances to the next provider on a quota/rate-limit error, HTTP >=500, a
        timeout, a connection error, or — for image-carrying payloads — any HTTP
        400 (a text-only model rejecting the image; the vision fallbacks may still
        take it). Fails fast on other 4xx (a bad request or auth error every
        provider would hit identically). Raises the last error once the chain is
        exhausted so callers keep their existing degrade-on-QwenError paths.
        """

        has_image = _payload_has_image(payload)
        providers = self._candidate_providers(is_vision=has_image)
        last_error: QwenError | None = None
        for index, provider in enumerate(providers):
            try:
                return await self._try_provider(provider, payload)
            except QwenTimeoutError as exc:
                last_error = exc
            except QwenError as exc:
                if not self._should_advance(exc, payload_has_image=has_image):
                    raise
                last_error = exc
            log.warning(
                "Qwen model %r failed (%s); trying fallback %d/%d",
                provider.model, last_error, index + 1, len(providers),
            )
        raise last_error or QwenError("no Qwen model providers configured")

    @staticmethod
    def _should_advance(error: QwenError, *, payload_has_image: bool = False) -> bool:
        """Whether to try the next provider given a failed attempt's error."""

        message = str(error)
        # Transport/connection failures ("Qwen request failed: ...") — try the next one.
        if message.startswith("Qwen request failed"):
            return True
        match = re.search(r"HTTP (\d{3})", message)
        if not match:
            return False  # e.g. malformed-JSON body: don't burn the whole chain.
        status = int(match.group(1))
        if status >= 500:
            return True
        if payload_has_image and status == 400:
            # A 400 on an image-carrying payload usually means this model is
            # text-only (DashScope: "Unexpected item type in content.") — e.g.
            # the chat primary seeing a tool snapshot. The vision-matched
            # fallbacks may still take it, so keep walking the chain.
            return True
        return _is_quota_error(status, message)

    async def verify(self, request: VerificationRequest, *, repair: bool = False) -> str:
        messages = build_verification_messages(request, repair=repair)
        # The concrete model is chosen per attempt by _post_chat's provider chain.
        data = await self._post_chat({"messages": messages, "temperature": 0})
        try:
            return data["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as exc:
            raise QwenError("Qwen response was not in the expected shape") from exc

    async def chat(
        self,
        messages: list[dict],
        *,
        tools: list[dict] | None = None,
        thinking: bool | None = None,
    ) -> QwenResponse:
        payload: dict = {"messages": messages, "temperature": 0}
        if tools:
            payload["tools"] = tools
            payload["tool_choice"] = "auto"
        if thinking is not None:
            # Top-level flag (DashScope compatible-mode); non-DashScope fallback
            # endpoints (Ollama) ignore unknown fields.
            payload["enable_thinking"] = thinking
        data = await self._post_chat(payload)
        try:
            message = data["choices"][0]["message"]
        except (KeyError, IndexError, TypeError) as exc:
            raise QwenError("Qwen response was not in the expected shape") from exc

        tool_calls: list[QwenToolCall] = []
        for raw in message.get("tool_calls") or []:
            function = raw.get("function") or {}
            try:
                arguments = json.loads(function.get("arguments") or "{}")
            except (ValueError, TypeError):
                arguments = {}
            tool_calls.append(
                QwenToolCall(
                    id=raw.get("id") or f"call_{len(tool_calls)}",
                    name=function.get("name", ""),
                    arguments=arguments if isinstance(arguments, dict) else {},
                )
            )
        return QwenResponse(content=message.get("content"), tool_calls=tool_calls)


class MockQwenClient(BaseQwenClient):
    """Deterministic offline client. Never calls tools; confirms high/critical."""

    @staticmethod
    def _verdict_for(severity: str, summary: str | None, event_type: str) -> str:
        verified = severity in ("high", "critical")
        return json.dumps(
            {
                "verified": verified,
                "confidence": 0.9 if verified else 0.4,
                "severity": severity,
                "summary": (
                    f"[mock] {'Confirmed' if verified else 'Could not confirm'}: "
                    f"{summary or event_type}"
                ),
                "recommended_action": "notify" if verified else "ignore",
            }
        )

    async def verify(self, request: VerificationRequest, *, repair: bool = False) -> str:
        return self._verdict_for(request.severity, request.summary, request.event_type)

    async def chat(
        self,
        messages: list[dict],
        *,
        tools: list[dict] | None = None,
        thinking: bool | None = None,
    ) -> QwenResponse:
        # The mock inspects the seeded prompt to stay consistent with its caller,
        # but never requests tools (and has no thinking to disable).
        text = "\n".join(
            m.get("content", "") for m in messages if isinstance(m.get("content"), str)
        )
        # Conversational chat (the Erlang AI Agent) rather than event verification:
        # return a friendly reply so keyless/offline dev and tests behave sensibly.
        if "Erlang AI Agent" in text:
            return QwenResponse(content=self._chat_reply(messages), tool_calls=[])
        severity = "high" if ("Edge severity: high" in text or "Edge severity: critical" in text) else "low"
        return QwenResponse(content=self._verdict_for(severity, None, "event"), tool_calls=[])

    @staticmethod
    def _chat_reply(messages: list[dict]) -> str:
        """A deterministic, conversational stand-in for a real assistant turn."""

        last_user = ""
        for message in reversed(messages):
            if message.get("role") == "user" and isinstance(message.get("content"), str):
                last_user = message["content"].strip()
                break
        if last_user:
            return (
                "[mock] Hi, I'm Erlang AI Agent. I can't reach a live model in this "
                "offline mode, but here is a placeholder reply to: "
                f'"{last_user}"'
            )
        return (
            "[mock] Hi, I'm Erlang AI Agent. I'm running in offline mode, so this is "
            "a placeholder reply. Ask me anything and I'll echo it back here."
        )


_cached_qwen_clients: dict[str, QwenClient] = {}


async def close_qwen_clients() -> None:
    """Close pooled HTTP connections during application shutdown."""
    clients = list(_cached_qwen_clients.values())
    _cached_qwen_clients.clear()
    for client in clients:
        await client.aclose()


def get_qwen_client(model: str | None = None) -> BaseQwenClient:
    """Pick the client for the current environment.

    Tests and key-less environments get the mock so verification is always
    exercisable offline; a configured non-test environment gets the real client.
    ``model`` overrides the primary model (e.g. a text model for chat); fallbacks
    are still applied by the client based on the request modality.
    """

    if settings.app_env == "test" or not settings.qwen_api_key:
        return MockQwenClient()
    key = model or settings.qwen_model
    client = _cached_qwen_clients.get(key)
    if client is None:
        client = QwenClient(model=model)
        _cached_qwen_clients[key] = client
    return client
