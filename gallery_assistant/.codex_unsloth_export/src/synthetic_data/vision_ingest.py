from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterable

from synthetic_data.io_utils import write_jsonl
from synthetic_data.prompts import LUMOS_SYSTEM_CONTRACT


DEFAULT_GENERAL_QUESTIONS = [
    "Ne var önümde?",
    "Şu an neredeyim?",
    "Önümde dikkat etmem gereken bir şey var mı?",
    "Burada nasıl ilerlemeliyim?",
]


def ingest_vision(
    *,
    source_dir: Path,
    out_path: Path,
    limit: int | None = None,
    include_disaster: bool = False,
) -> int:
    rows: list[dict] = []
    rows.extend(_ingest_indoor(source_dir))
    if include_disaster:
        rows.extend(_ingest_disaster(source_dir))
    if limit is not None:
        rows = rows[: max(0, limit)]
    return write_jsonl(out_path, rows)


def _ingest_indoor(source_dir: Path) -> list[dict]:
    roots = [
        source_dir / "indoorDatas" / "labeled_1150" / "data.json",
        source_dir / "indoorDatas" / "labeled_1150" / "phase2_qa.json",
        source_dir / "indoorDatas" / "labeled_1150" / "conversations.json",
        source_dir / "indoorDatas" / "labeledImages" / "dataset.json",
    ]
    rows: list[dict] = []
    for path in roots:
        if not path.exists():
            continue
        data = _load_list(path)
        base_dir = path.parent
        for item in data:
            image = str(item.get("image", "")).strip()
            if not image:
                continue
            absolute_image = str(_resolve_image(base_dir, image))
            rows.extend(_item_to_examples(item, absolute_image, source_name=path.name))
    return _dedupe(rows)


def _ingest_disaster(source_dir: Path) -> list[dict]:
    path = source_dir / "Comprehensive Disaster Dataset(CDD)" / "cdd_qa.json"
    if not path.exists():
        return []
    data = _load_list(path)
    base_dir = path.parent
    rows: list[dict] = []
    for item in data:
        image = str(item.get("image", "")).strip()
        if not image:
            continue
        absolute_image = str(_resolve_image(base_dir, image))
        for qa in item.get("qa_pairs", []):
            question = str(qa.get("question", "")).strip()
            answer = str(qa.get("answer", "")).strip()
            if question and answer:
                rows.append(
                    _example(
                        image=absolute_image,
                        question=question,
                        answer=answer,
                        scenario="local_disaster_visual_qa",
                        tags=["vision", "tool_call", "local_dataset", "safety", "disaster", "tr"],
                        source_name="cdd_qa.json",
                        risk="high",
                    )
                )
    return rows


def _item_to_examples(item: dict[str, Any], image: str, source_name: str) -> list[dict]:
    rows: list[dict] = []
    description = str(item.get("description", "")).strip()
    if description:
        for question in DEFAULT_GENERAL_QUESTIONS[:2]:
            rows.append(
                _example(
                    image=image,
                    question=question,
                    answer=description,
                    scenario="local_general_visual_question",
                    tags=["vision", "tool_call", "local_dataset", "general_scene", "tr"],
                    source_name=source_name,
                    risk="medium",
                )
            )

    for qa in item.get("qa_pairs", []) or []:
        question = str(qa.get("question", "")).strip()
        answer = str(qa.get("answer", "")).strip()
        if question and answer:
            rows.append(
                _example(
                    image=image,
                    question=question,
                    answer=answer,
                    scenario="local_visual_qa",
                    tags=["vision", "tool_call", "local_dataset", "tr"],
                    source_name=source_name,
                    risk="medium",
                )
            )

    messages = item.get("messages") or item.get("conversations") or []
    rows.extend(_conversation_to_examples(messages, image, source_name))
    return rows


def _conversation_to_examples(messages: list[Any], image: str, source_name: str) -> list[dict]:
    rows: list[dict] = []
    pending_question: str | None = None
    for message in messages:
        if not isinstance(message, dict):
            continue
        role = message.get("role")
        text = _extract_text(message.get("content"))
        if role == "user" and text:
            pending_question = text
        elif role == "assistant" and pending_question and text:
            rows.append(
                _example(
                    image=image,
                    question=pending_question,
                    answer=text,
                    scenario="local_visual_conversation",
                    tags=["vision", "tool_call", "local_dataset", "conversation", "tr"],
                    source_name=source_name,
                    risk="medium",
                )
            )
            pending_question = None
    return rows


def _example(
    *,
    image: str,
    question: str,
    answer: str,
    scenario: str,
    tags: list[str],
    source_name: str,
    risk: str,
) -> dict:
    example_id = _stable_id(image, question, answer)
    focus = _focus_for_question(question)
    return {
        "id": example_id,
        "language": "tr",
        "scenario": scenario,
        "messages": [
            {"role": "system", "content": LUMOS_SYSTEM_CONTRACT},
            {
                "role": "user",
                "content": [
                    {"type": "image", "path": image},
                    {"type": "text", "text": question},
                ],
            },
            {
                "role": "assistant",
                "tool_calls": [{"name": "describe_scene", "arguments": {"focus": focus}}],
            },
            {
                "role": "tool",
                "name": "describe_scene",
                "content": {
                    "image_path": image,
                    "visual_answer": answer,
                    "style": "body-relative accessibility description",
                },
            },
            {"role": "assistant", "content": _clean_answer(answer)},
        ],
        "tags": tags,
        "metadata": {
            "source": source_name,
            "risk": risk,
            "image_path": image,
            "conversion": "local-image-label-to-tool-call",
        },
    }


def _focus_for_question(question: str) -> str:
    lowered = question.lower()
    if any(word in lowered for word in ["engel", "tehlike", "dikkat", "güvenli"]):
        return "obstacles"
    if any(word in lowered for word in ["neredeyim", "nerede", "mekan", "alan"]):
        return "place"
    if any(word in lowered for word in ["yaz", "tabela", "metin", "etiket"]):
        return "text"
    if any(word in lowered for word in ["nasıl", "ulaş", "ilerle", "çıkış", "kapı"]):
        return "route"
    return "general"


def _clean_answer(answer: str) -> str:
    cleaned = " ".join(answer.split())
    banned_prefixes = [
        "Bu görselde ",
        "Görselde ",
        "Resimde ",
        "Fotoğrafta ",
    ]
    for prefix in banned_prefixes:
        if cleaned.startswith(prefix):
            cleaned = cleaned[len(prefix) :].lstrip()
            break
    return cleaned


def _extract_text(content: Any) -> str:
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                parts.append(str(item.get("text", "")).strip())
        return " ".join(part for part in parts if part).strip()
    return ""


def _load_list(path: Path) -> list[dict[str, Any]]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, list):
        raise ValueError(f"{path} must contain a JSON list")
    return [item for item in raw if isinstance(item, dict)]


def _dedupe(rows: Iterable[dict]) -> list[dict]:
    seen: set[str] = set()
    result: list[dict] = []
    for row in rows:
        row_id = str(row.get("id"))
        if row_id in seen:
            continue
        seen.add(row_id)
        result.append(row)
    return result


def _stable_id(*parts: str) -> str:
    import hashlib

    digest = hashlib.sha1("\n".join(parts).encode("utf-8")).hexdigest()[:16]
    return f"lumos_vision_{digest}"


def _resolve_image(base_dir: Path, image: str) -> Path:
    direct = (base_dir / image).resolve()
    if direct.exists():
        return direct
    nested = (base_dir / "images" / image).resolve()
    if nested.exists():
        return nested
    return direct
