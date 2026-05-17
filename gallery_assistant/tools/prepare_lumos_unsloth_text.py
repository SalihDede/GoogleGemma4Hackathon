#!/usr/bin/env python3
"""Prepare Lumos HF datasets for Unsloth text SFT.

This script intentionally outputs a `text` column. Unsloth's text SFT path is
most reliable when every row is already rendered through the target model's chat
template and passed to SFTTrainer with dataset_text_field="text".

It keeps tool calls as visible assistant text:
  <tool_call>{"tool_calls":[...]}</tool_call>
and tool results as visible user/tool-observation text:
  <tool_result>{...}</tool_result>

That shape is easier for a text-only LoRA to learn than raw Python dictionaries
inside assistant.tool_calls, because the tokenizer/chat template will not drop
unknown fields.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


DEFAULT_DATASET = "SalihHub/lumos-tool-messages-unsloth"
DEFAULT_OUT = Path("data_generation/out/lumos_unsloth_text_train.jsonl")

TOOL_CALL_RE = re.compile(r"^\s*<tool_call>\s*(.*?)\s*</tool_call>\s*$", re.S)
TOOL_RESULT_RE = re.compile(r"^\s*<tool_result>\s*(.*?)\s*</tool_result>\s*$", re.S)

TOOL_ALIASES = {
    "read_distance_sensor": "detect_near_obstacle",
    "captureCameraFrame": "capture_image",
    "capture_camera_frame": "capture_image",
    "describe_current_scene": "capture_image",
}

KNOWN_OLD_TOOLS_TO_DROP = {
    "internet_connection_status",
    "get_directions",
    "get_location_info",
}

SHORT_SYSTEM = (
    "You are Lumos, a visual assistant for visually impaired users. "
    "Always reply in the same language as the user. Use tools instead of "
    "guessing current scene, sensor, date, time, contact, or reminder facts. "
    "Keep final answers short, safe, and TTS-friendly. Write your name as "
    "Lumos, never as all-caps."
)


def dump_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def load_tool_names(path: Path | None) -> set[str]:
    if path is None:
        return {
            "describe_scene",
            "read_text",
            "identify_object",
            "check_sensor_context",
            "measure_brightness",
            "detect_near_obstacle",
            "get_environment_status",
            "detect_motion_state",
            "capture_image",
            "set_reminder",
            "search_contact",
            "cancel_action",
            "get_date",
            "get_time",
            "make_call",
        }
    with path.open("r", encoding="utf-8") as f:
        return {tool["name"] for tool in json.load(f)}


def repair_text(text: str, enabled: bool) -> str:
    if not enabled:
        return text
    try:
        from ftfy import fix_text  # type: ignore

        return fix_text(text)
    except Exception:
        pass
    if not any(marker in text for marker in ("Ã", "Ä", "Å", "â")):
        return text
    try:
        fixed = text.encode("latin-1").decode("utf-8")
        if len(fixed) >= len(text) * 0.75:
            return fixed
    except Exception:
        return text
    return text


def normalize_tool_name(name: str) -> str:
    return TOOL_ALIASES.get(name, name)


def normalize_tool_call_text(
    content: str,
    *,
    allowed_tools: set[str],
    unknown_tools: str,
) -> tuple[str | None, list[str]]:
    match = TOOL_CALL_RE.match(content)
    if not match:
        return content, []

    issues: list[str] = []
    payload = json.loads(match.group(1))
    raw_calls = payload.get("tool_calls")
    if not isinstance(raw_calls, list):
        return None, ["bad_tool_calls"]

    calls = []
    for call in raw_calls:
        if not isinstance(call, dict):
            issues.append("non_object_tool_call")
            continue
        name = normalize_tool_name(str(call.get("name", "")))
        if name in KNOWN_OLD_TOOLS_TO_DROP:
            issues.append(f"dropped_old_tool:{name}")
            if unknown_tools == "skip_row":
                return None, issues
            continue
        if name not in allowed_tools:
            issues.append(f"unknown_tool:{name}")
            if unknown_tools == "skip_row":
                return None, issues
            if unknown_tools == "drop_call":
                continue
        args = call.get("arguments", {})
        if not isinstance(args, dict):
            args = {}
        calls.append({"name": name, "arguments": args})

    if not calls:
        return None, issues + ["empty_tool_call_after_filter"]
    return f"<tool_call>{dump_json({'tool_calls': calls})}</tool_call>", issues


def normalize_tool_result_text(
    content: str,
    *,
    allowed_tools: set[str],
    unknown_tools: str,
) -> tuple[str | None, list[str]]:
    match = TOOL_RESULT_RE.match(content)
    if not match:
        return content, []

    issues: list[str] = []
    payload = json.loads(match.group(1))
    name = normalize_tool_name(str(payload.get("name", "")))
    if name in KNOWN_OLD_TOOLS_TO_DROP:
        issues.append(f"dropped_old_tool_result:{name}")
        if unknown_tools == "skip_row":
            return None, issues
    elif name not in allowed_tools:
        issues.append(f"unknown_tool_result:{name}")
        if unknown_tools == "skip_row":
            return None, issues

    payload["name"] = name
    return f"<tool_result>{dump_json(payload)}</tool_result>", issues


def normalize_messages(
    raw_messages: list[dict[str, Any]],
    *,
    allowed_tools: set[str],
    unknown_tools: str,
    fix_mojibake: bool,
    short_system: bool,
) -> tuple[list[dict[str, str]] | None, list[str]]:
    messages: list[dict[str, str]] = []
    issues: list[str] = []

    for raw in raw_messages:
        if not isinstance(raw, dict):
            issues.append("non_object_message")
            continue
        role = raw.get("role")
        content = repair_text(str(raw.get("content", "")), fix_mojibake)

        if role == "system":
            if not messages:
                messages.append({"role": "system", "content": SHORT_SYSTEM if short_system else content})
            continue
        if role == "assistant":
            next_content, msg_issues = normalize_tool_call_text(
                content,
                allowed_tools=allowed_tools,
                unknown_tools=unknown_tools,
            )
            issues.extend(msg_issues)
            if next_content is None:
                return None, issues
            messages.append({"role": "assistant", "content": next_content})
            continue
        if role in {"user", "tool"}:
            next_content, msg_issues = normalize_tool_result_text(
                content,
                allowed_tools=allowed_tools,
                unknown_tools=unknown_tools,
            )
            issues.extend(msg_issues)
            if next_content is None:
                return None, issues
            # Gemma chat training has only system/user/assistant roles. Keeping
            # tool observations as user messages prevents template incompatibility.
            messages.append({"role": "user", "content": next_content})
            continue
        issues.append(f"unknown_role:{role}")

    if not any(m["role"] == "user" for m in messages):
        return None, issues + ["missing_user"]
    if not any(m["role"] == "assistant" for m in messages):
        return None, issues + ["missing_assistant"]
    return messages, issues


def fallback_gemma_template(messages: list[dict[str, str]]) -> str:
    """Best-effort Gemma-like template used only when no tokenizer is loaded."""

    chunks = []
    for msg in messages:
        role = "model" if msg["role"] == "assistant" else msg["role"]
        chunks.append(f"<start_of_turn>{role}\n{msg['content']}<end_of_turn>")
    return "\n".join(chunks)


def load_tokenizer(model_name: str | None):
    if not model_name:
        return None
    try:
        from transformers import AutoTokenizer  # type: ignore
    except ImportError as exc:
        raise SystemExit("Missing dependency: transformers. Install it or omit --tokenizer-model.") from exc
    return AutoTokenizer.from_pretrained(model_name, trust_remote_code=True)


def render_text(messages: list[dict[str, str]], tokenizer: Any | None) -> str:
    if tokenizer is None:
        return fallback_gemma_template(messages)
    return tokenizer.apply_chat_template(
        messages,
        tokenize=False,
        add_generation_prompt=False,
    )


def iter_hf_dataset(repo_id: str, split: str, limit: int | None):
    try:
        from datasets import load_dataset  # type: ignore
    except ImportError as exc:
        raise SystemExit("Missing dependency: datasets. Install with `pip install datasets`.") from exc

    dataset = load_dataset(repo_id, split=split)
    if limit is not None:
        dataset = dataset.select(range(min(limit, len(dataset))))
    for row in dataset:
        yield row


def prepare(args: argparse.Namespace) -> dict[str, Any]:
    allowed_tools = load_tool_names(args.tools)
    tokenizer = load_tokenizer(args.tokenizer_model)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    total = kept = skipped = 0
    issue_counts: dict[str, int] = {}
    language_counts: dict[str, int] = {}

    with args.out.open("w", encoding="utf-8", newline="\n") as f:
        for row in iter_hf_dataset(args.repo_id, args.split, args.limit):
            total += 1
            raw_messages = row.get("messages")
            if not isinstance(raw_messages, list):
                skipped += 1
                issue_counts["missing_messages"] = issue_counts.get("missing_messages", 0) + 1
                continue

            messages, issues = normalize_messages(
                raw_messages,
                allowed_tools=allowed_tools,
                unknown_tools=args.unknown_tools,
                fix_mojibake=args.fix_mojibake,
                short_system=args.short_system,
            )
            for issue in issues:
                issue_counts[issue] = issue_counts.get(issue, 0) + 1
            if messages is None:
                skipped += 1
                continue

            text = render_text(messages, tokenizer)
            if "<tool_call>" not in text and args.require_tool_call:
                skipped += 1
                issue_counts["missing_tool_call_text"] = issue_counts.get("missing_tool_call_text", 0) + 1
                continue

            language = args.language
            language_counts[language] = language_counts.get(language, 0) + 1
            out_row = {
                "id": f"lumos_unsloth_{args.split}_{total:06d}",
                "source": args.repo_id,
                "language": language,
                "messages": messages,
                "text": text,
            }
            f.write(dump_json(out_row))
            f.write("\n")
            kept += 1

    return {
        "repo_id": args.repo_id,
        "split": args.split,
        "out": str(args.out),
        "tokenizer_model": args.tokenizer_model or "fallback_gemma_template",
        "total": total,
        "kept": kept,
        "skipped": skipped,
        "language_counts": language_counts,
        "issues": issue_counts,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-id", default=DEFAULT_DATASET)
    parser.add_argument("--split", default="train")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--tools", type=Path, default=Path("data_generation/lumos_tools.json"))
    parser.add_argument("--tokenizer-model", help="Use the exact Gemma tokenizer to render text.")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--language", default="tr")
    parser.add_argument("--unknown-tools", choices=["skip_row", "drop_call", "keep"], default="skip_row")
    parser.add_argument("--fix-mojibake", action="store_true")
    parser.add_argument("--short-system", action="store_true", default=True)
    parser.add_argument("--keep-original-system", dest="short_system", action="store_false")
    parser.add_argument("--require-tool-call", action="store_true")
    args = parser.parse_args()

    report = prepare(args)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["kept"] else 1


if __name__ == "__main__":
    sys.exit(main())

