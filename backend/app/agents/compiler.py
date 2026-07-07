"""NL-rule compiler: plain-language surveillance rule -> edge config + verification prompt.

A user writes a rule in plain English ("alert me if someone lingers at the door after
9pm"). This turns it into (1) the ``compiled_edge_config`` the laptop-edge ``EventFilter``
consumes and (2) a ``compiled_prompt`` restatement used by the cloud verification agent and
the edge triage/agent.

Uses Qwen Cloud (a text model, ``qwen-plus`` by default) via the OpenAI-compatible client.
Always resolves — never fails agent creation: in test/key-less environments, or on any LLM
or parse failure, it falls back to a deterministic keyword compiler.

The edge is the source of truth for the config schema. Keys must match
``pipeline/event_filter.py`` in the SentinelEdge_LaptopEdge repo:
``{classes, min_confidence, dwell_s, cooldown_s, roi?, schedule?}``. NOTE the key is
``classes`` (not ``detectors`` — the old stub's ``detectors`` was silently ignored by the edge).
"""

from __future__ import annotations

import json
import logging
import re

from app.core.config import settings
from app.services.qwen_client import QwenError, QwenClient

log = logging.getLogger("app.agents.compiler")

# YOLOv8n COCO-80 video classes (the edge's YoloDetector vocabulary).
_VIDEO_CLASSES = frozenset({
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
    "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
    "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
    "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
    "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
    "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
    "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
    "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
    "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator",
    "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush",
})
# YAMNet security audio classes (the edge's YamnetDetector vocabulary).
_AUDIO_CLASSES = frozenset({"glass-break", "scream", "crying", "gunshot", "alarm"})
_ALLOWED_CLASSES = _VIDEO_CLASSES | _AUDIO_CLASSES

_DEFAULTS = {"min_confidence": 0.5, "dwell_s": 3.0, "cooldown_s": 30.0}
_HHMM = re.compile(r"^\d{1,2}:\d{2}$")


# --------------------------------------------------------------------------- public API

async def compile_agent_rule(nl_rule: str) -> tuple[str, dict]:
    """Compile a natural-language rule into (compiled_prompt, compiled_edge_config).

    Never raises: falls back to the keyword compiler in test/key-less environments or on
    any LLM/parse error.
    """
    normalized = " ".join(nl_rule.split())
    if settings.app_env == "test" or not settings.qwen_api_key:
        return _keyword_compile(normalized)
    try:
        obj = await _llm_compile(normalized)
        return _compiled_prompt(obj, normalized), _validate_config(obj)
    except (QwenError, ValueError, KeyError, TypeError) as exc:
        log.warning("NL-rule LLM compile failed (%s); using keyword fallback", exc)
        return _keyword_compile(normalized)


# ------------------------------------------------------------------------------- LLM path

_SYSTEM_PROMPT = (
    "You compile a home-security user rule into a JSON edge-detector config. Reply with ONLY "
    "a JSON object (no markdown, no prose) with these keys:\n"
    '  "classes":        array of detector classes to watch (see the allowed list; use the '
    "exact spellings)\n"
    '  "min_confidence": number 0..1 (detector confidence gate; default 0.5)\n'
    '  "dwell_s":        number of seconds the subject must persist before firing (default 3)\n'
    '  "cooldown_s":     number of seconds to suppress re-fires after one fires (default 30)\n'
    '  "schedule":       optional {"days":[0-6 Mon=0], "start":"HH:MM", "end":"HH:MM"} — include '
    "ONLY if the rule names a time/day window; overnight windows (start>end) are allowed\n"
    '  "compiled_prompt": a single crisp restatement of the rule for a verification model\n'
    "Allowed VIDEO classes are the COCO-80 set (person, dog, cat, car, bicycle, backpack, "
    "handbag, suitcase, knife, ...). Allowed AUDIO classes are exactly: glass-break, scream, "
    "crying, gunshot, alarm. Pick the smallest set of classes that captures the rule; if unsure, "
    'use ["person"]. Do not invent classes outside these sets.'
)

_FEWSHOT = [
    ("Alert me when a person is present in the room.",
     {"classes": ["person"], "min_confidence": 0.4, "dwell_s": 1.0, "cooldown_s": 15.0,
      "compiled_prompt": "A person is present in the room."}),
    ("Alert me if an unfamiliar person lingers at the front door after 9pm.",
     {"classes": ["person"], "min_confidence": 0.5, "dwell_s": 4.0, "cooldown_s": 30.0,
      "schedule": {"days": [0, 1, 2, 3, 4, 5, 6], "start": "21:00", "end": "06:00"},
      "compiled_prompt": "An unfamiliar person lingers at the front door during night hours."}),
    ("Tell me about breaking glass or a scream.",
     {"classes": ["glass-break", "scream"], "min_confidence": 0.4, "dwell_s": 0.5,
      "cooldown_s": 20.0, "compiled_prompt": "Breaking glass or a scream is heard."}),
]


def _compiler_messages(nl_rule: str) -> list[dict]:
    messages: list[dict] = [{"role": "system", "content": _SYSTEM_PROMPT}]
    for rule, out in _FEWSHOT:
        messages.append({"role": "user", "content": f"Rule: {rule}"})
        messages.append({"role": "assistant", "content": json.dumps(out)})
    messages.append({"role": "user", "content": f"Rule: {nl_rule}"})
    return messages


async def _llm_compile(nl_rule: str) -> dict:
    client = QwenClient(model=settings.qwen_text_model)
    response = await client.chat(_compiler_messages(nl_rule))
    obj = _extract_json(response.content)
    if obj is None:
        raise ValueError("compiler model did not return a JSON object")
    return obj


