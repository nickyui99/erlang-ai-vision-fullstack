"""Conversational agent builder: shape a detection rule through a short chat.

The user talks to the model ("watch the door at night"); the model replies
conversationally and, once it has enough, proposes a single crisp rule + a short
name. Each turn we also compile the proposed rule (reusing the NL-rule compiler)
so the UI can preview what the camera will actually watch for.

Never raises: in test/key-less environments or on any LLM/parse failure it falls
back to a deterministic helper that proposes the user's own words as the rule.
"""

from __future__ import annotations

import logging

from app.agents.compiler import compile_agent_rule, _extract_json
from app.core.config import settings
from app.services.qwen_client import QwenClient, QwenError


log = logging.getLogger("app.agents.builder")

_SYSTEM_PROMPT = (
    "You help a user create ONE home-security camera detection rule through a short, "
    "friendly conversation. Understand what they want the camera to watch for and turn it "
    "into a single clear instruction.\n"
    "Guidelines:\n"
    "- Keep each reply short (1-2 sentences). Ask a brief clarifying question ONLY when it "
    "materially changes the rule (e.g. a time window or which subject); otherwise just "
    "propose a rule.\n"
    "- Cameras/mics can only detect: people, vehicles (car/truck/motorcycle/bus/bicycle), "
    "pets (dog/cat), bags (backpack/handbag/suitcase), and sounds (glass breaking, scream, "
    "alarm, crying, gunshot). Don't promise anything outside that.\n"
    "- A good rule reads like: \"Alert me when an unfamiliar person lingers at the front door "
    "after 9 PM.\"\n"
    "Reply with ONLY a JSON object (no markdown, no prose outside it):\n"
    '{"reply": "<your short message to the user>", '
    '"rule": "<the current best single-sentence rule, or null if you still need info>", '
    '"name": "<a 2-4 word name for the rule, or null>"}'
)


async def run_agent_builder(messages: list[dict]) -> dict:
    """Run one builder turn. Returns reply + (optional) proposed rule and preview."""

    reply, rule, name = await _converse(messages)
    result: dict = {
        "reply": reply,
        "rule": rule,
        "name": name,
        "compiled_prompt": None,
        "compiled_edge_config": None,
    }
    if rule:
        compiled_prompt, compiled_edge_config = await compile_agent_rule(rule)
        result["compiled_prompt"] = compiled_prompt
        result["compiled_edge_config"] = compiled_edge_config
    return result


async def _converse(messages: list[dict]) -> tuple[str, str | None, str | None]:
    if settings.app_env == "test" or not settings.qwen_api_key:
        return _fallback(messages)
    try:
        client = QwenClient(model=settings.qwen_text_model)
        convo = [{"role": "system", "content": _SYSTEM_PROMPT}] + _sanitize(messages)
        response = await client.chat(convo)
        obj = _extract_json(response.content)
        if not obj:
            raise ValueError("builder model did not return a JSON object")
        reply = str(obj.get("reply") or "").strip() or "Here's a suggestion — refine it or save."
        rule = obj.get("rule")
        rule = str(rule).strip() if isinstance(rule, str) and rule.strip() else None
        name = obj.get("name")
        name = str(name).strip() if isinstance(name, str) and name.strip() else None
        return reply, rule, name
    except (QwenError, ValueError, KeyError, TypeError) as exc:
        log.warning("agent builder LLM failed (%s); using fallback", exc)
        return _fallback(messages)


def _sanitize(messages: list[dict]) -> list[dict]:
    """Keep only well-formed user/assistant turns, capped to recent history."""
    clean: list[dict] = []
    for message in messages:
        role = message.get("role")
        content = str(message.get("content") or "").strip()
        if role in ("user", "assistant") and content:
            clean.append({"role": role, "content": content})
    return clean[-12:]


def _fallback(messages: list[dict]) -> tuple[str, str | None, str | None]:
    last_user = ""
    for message in reversed(messages):
        if message.get("role") == "user" and str(message.get("content") or "").strip():
            last_user = str(message["content"]).strip()
            break
    if not last_user:
        return ("Tell me what this camera should watch for.", None, None)
    rule = last_user if last_user[:1].isupper() else last_user[:1].upper() + last_user[1:]
    if not rule.endswith((".", "!", "?")):
        rule += "."
    return ("Here's a rule based on that — refine it or save it.", rule, None)
