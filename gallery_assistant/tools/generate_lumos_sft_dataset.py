#!/usr/bin/env python3
"""Generate synthetic Lumos SFT examples with OpenRouter.

The output is JSONL in OpenAI-style chat format with assistant tool_calls and
tool messages. It is intended for text/tool-reasoning fine-tuning, not visual
encoder fine-tuning.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import random
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TOOLS = ROOT / "data_generation" / "lumos_tools.json"
DEFAULT_SEEDS = ROOT / "data_generation" / "seed_scenarios.jsonl"
DEFAULT_OUT = ROOT / "data_generation" / "out" / "lumos_sft.jsonl"
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

MINIMAL_SYSTEM = (
    "You are Lumos, a visual assistant for visually impaired users. "
    "Reply in the user's language. Use tools instead of guessing current "
    "scene, sensor, date, time, contact, or reminder facts. Keep final "
    "answers short, safe, and TTS-friendly."
)

TEACHER_SYSTEM = """You create supervised fine-tuning data for Lumos.

Lumos is a Gemma 4 assistant for visually impaired users. The fine-tune is
TEXT/TOOL-REASONING ONLY. Do not train visual perception. Teach when to call
tools, which tool combinations are useful, how to summarize tool outputs, and
how to speak safely.

Return only valid JSON with this exact top-level shape:
{"examples":[...]}

Each example must be one JSON object with:
- id: short unique string
- source: "openrouter_synthetic_v1"
- language: "tr" or "en"
- task: concise task label
- risk: "low", "medium", or "high"
- messages: OpenAI-style messages list

Message rules:
- Use role system, user, assistant, and tool only.
- The first message should be the minimal Lumos system message provided.
- Assistant tool calls must use tool_calls with id, type="function", function.name, function.arguments.
- function.arguments must be a JSON string, not a raw object.
- Every tool message must reference tool_call_id and name.
- The final assistant message must be plain spoken text, not JSON.
- Do not include hidden chain-of-thought, analysis, markdown, bullets, tables, emojis, URLs, or code fences.
- Never write the assistant name as LUMOS in final answers. Use Lumos.
- Never use phrases like "as you can see", "look at", "in the picture", or "the image shows".
- For medicine, money, expiry dates, allergens, traffic, darkness, or physical hazards, be conservative and ask the user to verify when needed.
- Include negative examples only as corrected behavior, never as bad assistant output.