def _extract_json(raw: str | None) -> dict | None:
    """Best-effort pull a JSON object out of a model reply (handles ``` fences)."""
    if not raw:
        return None
    text = raw.strip()
    if text.startswith("```"):
        text = text.strip("`").strip()
        if text[:4].lower() == "json":
            text = text[4:].strip()
    start, end = text.find("{"), text.rfind("}")
    candidate = text[start : end + 1] if start != -1 and end > start else text
    try:
        obj = json.loads(candidate)
    except (ValueError, TypeError):
        return None
    return obj if isinstance(obj, dict) else None


# ------------------------------------------------------------------------- validation

def _validate_config(obj: dict) -> dict:
    """Coerce a loosely-shaped model config into a safe edge config. Never trusts the LLM."""
    config: dict = {
        "classes": _clean_classes(obj.get("classes")),
        "min_confidence": _clamp01(obj.get("min_confidence"), _DEFAULTS["min_confidence"]),
        "dwell_s": _positive(obj.get("dwell_s"), _DEFAULTS["dwell_s"]),
        "cooldown_s": _positive(obj.get("cooldown_s"), _DEFAULTS["cooldown_s"]),
    }
    schedule = _clean_schedule(obj.get("schedule"))
    if schedule:
        config["schedule"] = schedule
    roi = _clean_roi(obj.get("roi"))
    if roi:
        config["roi"] = roi
    return config


def _clean_classes(value) -> list[str]:
    """Keep only allowed classes, de-duped in order; default to ['person'] if none survive."""
    if not isinstance(value, (list, tuple)):
        return ["person"]
    seen: list[str] = []
    for item in value:
        name = str(item).strip().lower()
        if name in _ALLOWED_CLASSES and name not in seen:
            seen.append(name)
    return seen or ["person"]


def _clamp01(value, default: float) -> float:
    try:
        return max(0.0, min(1.0, float(value)))
    except (TypeError, ValueError):
        return default


def _positive(value, default: float) -> float:
    try:
        num = float(value)
        return num if num > 0 else default
    except (TypeError, ValueError):
        return default


def _clean_schedule(value) -> dict | None:
    if not isinstance(value, dict):
        return None
    start, end = value.get("start"), value.get("end")
    if not (isinstance(start, str) and isinstance(end, str) and _HHMM.match(start) and _HHMM.match(end)):
        return None
    schedule: dict = {"start": start, "end": end}
    days = value.get("days")
    if isinstance(days, (list, tuple)):
        clean_days = sorted({int(d) for d in days if isinstance(d, (int, float)) and 0 <= int(d) <= 6})
        if clean_days:
            schedule["days"] = clean_days
    return schedule


def _clean_roi(value) -> list[float] | None:
    if not isinstance(value, (list, tuple)) or len(value) != 4:
        return None
    try:
        return [float(v) for v in value]
    except (TypeError, ValueError):
        return None


def _compiled_prompt(obj: dict, normalized: str) -> str:
    prompt = obj.get("compiled_prompt")
    if isinstance(prompt, str) and prompt.strip():
        return prompt.strip()
    return normalized


# --------------------------------------------------------------- deterministic fallback

# keyword -> canonical class. Order-independent; first match wins per keyword.
_VIDEO_KEYWORDS = {
    "person": "person", "people": "person", "someone": "person", "somebody": "person",
    "stranger": "person", "intruder": "person", "burglar": "person", "prowler": "person",
    "visitor": "person", "human": "person", "man": "person", "woman": "person", "child": "person",
    "dog": "dog", "puppy": "dog", "cat": "cat", "kitten": "cat",
    "car": "car", "vehicle": "car", "bicycle": "bicycle", "bike": "bicycle",
    "motorcycle": "motorcycle", "truck": "truck", "backpack": "backpack", "handbag": "handbag",
    "suitcase": "suitcase", "knife": "knife",
}
_AUDIO_KEYWORDS = {
    "glass": "glass-break", "shatter": "glass-break", "window break": "glass-break",
    "scream": "scream", "screaming": "scream", "shout": "scream", "yell": "scream",
    "alarm": "alarm", "smoke": "alarm", "siren": "alarm", "fire": "alarm",
    "cry": "crying", "crying": "crying", "sob": "crying", "baby": "crying", "infant": "crying",
    "gun": "gunshot", "gunshot": "gunshot", "gunfire": "gunshot", "shot": "gunshot",
}
_AFTER_TIME = re.compile(r"after\s+(\d{1,2})\s*(am|pm)", re.I)


def _keyword_compile(normalized: str) -> tuple[str, dict]:
    text = normalized.lower()
    classes: list[str] = []
    if "pet" in text:
        classes += ["dog", "cat"]
    for kw, cls in {**_VIDEO_KEYWORDS, **_AUDIO_KEYWORDS}.items():
        if kw in text and cls not in classes:
            classes.append(cls)
    if not classes:
        classes = ["person"]

    config = {
        "classes": classes,
        "min_confidence": _DEFAULTS["min_confidence"],
        "dwell_s": _DEFAULTS["dwell_s"],
        "cooldown_s": _DEFAULTS["cooldown_s"],
    }
    schedule = _keyword_schedule(text)
    if schedule:
        config["schedule"] = schedule
    return normalized, config


def _keyword_schedule(text: str) -> dict | None:
    match = _AFTER_TIME.search(text)
    if match:
        hour = int(match.group(1)) % 12
        if match.group(2).lower() == "pm":
            hour += 12
        return {"start": f"{hour:02d}:00", "end": "06:00"}
    if "overnight" in text or "at night" in text or "night" in text:
        return {"start": "21:00", "end": "06:00"}
    return None
