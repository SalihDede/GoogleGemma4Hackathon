#!/usr/bin/env python3
"""Convert existing Hugging Face Lumos datasets into canonical SFT JSONL."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TOOLS = ROOT / "data_generation" / "lumos_tools.json"
DEFAULT_OUT = ROOT / "data_generation" / "out" / "lumos_tool_messages_canonical.jsonl"
DEFAULT_TOOL_DATASET = "SalihHub/lumos-tool-messages-unsloth"

MINIMAL_SYSTEM = (
    "You are Lumos, a visual assistant for visually impaired users. "
    "Always reply in the same language the user writes in. Use tools instead "
    "of guessing current scene, sensor, date, time, contact, or reminder facts. "
    "Keep final answers short, safe, and TTS-friendly. Never write your name "
    "as LUMOS in final answers; write Lumos."
)

TOOL_CALL_RE = re.compile(r"^\s*<tool_call>\s*(.*?)\s*</tool_call>\s*$", re.S)
TOOL_RESULT_RE = re.compile(r"^\s*<tool_result>\s*(.*?)\s*</tool_result>\s*$", re.S)

TOOL_ALIASES = {
    "read_distance_sensor": "detect_near_obstacle",
    "captureCameraFrame": "capture_image",
    "capture_camera_frame": "capture_image",
    "describe_current_scene": "capture_image",
}


def load_tool_names(path: Path) -> set[str]:
    with path.open("r", encoding="utf-8") as f:
        tools = json.load(f)
    return {tool["name"] for tool in tools}


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


def dump_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def parse_tag(pattern: re.Pattern[str], content: str) -> dict[str, Any] | None:
    match = pattern.match(content or "")
    if not match:
        return None
    return json.loads(match.group(1))


def convert_tool_call(
    payload: dict[str, Any],
    *,
    allowed_tools: set[str],
    unknown_policy: str,
    counter: int,
) -> tuple[dict[str, Any] | None, list[str], int]:
    raw_calls = payload.get("tool_calls")
    if not isinstance(raw_calls, list) or not raw_calls:
        return None, ["empty_tool_calls"], counter

    calls = []
    issues = []
    for raw_call in raw_calls:
        if not isinstance(raw_call, dict):
            issues.append("non_object_tool_call")
            continue
        name = normalize_tool_name(str(raw_call.get("name", "")))
        if name not in allowed_tools:
            issues.append(f"unknown_tool:{name}")
            if unknown_policy != "keep":
                continue
        args = raw_call.get("arguments", {})
        if not isinstance(args, dict):
            args = {}
        counter += 1
        calls.append(
            {
                "id": f"call_{counter}",
                "type": "function",
                "function": {"name": name, "arguments": dump_json(args)},
            }
        )

    if not calls:
        return None, issues, counter
    return {"role": "assistant", "content": "", "tool_calls": calls}, issues, counter


def convert_tool_result(
    payload: dict[str, Any],
    *,
    pending: list[tuple[str, str]],
    allowed_tools: set[str],
    unknown_policy: str,
) -> tuple[dict[str, Any] | None, str | None]:
    name = normalize_tool_name(str(payload.get("name", "")))
    if name not in allowed_tools and unknown_policy != "keep":
        return None, f"unknown_tool_result:{name}"

    call_id = ""
    for idx, (candidate_id, candidate_name) in enumerate(pending):
        if candidate_name == name:
            call_id = candidate_id
            pending.pop(idx)
            break
    if not call_id and pending:
        call_id = pending.pop(0)[0]
    if not call_id:
        return None, f"orphan_tool_result:{name}"

    return (
        {
            "role": "tool",
            "tool_call_id": call_id,
            "name": name,
            "content": dump_json(payload.get("content", {})),
        },
        None,
    )


def convert_messages(
    raw_messages: list[dict[str, Any]],
    *,
    allowed_tools: set[str],
    unknown_policy: str,
    fix_mojibake: bool,
    replace_system: bool,
) -> tuple[list[dict[str, Any]] | None, list[str]]:
    messages: list[dict[str, Any]] = []
    issues: list[str] = []
    pending: list[tuple[str, str]] = []
    counter = 0

    for raw in raw_messages:
        if not isinstance(raw, dict):
            issues.append("non_object_message")
            continue
        role = raw.get("role")
        content = repair_text(str(raw.get("content", "")), fix_mojibake)

        if role == "system":
            if not messages:
                messages.append({"role": "system", "content": MINIMAL_SYSTEM if replace_system else content})
            continue

        if role == "assistant":
            payload = parse_tag(TOOL_CALL_RE, content)
            if payload is not None:
                msg, call_issues, counter = convert_tool_call(
                    payload,
                    allowed_tools=allowed_tools,
                    unknown_policy=unknown_policy,
                    counter=counter,
                )
                issues.extend(call_issues)
                if msg is None:
                    if unknown_policy == "skip_row":
                        return None, issues
                    continue
                messages.append(msg)
                for call in msg["tool_calls"]:
                    pending.append((call["id"], call["function"]["name"]))
                continue
            messages.append({"role": "assistant", "content": content})
            continue

        if role in {"user", "tool"}:
            payload = parse_tag(TOOL_RESULT_RE, content)
            if payload is not None:
                msg, issue = convert_tool_result(
                    payload,
                    pending=pending,
                    allowed_tools=allowed_tools,
                    unknown_policy=unknown_policy,
                )
                if issue:
                    issues.append(issue)
                    if unknown_policy == "skip_row":
                        return None, issues
                if msg is not None:
                    messages.append(msg)
                continue
            messages.append({"role": "user", "content": content})
            continue

        issues.append(f"unknown_role:{role}")

    if not any(m.get("role") == "user" for m in messages):
        return None, issues + ["missing_user"]
    if not any(m.get("role") == "assistant" and m.get("content") for m in messages):
        return None, issues + ["missing_final_assistant"]
    return messages, issues


def iter_dataset(repo_id: str, split: str, limit: int | None):
    try:
        from datasets import load_dataset  # type: ignore
    except ImportError as exc:
        raise SystemExit("Missing dependency: datasets. Install with `pip install datasets`.") from exc

    dataset = load_dataset(repo_id, split=split)
    if limit is not None:
        dataset = dataset.select(range(min(limit, len(dataset))))
    for row in dataset:
        yield row


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-id", default=DEFAULT_TOOL_DATASET)
    parser.add_argument("--split", default="train")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--tools", type=Path, default=DEFAULT_TOOLS)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--language", default="tr")
    parser.add_argument("--unknown-tools", choices=["skip_row", "drop_call", "keep"], default="skip_row")
    parser.add_argument("--fix-mojibake", action="store_true")
    parser.add_argument("--replace-system", action="store_true", default=True)
    parser.add_argument("--keep-original-system", dest="replace_system", action="store_false")
    args = parser.parse_args()

    allowed_tools = load_tool_names(args.tools)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    total = kept = skipped = 0
    issue_counts: dict[str, int] = {}

    with args.out.open("w", encoding="utf-8", newline="\n") as f:
        for row in iter_dataset(args.repo_id, args.split, args.limit):
            total += 1
            raw_messages = row.get("messages")
            if not isinstance(raw_messages, list):
                skipped += 1
                issue_counts["missing_messages"] = issue_counts.get("missing_messages", 0) + 1
                continue
            messages, issues = convert_messages(
                raw_messages,
                allowed_tools=allowed_tools,
                unknown_policy=args.unknown_tools,
                fix_mojibake=args.fix_mojibake,
                replace_system=args.replace_system,
            )
            for issue in issues:
                issue_counts[issue] = issue_counts.get(issue, 0) + 1
            if messages is None:
                skipped += 1
                continue
            kept += 1
            out_row = {
                "id": f"hf_lumos_tool_{args.split}_{total:06d}",
                "source": args.repo_id,
                "language": args.language,
                "task": "tool_reasoning",
                "risk": "unknown",
                "messages": messages,
            }
            f.write(dump_json(out_row))
            f.write("\n")

    report = {
        "repo_id": args.repo_id,
        "split": args.split,
        "out": str(args.out),
        "total": total,
        "kept": kept,
        "skipped": skipped,
        "issues": issue_counts,
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if kept else 1


if __name__ == "__main__":
    sys.exit(main())

