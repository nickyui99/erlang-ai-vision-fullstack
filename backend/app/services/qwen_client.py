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
from abc import ABC, abstractmethod
from dataclasses import dataclass, field

import httpx

from app.agents.prompts import build_verification_messages
from app.core.config import settings
from app.schemas.verification import VerificationRequest


class QwenError(Exception):
    """Qwen verification failed (network, HTTP, or transport error)."""


class QwenTimeoutError(QwenError):
    """Qwen did not respond within the configured timeout."""


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
    async def chat(self, messages: list[dict], *, tools: list[dict] | None = None) -> QwenResponse:
        """Run one chat turn with optional tool specs; return content + tool calls."""


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
        self._api_key = api_key if api_key is not None else settings.qwen_api_key
        self._base_url = (base_url or settings.qwen_base_url).rstrip("/")
        self._model = model or settings.qwen_model
        self._timeout = timeout_seconds if timeout_seconds is not None else settings.qwen_timeout_seconds

    async def _post_chat(self, payload: dict) -> dict:
        headers = {"Authorization": f"Bearer {self._api_key}"}
        try:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                response = await client.post(
                    f"{self._base_url}/chat/completions",
                    headers=headers,
                    json=payload,
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

    async def verify(self, request: VerificationRequest, *, repair: bool = False) -> str:
        messages = build_verification_messages(request, repair=repair)
        data = await self._post_chat({"model": self._model, "messages": messages, "temperature": 0})
        try:
            return data["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as exc:
            raise QwenError("Qwen response was not in the expected shape") from exc

    async def chat(self, messages: list[dict], *, tools: list[dict] | None = None) -> QwenResponse:
        payload: dict = {"model": self._model, "messages": messages, "temperature": 0}
        if tools:
            payload["tools"] = tools
            payload["tool_choice"] = "auto"
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

    async def chat(self, messages: list[dict], *, tools: list[dict] | None = None) -> QwenResponse:
        # The mock inspects the seeded prompt to stay consistent with its caller,
        # but never requests tools.
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


def get_qwen_client() -> BaseQwenClient:
    """Pick the client for the current environment.

    Tests and key-less environments get the mock so verification is always
    exercisable offline; a configured non-test environment gets the real client.
    """

    if settings.app_env == "test" or not settings.qwen_api_key:
        return MockQwenClient()
    return QwenClient()
