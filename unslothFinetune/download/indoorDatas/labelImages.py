import os
import sys
import io
import re
import json
import base64
import traceback
import requests
import time
import asyncio
import aiohttp
import aiofiles
from pathlib import Path
from dotenv import load_dotenv
from typing import List, Dict, Optional
from PIL import Image

# ============================================================
# Configuration
# ============================================================
load_dotenv()

VLLM_BASEURL = os.getenv("VLLM_BASEURL").rstrip("/")
VLLM_API_KEY = os.getenv("VLLM_API_KEY")
VLLM_MODEL = os.getenv("VLLM_BASE_MODEL")

# Paths
DATA_DIR = Path(__file__).parent / "sampled_1150"
OUTPUT_DIR = Path(__file__).parent / "labeled_1150"
OUTPUT_DIR.mkdir(exist_ok=True)

# System prompt from markdown file
SYSTEM_PROMPT_PATH = Path(__file__).parent.parent.parent / "sysPrompts" / "TR.md" ## ENG.md for english
if SYSTEM_PROMPT_PATH.exists():
    SYSTEM_PROMPT = SYSTEM_PROMPT_PATH.read_text(encoding="utf-8").strip()
else:
    raise FileNotFoundError(f"System prompt not found: {SYSTEM_PROMPT_PATH}")

# VLM config
MAX_WORKERS = 3
MAX_CONCURRENT_API_CALLS = 1
API_TIMEOUT = 120  # seconds per request
IMG_MAX_DIM = 256  # tiny for API
IMG_MAX_SIZE = 5 * 1024 * 1024  # 5MB for API
IMG_QUALITY = 30  # aggressive compression for VLM


# ============================================================
# Image utils
# ============================================================
def encode_image_for_api(img_path: Path) -> Dict:
    """Resize image to fit API limits and return base64 data URL."""
    img = Image.open(img_path).convert("RGB")

    w, h = img.size
    if max(w, h) > IMG_MAX_DIM:
        ratio = IMG_MAX_DIM / max(w, h)
        img = img.resize((int(w * ratio), int(h * ratio)), Image.LANCZOS)

    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=IMG_QUALITY)
    b64 = base64.b64encode(buf.getvalue()).decode("utf-8")

    if len(b64) > 400000:
        img = img.resize((img.width // 3, img.height // 3), Image.LANCZOS)
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=20)
        b64 = base64.b64encode(buf.getvalue()).decode("utf-8")

    return {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}}


# ============================================================
# VLM API call
# ============================================================

# Test multimodal support with a tiny image
VLM_AVAILABLE = False
try:
    test_img = Image.new('RGB', (16, 16), (255, 0, 0))
    buf = io.BytesIO()
    test_img.save(buf, 'JPEG', quality=30)
    test_b64 = base64.b64encode(buf.getvalue()).decode()
    test_payload = {
        'model': VLLM_MODEL,
        'messages': [
            {
                'role': 'user',
                'content': [
                    {'type': 'text', 'text': 'one word'},
                    {'type': 'image_url', 'image_url': {'url': f'data:image/jpeg;base64,{test_b64}'}}
                ]
            }
        ],
        'max_tokens': 5
    }
    r = requests.post(
        f"{VLLM_BASEURL}/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {VLLM_API_KEY}",
            "Content-Type": "application/json",
        },
        json=test_payload,
        timeout=30
    )
    if r.status_code == 200 and r.json().get('choices'):
        VLM_AVAILABLE = True
        print(f"\n✓ VLLM multimodal is WORKING! response: {r.json()['choices'][0]['message']['content']}")
    else:
        print(f"\n✗ VLLM multimodal FAILED: status={r.status_code}")
        print(f"  {r.text[:500]}")
except Exception as e:
    print(f"\n✗ VLLM multimodal check raised: {e}")


def build_vlm_messages(img_data: Dict, class_name: str) -> List[Dict]:
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {
            "role": "user",
            "content": [
                {"type": "text", "text": f"Class: {class_name}\n\nAnalyze this image and return ONLY valid JSON as specified."},
                img_data
            ]
        }
    ]


# ============================================================
# Async VLM client
# ============================================================
async def call_vlm(
    session: aiohttp.ClientSession,
    img_data: Dict,
    img_path,
    class_name: str,
    timeout: int = API_TIMEOUT,
    _retries: int = 0,
) -> Optional[Dict]:
    """Call VLLM VLM API to label a single image."""
    messages = build_vlm_messages(img_data, class_name)

    payload = {
        "model": VLLM_MODEL,
        "messages": messages,
        "max_tokens": 2048,
        "temperature": 0.3,
    }

    headers = {
        "Authorization": f"Bearer {VLLM_API_KEY}",
        "Content-Type": "application/json",
    }

    try:
        async with session.post(
            f"{VLLM_BASEURL}/v1/chat/completions",
            headers=headers,
            json=payload,
            timeout=aiohttp.ClientTimeout(total=timeout)
        ) as resp:
            if resp.status == 200:
                data = await resp.json()
                raw = data["choices"][0]["message"]["content"].strip()
                raw = re.sub(r'<think>.*?</think>', '', raw, flags=re.DOTALL).strip()
                start = raw.find('{')
                end = raw.rfind('}')
                if start != -1 and end != -1:
                    raw = raw[start:end+1]
                return json.loads(raw)
            else:
                body = await resp.text()
                print(f"\nERROR: [HTTP {resp.status}] {body[:2000]}")
                print(f"Image path: {img_path}")
                print(f"b64 size: {len(img_data['image_url']['url'])} chars")
                print(f"Payload text len: {len(json.dumps(payload))}")
                MAX_RETRIES = 4
                if _retries >= MAX_RETRIES:
                    return None
                if resp.status == 429:
                    await asyncio.sleep(float(resp.headers.get("Retry-After", "5")))
                elif resp.status >= 500:
                    await asyncio.sleep(min(5 * 2 ** _retries, 60))
                else:
                    return None
                return await call_vlm(session, img_data, img_path, class_name, timeout, _retries + 1)
    except asyncio.TimeoutError:
        print(f"\nTIMEOUT for image: {img_path}")
        return None
    except Exception as e:
        print(f"\nEXCEPTION for image: {img_path} - {e}")
        traceback.print_exc()
        return None


