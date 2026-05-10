from __future__ import annotations

import argparse
import os
from pathlib import Path

from datasets import Dataset, DatasetDict, Features, Image, Value
from dotenv import load_dotenv
from huggingface_hub import HfApi


def load_env(root: Path) -> None:
    load_dotenv(root / ".env")


def push_tool_messages(root: Path, repo_id: str, private: bool, token: str) -> None:
    base = root / "SyntheticData" / "data" / "unsloth" / "tool_messages"
    dataset = DatasetDict(
        {
            "train": Dataset.from_json(str(base / "train.jsonl")),
            "validation": Dataset.from_json(str(base / "validation.jsonl")),
            "test": Dataset.from_json(str(base / "test.jsonl")),
        }
    )
    dataset.push_to_hub(repo_id, private=private, token=token)


def push_vision_qa(root: Path, repo_id: str, private: bool, token: str) -> None:
    base = root / "SyntheticData" / "data" / "unsloth" / "vision_qa"
    features = Features(
        {
            "image": Image(),
            "system": Value("string"),
            "question": Value("string"),
            "answer": Value("string"),
        }
    )
    dataset = DatasetDict(
        {
            "train": Dataset.from_json(str(base / "train.jsonl"), features=features),
            "validation": Dataset.from_json(str(base / "validation.jsonl"), features=features),
            "test": Dataset.from_json(str(base / "test.jsonl"), features=features),
        }
    )
    dataset.push_to_hub(repo_id, private=private, token=token)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(r"C:\Users\Hp\Desktop\GoogleCompetitionUnsloth"))
    parser.add_argument("--tool-repo", required=True)
    parser.add_argument("--vision-repo", required=True)
    parser.add_argument("--public", action="store_true")
    parser.add_argument("--which", choices=["all", "tool", "vision"], default="all")
    args = parser.parse_args()

    load_env(args.root)
    token = os.environ.get("HF_TOKEN", "").strip()
    if not token:
        raise RuntimeError("HF_TOKEN not found in .env or environment")

    api = HfApi(token=token)
    who = api.whoami()
    print(f"Authenticated as: {who.get('name') or who}")
    private = not args.public

    if args.which in ("all", "tool"):
        print(f"Pushing tool messages dataset to {args.tool_repo} private={private}")
        push_tool_messages(args.root, args.tool_repo, private, token)
        print(f"Done: https://huggingface.co/datasets/{args.tool_repo}")

    if args.which in ("all", "vision"):
        print(f"Pushing vision QA dataset to {args.vision_repo} private={private}")
        push_vision_qa(args.root, args.vision_repo, private, token)
        print(f"Done: https://huggingface.co/datasets/{args.vision_repo}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

