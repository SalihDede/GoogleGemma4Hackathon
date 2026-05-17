#!/usr/bin/env python3
"""Validate Lumos synthetic SFT JSONL files."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TOOLS = ROOT / "data_generation" / "lumos_tools.json"

ALLOWED_ROLES = {"system", "user", "assistant", "tool"}
FORBIDDEN_FINAL_PATTERNS = [
    re.compile(r"\bLUMOS\b"),
    re.compile(r"\bas you can see\b", re.I),
    re.compile(r"\blook at\b", re.I),
    re.compile(r"\bin the picture\b", re.I),
    re.compile(r"\bthe image shows\b", re.I),
    re.compile(r"https?://", re.I),
    re.compile(r"```"),
    re.compile(r"(^|\n)\s*[-*#]\s+"),
]


def load_tool_names(path: Path) -> set[str]:
    with path.open("r", encoding="utf-8") as f:
        tools = json.load(f)
    return {tool["name"] for tool in tools}


def load_jsonl(path: Path) -> list[tuple[int, dict[str, Any]]]:
    rows: list[tuple[int, dict[str, Any]]] = []
    with path.open("r", encoding="utf-8") as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                value = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_no}: invalid JSON: {exc}") from exc
            if not isinstance(value, dict):
                raise ValueError(f"{path}:{line_no}: row is not an object")
            rows.append((line_no, value))
    return rows


def validate_tool_call(
    *,
    row_id: str,
    index: int,
    call: Any,
    tool_names: set[str],
    seen_call_ids: set[str],
    errors: list[str],
) -> None:
    if not isinstance(call, dict):
        errors.append(f"{row_id}: assistant tool_calls[{index}] is not an object")
        return
    call_id = call.get("id")
    if not isinstance(call_id, str) or not call_id:
        errors.append(f"{row_id}: tool call {index} missing id")
    else:
        seen_call_ids.add(call_id)
    if call.get("type") != "function":
        errors.append(f"{row_id}: tool call {index} type must be function")
    fn = call.get("function")
    if not isinstance(fn, dict):
        errors.append(f"{row_id}: tool call {index} missing function")
        return
    name = fn.get("name")
    if name not in tool_names:
        errors.append(f"{row_id}: unknown tool name {name!r}")
    args = fn.get("arguments")
    if not isinstance(args, str):
        errors.append(f"{row_id}: tool {name} arguments must be a JSON string")
    else:
        try:
            parsed = json.loads(args or "{}")
            if not isinstance(parsed, dict):
                errors.append(f"{row_id}: tool {name} arguments must decode to object")
        except json.JSONDecodeError as exc:
            errors.append(f"{row_id}: tool {name} arguments invalid JSON: {exc}")


def validate_row(line_no: int, row: dict[str, Any], tool_names: set[str]) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    row_id = str(row.get("id") or f"line {line_no}")
    messages = row.get("messages")
    if not isinstance(messages, list) or not messages:
        return [f"{row_id}: messages must be a non-empty list"], warnings

    seen_user = False
    seen_final = False
    seen_call_ids: set[str] = set()
    used_tool_ids: set[str] = set()

    for i, msg in enumerate(messages):
        if not isinstance(msg, dict):
            errors.append(f"{row_id}: messages[{i}] is not an object")
            continue
        role = msg.get("role")
        if role not in ALLOWED_ROLES:
            errors.append(f"{row_id}: messages[{i}] invalid role {role!r}")
            continue
        if role == "user":
            seen_user = True
        if role in {"system", "user"} and not isinstance(msg.get("content"), str):
            errors.append(f"{row_id}: {role} message {i} content must be string")
        if role == "assistant":
            tool_calls = msg.get("tool_calls")
            if tool_calls is not None:
                if not isinstance(tool_calls, list) or not tool_calls:
                    errors.append(f"{row_id}: assistant message {i} tool_calls must be non-empty list")
                else:
                    for j, call in enumerate(tool_calls):
                        validate_tool_call(
                            row_id=row_id,
                            index=j,
                            call=call,
                            tool_names=tool_names,
                            seen_call_ids=seen_call_ids,
                            errors=errors,
                        )
            else:
                content = msg.get("content")
                if isinstance(content, str) and content.strip():
                    seen_final = True
                    for pattern in FORBIDDEN_FINAL_PATTERNS:
                        if pattern.search(content):
                            warnings.append(f"{row_id}: final assistant text may violate TTS/style rule: {pattern.pattern}")
                else:
                    errors.append(f"{row_id}: assistant message {i} needs content or tool_calls")
        if role == "tool":
            name = msg.get("name")
            if name not in tool_names:
                errors.append(f"{row_id}: tool message {i} unknown name {name!r}")
            call_id = msg.get("tool_call_id")
            if not isinstance(call_id, str) or not call_id:
                errors.append(f"{row_id}: tool message {i} missing tool_call_id")
            else:
                used_tool_ids.add(call_id)
            content = msg.get("content")
            if not isinstance(content, str):
                errors.append(f"{row_id}: tool message {i} content must be string")

    missing = used_tool_ids - seen_call_ids
    if missing:
        errors.append(f"{row_id}: tool messages reference unknown call ids: {sorted(missing)}")
    if not seen_user:
        errors.append(f"{row_id}: no user message")
    if not seen_final:
        errors.append(f"{row_id}: no final assistant text message")
    return errors, warnings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("jsonl", type=Path)
    parser.add_argument("--tools", type=Path, default=DEFAULT_TOOLS)
    args = parser.parse_args()

    tool_names = load_tool_names(args.tools)
    rows = load_jsonl(args.jsonl)
    all_errors: list[str] = []
    all_warnings: list[str] = []
    tool_call_rows = 0

    for line_no, row in rows:
        errors, warnings = validate_row(line_no, row, tool_names)
        all_errors.extend(errors)
        all_warnings.extend(warnings)
        if any(msg.get("role") == "assistant" and msg.get("tool_calls") for msg in row.get("messages", []) if isinstance(msg, dict)):
            tool_call_rows += 1

    for warning in all_warnings:
        print(f"WARNING: {warning}")
    for error in all_errors:
        print(f"ERROR: {error}")

    print(
        json.dumps(
            {
                "file": str(args.jsonl),
                "rows": len(rows),
                "tool_call_rows": tool_call_rows,
                "warnings": len(all_warnings),
                "errors": len(all_errors),
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 1 if all_errors else 0


if __name__ == "__main__":
    sys.exit(main())