# ============================================================
# Processing pipeline
# ============================================================
async def process_dataset(data_dir: Path, output_dir: Path) -> None:
    """Process all classes and images in the dataset."""
    class_dirs = sorted([d for d in data_dir.iterdir() if d.is_dir()])
    print(f"Found {len(class_dirs)} classes in {data_dir}")

    total_images = 0
    for cls_dir in class_dirs:
        total_images += len([f for f in cls_dir.iterdir() if f.suffix.lower() in ('.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif')])
    print(f"Total images to process: {total_images}")

    output_dir.mkdir(exist_ok=True)

    global_semaphore = asyncio.Semaphore(MAX_CONCURRENT_API_CALLS)
    completed_count = [0]

    all_img_tasks = []
    for cls_dir in class_dirs:
        img_files = sorted([
            f for f in cls_dir.iterdir()
            if f.suffix.lower() in ('.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif')
        ])
        if not img_files:
            continue
        for img_file in img_files:
            all_img_tasks.append((cls_dir.name, img_file))

    print(f"\nProcessing {len(all_img_tasks)} images with {MAX_CONCURRENT_API_CALLS} concurrent VLM calls...\n")

    all_labels = []
    failed_files = set()

    async with aiohttp.TCPConnector(limit=MAX_CONCURRENT_API_CALLS, ttl_dns_cache=300) as connector:
        async with aiohttp.ClientSession(connector=connector) as session:
            async def process_task(cls_name: str, img_path: Path):
                try:
                    async with global_semaphore:
                        img_data = encode_image_for_api(img_path)
                        # FIX: pass img_path so call_vlm can log it and retry correctly
                        raw_result = await call_vlm(session, img_data, img_path, cls_name)

                    if raw_result is not None:
                        label = {
                            "image_path": str(img_path.relative_to(Path(__file__).parent.parent)),
                            "class": cls_name,
                            **raw_result
                        }
                        all_labels.append(label)
                    else:
                        failed_files.add(img_path.name)

                    completed_count[0] += 1
                    if completed_count[0] % 10 == 0 or completed_count[0] == len(all_img_tasks):
                        elapsed = time.monotonic() - start_time
                        rate = completed_count[0] / elapsed if elapsed > 0 else 0
                        eta = (len(all_img_tasks) - completed_count[0]) / rate if rate > 0 else 0
                        bar_len = completed_count[0] / len(all_img_tasks) * 40
                        bar = '█' * int(bar_len) + '░' * (40 - int(bar_len))
                        pct = completed_count[0] / len(all_img_tasks) * 100
                        print(f"\r[█{bar}] {completed_count[0]}/{len(all_img_tasks)} ({pct:.1f}%) | {rate:.1f} img/s | ETA: {eta:.0f}s", end='', flush=True)
                except Exception as e:
                    failed_files.add(img_path.name)
                    completed_count[0] += 1

            start_time = time.monotonic()
            tasks = [process_task(cls_name, img_path) for cls_name, img_path in all_img_tasks]
            await asyncio.gather(*tasks)

    print(f"\n")

    class_label_map = {}
    for label in all_labels:
        cls = label["class"]
        if cls not in class_label_map:
            class_label_map[cls] = []
        class_label_map[cls].append(label)

    for cls_name, labels in class_label_map.items():
        cls_dir = DATA_DIR / cls_name
        img_files = sorted([
            f for f in cls_dir.iterdir()
            if f.suffix.lower() in ('.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif')
        ])
        print(f"\n[{cls_name}] {len(labels)}/{len(img_files)} labeled ({len(img_files)-len(labels)} failed)")
        class_json_path = output_dir / f"{cls_name}.json"
        await save_jsonl(class_json_path, labels)

    global_path = output_dir / "all_labels.jsonl"
    async with aiofiles.open(global_path, "w", encoding="utf-8") as f:
        for label in all_labels:
            await f.write(json.dumps(label, ensure_ascii=False) + "\n")

    if failed_files:
        failed_path = output_dir / "failed_images.txt"
        async with aiofiles.open(failed_path, "w") as f:
            for img in failed_files:
                await f.write(img + "\n")

    print(f"\n{'='*60}")
    print(f"Done! Processed {len(all_labels)} images total.")
    print(f"Failed: {len(failed_files)}")
    print(f"Output: {output_dir}")
    print(f"{'='*60}")


async def save_jsonl(path: Path, labels: List[Dict]) -> None:
    async with aiofiles.open(path, "w", encoding="utf-8") as f:
        for label in labels:
            await f.write(json.dumps(label, ensure_ascii=False) + "\n")


# ============================================================
# Main
# ============================================================
async def main():
    print(f"VLM Model: {VLLM_MODEL}")
    print(f"Data Dir:  {DATA_DIR.absolute()}")
    print(f"Output:    {OUTPUT_DIR.absolute()}")
    print(f"Concurrency: {MAX_CONCURRENT_API_CALLS} parallel API calls")
    print()

    await process_dataset(DATA_DIR, OUTPUT_DIR)


if __name__ == "__main__":
    asyncio.run(main())
