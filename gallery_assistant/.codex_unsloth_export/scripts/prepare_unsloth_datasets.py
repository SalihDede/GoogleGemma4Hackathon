from __future__ import annotations

import argparse
import json
import random
from pathlib import Path
from typing import Any


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            stripped = line.strip()
            if stripped:
                rows.append(json.loads(stripped))
    return rows


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")


def split_rows(
    rows: list[dict[str, Any]],
    *,
    seed: int,
    train_ratio: float,
    validation_ratio: float,
) -> dict[str, list[dict[str, Any]]]:
    copied = list(rows)
    random.Random(seed).shuffle(copied)
    train_end = int(len(copied) * train_ratio)
    validation_end = train_end + int(len(copied) * validation_ratio)
    return {
        "train": copied[:train_end],
        "validation": copied[train_end:validation_end],
        "test": copied[validation_end:],
    }


def content_to_text(content: Any) -> str:
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                text = str(item.get("text", "")).strip()
                if text:
                    parts.append(text)
        return "\n".join(parts).strip()
    return ""


def canonical_to_unsloth_messages(row: dict[str, Any], system_prompt: str) -> dict[str, Any]:
    messages = [{"role": "system", "content": system_prompt}]
    for message in row.get("messages", []):
        role = message.get("role")
        if role == "system":
            continue
        if role == "user":
            text = content_to_text(message.get("content"))
            if text:
                messages.append({"role": "user", "content": text})
            continue
        if role == "assistant":
            if isinstance(message.get("tool_calls"), list):
                payload = json.dumps(
                    {"tool_calls": message["tool_calls"]},
                    ensure_ascii=False,
                    separators=(",", ":"),
                )
                messages.append({"role": "assistant", "content": f"<tool_call>{payload}</tool_call>"})
                continue
            text = content_to_text(message.get("content"))
            if text:
                messages.append({"role": "assistant", "content": text})
            continue
        if role == "tool":
            payload = json.dumps(
                {"name": message.get("name"), "content": message.get("content")},
                ensure_ascii=False,
                separators=(",", ":"),
            )
            messages.append({"role": "user", "content": f"<tool_result>{payload}</tool_result>"})
    return {"messages": messages}


def extract_vision_qa(row: dict[str, Any], system_prompt: str) -> dict[str, Any] | None:
    image_path = normalize_image_path(str(row.get("metadata", {}).get("image_path", "")))
    question = ""
    answer = ""
    for message in row.get("messages", []):
        if message.get("role") == "user" and not question:
            question = content_to_text(message.get("content"))
        if message.get("role") == "assistant" and isinstance(message.get("content"), str):
            answer = message["content"].strip()
    if not image_path or not Path(image_path).exists() or not question or not answer:
        return None
    return {
        "image": image_path,
        "system": system_prompt,
        "question": question,
        "answer": answer,
    }


def normalize_image_path(path_text: str) -> str:
    if not path_text:
        return ""
    path = Path(path_text)
    if path.exists():
        return str(path)
    parent = path.parent
    candidate = parent / "images" / path.name
    if candidate.exists():
        return str(candidate)
    if parent.name == "images":
        return ""
    return ""


def prepare(
    *,
    synthetic_path: Path,
    vision_path: Path,
    system_prompt_path: Path,
    out_dir: Path,
    seed: int,
    train_ratio: float,
    validation_ratio: float,
) -> dict[str, Any]:
    system_prompt = system_prompt_path.read_text(encoding="utf-8").strip()

    synthetic_rows = read_jsonl(synthetic_path)
    tool_rows = [canonical_to_unsloth_messages(row, system_prompt) for row in synthetic_rows]
    tool_splits = split_rows(
        tool_rows,
        seed=seed,
        train_ratio=train_ratio,
        validation_ratio=validation_ratio,
    )
    tool_dir = out_dir / "tool_messages"
    for split, split_rows_ in tool_splits.items():
        write_jsonl(tool_dir / f"{split}.jsonl", split_rows_)

    vision_rows_raw = read_jsonl(vision_path)
    vision_rows = [
        row
        for row in (extract_vision_qa(raw, system_prompt) for raw in vision_rows_raw)
        if row is not None
    ]
    vision_splits = split_rows(
        vision_rows,
        seed=seed,
        train_ratio=train_ratio,
        validation_ratio=validation_ratio,
    )
    vision_dir = out_dir / "vision_qa"
    for split, split_rows_ in vision_splits.items():
        write_jsonl(vision_dir / f"{split}.jsonl", split_rows_)

    report = {
        "tool_messages": {
            "source": str(synthetic_path),
            "total": len(tool_rows),
            "splits": {name: len(rows) for name, rows in tool_splits.items()},
            "schema": {"messages": [{"role": "system|user|assistant", "content": "string"}]},
        },
        "vision_qa": {
            "source": str(vision_path),
            "total": len(vision_rows),
            "skipped_missing_image_or_text": len(vision_rows_raw) - len(vision_rows),
            "splits": {name: len(rows) for name, rows in vision_splits.items()},
            "schema": {
                "image": "image file path, cast to datasets.Image at upload",
                "system": "string",
                "question": "string",
                "answer": "string",
            },
        },
    }
    report_path = out_dir / "prepare_report.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--synthetic", type=Path, default=Path("data/processed/lumos.synthetic.valid.jsonl"))
    parser.add_argument("--vision", type=Path, default=Path("data/processed/vision.local.valid.jsonl"))
    parser.add_argument(
        "--system-prompt",
        type=Path,
        default=Path(r"C:\Users\Hp\Desktop\GoogleCompetitionUnsloth\unslothFinetune\sysPrompts\ENG.md"),
    )
    parser.add_argument("--out-dir", type=Path, default=Path("data/unsloth"))
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--train-ratio", type=float, default=0.95)
    parser.add_argument("--validation-ratio", type=float, default=0.03)
    args = parser.parse_args()
    report = prepare(
        synthetic_path=args.synthetic,
        vision_path=args.vision,
        system_prompt_path=args.system_prompt,
        out_dir=args.out_dir,
        seed=args.seed,
        train_ratio=args.train_ratio,
        validation_ratio=args.validation_ratio,
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