Tool reasoning rules:
- For current visual facts, call capture_image first instead of guessing.
- For reading current text, call capture_image and/or read_text.
- For walking safety, combine detect_near_obstacle, measure_brightness, and capture_image when useful.
- For weather/clothing without internet, use local sensors only and say it is not official weather.
- For calls, search_contact first, then ask confirmation before make_call.
- For date and time, call get_date or get_time.
- For simple greetings or identity questions, call no tool.
"""


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise SystemExit(f"{path}:{line_no}: invalid JSON: {exc}") from exc
    return rows


def write_jsonl(path: Path, rows: list[dict[str, Any]], append: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = "a" if append else "w"
    with path.open(mode, encoding="utf-8", newline="\n") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
            f.write("\n")


def tool_subset(tools: list[dict[str, Any]], names: list[str]) -> list[dict[str, Any]]:
    by_name = {tool["name"]: tool for tool in tools}
    subset = [by_name[name] for name in names if name in by_name]
    # Include no-tool examples with a tiny reference set, so the teacher knows what not to call.
    if not subset:
        return tools[:5]
    return subset


def build_prompt(seed: dict[str, Any], tools: list[dict[str, Any]], batch_size: int) -> str:
    subset = tool_subset(tools, seed.get("expected_tools", []))
    return json.dumps(
        {
            "instruction": (
                f"Create {batch_size} diverse high-quality SFT examples from this seed. "
                "Use Turkish unless the seed language is English. Vary the user wording, "
                "tool results, and final answer. Use only the allowed tools below."
            ),
            "minimal_system_message": MINIMAL_SYSTEM,
            "seed": seed,
            "allowed_tools": subset,
            "quality_targets": {
                "final_answer_max_sentences": 4,
                "plain_spoken_tts": True,
                "tool_calls_are_labels": True,
                "no_chain_of_thought": True,
                "body_relative_directions": True,
            },
        },
        ensure_ascii=False,
        indent=2,
    )


def extract_json_object(text: str) -> dict[str, Any]:
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError("No JSON object found in model response")
    return json.loads(text[start : end + 1])


def call_openrouter(
    *,
    api_key: str,
    model: str,
    prompt: str,
    temperature: float,
    max_tokens: int,
    response_format: str,
) -> dict[str, Any]:
    body: dict[str, Any] = {
        "model": model,
        "messages": [
            {"role": "system", "content": TEACHER_SYSTEM},
            {"role": "user", "content": prompt},
        ],
        "temperature": temperature,
        "top_p": 0.95,
        "max_tokens": max_tokens,
    }
    if response_format != "none":
        body["response_format"] = {"type": response_format}

    request = urllib.request.Request(
        OPENROUTER_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://lumos.local",
            "X-Title": "Lumos Synthetic SFT Generator",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"OpenRouter HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"OpenRouter request failed: {exc}") from exc

    try:
        content = payload["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as exc:
        raise RuntimeError(f"Unexpected OpenRouter response: {payload}") from exc
    if not content:
        raise RuntimeError(f"OpenRouter returned empty content: {payload}")
    return extract_json_object(content)


def dry_run_examples(seeds: list[dict[str, Any]], count: int) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    sample_seeds = (seeds * ((count // max(len(seeds), 1)) + 1))[:count]
    for i, seed in enumerate(sample_seeds, 1):
        tool_names = seed.get("expected_tools", [])
        messages: list[dict[str, Any]] = [
            {"role": "system", "content": MINIMAL_SYSTEM},
            {"role": "user", "content": seed["user_intents"][0]},
        ]
        if tool_names:
            calls = []
            for n, name in enumerate(tool_names[:3], 1):
                args: dict[str, Any] = {}
                if name == "capture_image":
                    args = {"reason": seed["task"]}
                elif name == "identify_object":
                    args = {"object": "door"}
                elif name == "search_contact":
                    args = {"query": "Anne"}
                elif name == "set_reminder":
                    args = {"text": "ilacımı al", "minutes": 10}
                elif name == "cancel_action":
                    args = {"target": "all"}
                elif name == "make_call":
                    args = {"name": "Anne", "phone": "+905551112233"}
                calls.append(
                    {
                        "id": f"call_{n}",
                        "type": "function",
                        "function": {
                            "name": name,
                            "arguments": json.dumps(args, ensure_ascii=False),
                        },
                    }
                )
            messages.append({"role": "assistant", "content": "", "tool_calls": calls})
            for call in calls:
                name = call["function"]["name"]
                messages.append(
                    {
                        "role": "tool",
                        "tool_call_id": call["id"],
                        "name": name,
                        "content": json.dumps(
                            {"summary": f"Synthetic {name} result."},
                            ensure_ascii=False,
                        ),
                    }
                )
        messages.append(
            {
                "role": "assistant",
                "content": "Şu an dikkatli ilerle. Verilere göre yakın çevrende kontrol etmen gereken bir durum var.",
            }
        )
        rows.append(
            {
                "id": f"dry_lumos_sft_{i:06d}",
                "source": "dry_run",
                "language": seed.get("language", "tr"),
                "task": seed.get("task", "unknown"),
                "risk": seed.get("risk", "low"),
                "messages": messages,
            }
        )
    return rows


def normalize_examples(rows: list[dict[str, Any]], prefix: str) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    timestamp = dt.datetime.utcnow().strftime("%Y%m%d%H%M%S")
    for i, row in enumerate(rows, 1):
        if not isinstance(row, dict):
            continue
        row.setdefault("id", f"{prefix}_{timestamp}_{i:06d}")
        row.setdefault("source", "openrouter_synthetic_v1")
        row.setdefault("language", "tr")
        row.setdefault("task", "unknown")
        row.setdefault("risk", "low")
        if isinstance(row.get("messages"), list):
            normalized.append(row)
    return normalized


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tools", type=Path, default=DEFAULT_TOOLS)
    parser.add_argument("--seeds", type=Path, default=DEFAULT_SEEDS)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--count", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=4)
    parser.add_argument("--model", default=os.getenv("OPENROUTER_MODEL", "google/gemma-4-26b-a4b-it:nitro"))
    parser.add_argument("--temperature", type=float, default=0.75)
    parser.add_argument("--max-tokens", type=int, default=5500)
    parser.add_argument("--response-format", choices=["none", "json_object"], default="json_object")
    parser.add_argument("--sleep", type=float, default=1.0)
    parser.add_argument("--append", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    random.seed(args.seed)
    tools = read_json(args.tools)
    seeds = read_jsonl(args.seeds)
    if not seeds:
        raise SystemExit("No seed scenarios found.")

    if args.dry_run:
        rows = dry_run_examples(seeds, args.count)
        write_jsonl(args.out, rows, append=args.append)
        print(f"Wrote {len(rows)} dry-run examples to {args.out}")
        return 0

    api_key = os.getenv("OPENROUTER_API_KEY")
    if not api_key:
        raise SystemExit("OPENROUTER_API_KEY is not set.")

    generated = 0
    first_write = not args.append
    while generated < args.count:
        batch_size = min(args.batch_size, args.count - generated)
        seed = random.choice(seeds)
        prompt = build_prompt(seed, tools, batch_size)
        print(f"Generating {batch_size} examples from {seed.get('id')} with {args.model}...")
        payload = call_openrouter(
            api_key=api_key,
            model=args.model,
            prompt=prompt,
            temperature=args.temperature,
            max_tokens=args.max_tokens,
            response_format=args.response_format,
        )
        examples = payload.get("examples")
        if not isinstance(examples, list):
            raise RuntimeError(f"Response missing examples list: {payload}")
        rows = normalize_examples(examples, prefix="lumos_sft")
        if not rows:
            raise RuntimeError(f"No valid examples in response: {payload}")
        write_jsonl(args.out, rows, append=not first_write)
        first_write = False
        generated += len(rows)
        print(f"Wrote {generated}/{args.count} examples to {args.out}")
        if generated < args.count:
            time.sleep(args.sleep)

    return 0


if __name__ == "__main__":
    sys.exit(main())

