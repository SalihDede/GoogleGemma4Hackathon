#!/usr/bin/env python3
"""Inspect a prepared Unsloth JSONL dataset."""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("jsonl", type=Path)
    parser.add_argument("--samples", type=int, default=2)
    parser.add_argument("--max-chars", type=int, default=2500)
    args = parser.parse_args()

    lengths = []
    tool_rows = 0
    rows = []
    with args.jsonl.open("r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            row = json.loads(line)
            text = row.get("text", "")
            lengths.append(len(text))
            if "<tool_call>" in text:
                tool_rows += 1
            if len(rows) < args.samples:
                rows.append(row)

    print(json.dumps({
        "file": str(args.jsonl),
        "rows": len(lengths),
        "tool_call_rows": tool_rows,
        "min_chars": min(lengths) if lengths else 0,
        "median_chars": int(statistics.median(lengths)) if lengths else 0,
        "max_chars": max(lengths) if lengths else 0,
    }, ensure_ascii=False, indent=2))

    for idx, row in enumerate(rows, 1):
        print(f"\n--- SAMPLE {idx}: {row.get('id')} ---")
        text = row.get("text", "")
        print(text[: args.max_chars])
        if len(text) > args.max_chars:
            print("\n...[truncated]...")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

