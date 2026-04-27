import os
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

# System prompt (scene description)
SYSTEM_PROMPT_PATH = Path(__file__).parent.parent.parent / "sysPrompts" / "TR.md"
if SYSTEM_PROMPT_PATH.exists():
    SYSTEM_PROMPT = SYSTEM_PROMPT_PATH.read_text(encoding="utf-8").strip()
else:
    raise FileNotFoundError(f"System prompt not found: {SYSTEM_PROMPT_PATH}")

# System prompt (haptic Q&A generation)
HAPTIC_SYSTEM_PROMPT = """Sen görme engelli bireyler için uzman bir rehber asistanısın.
Verilen sahne açıklamasına dayanarak, 5-8 soru-cevap çifti içeren gerçekçi bir çok turlu konuşma üret.

SORU TİPLERİ — Aşağıdaki tiplerden karıştırarak seç:

1. NESNEYE ULAŞMA (haptic)
   Soru: "X'e nasıl ulaşırım?" veya "X nerede?"
   Cevap: "Sana [referans]'a göre tarif edeyim:\\n[adım] → [adım] → [ne hissedeceksin].\\nYönleri karıştırırsan tekrar yaz; başka bir nesneye göre de tarif edebilirim."
   Not: Yalnızca elle ulaşılabilir nesneler için üret.

2. GÜVENLİK
   Soru: "Dikkat etmem gereken bir şey var mı?" / "Yolum açık mı?" / "Tehlike var mı?"
   Cevap (tehlike varsa): Nesneyi + konumunu belirt.
   Cevap (tehlike yoksa): "Önünüzdeki alan açık görünüyor, yine de bastonunuzu kullanın."

3. YÖNSELLİK
   Soru: "Sağımda ne var?" / "Solumda ne var?" / "Tam önümde ne var?"
   Cevap: O yöndeki nesneleri konum + materyal + işlev ile tarif et.

4. ZEMİN
   Soru: "Zemin nasıl?" / "Kaygan mı?" / "Zeminde engel var mı?"
   Cevap: Materyal, doku, kot değişimi veya ıslaklık bilgisi.

5. ÜST ENGEL
   Soru: "Başım bir şeye çarpar mı?" / "Üstte engel var mı?"
   Cevap (engel varsa): Nesneyi + hizasını belirt.
   Cevap (yoksa): "Baş hizasında belirgin bir engel yok."

6. ROTA (sahneye uygunsa)
   Soru: "Çıkışa nasıl giderim?" / "Kapıya nasıl ulaşırım?"
   Cevap: Referans noktalara dayalı adım adım rota.

7. İHTİYAÇ
   Soru: "Oturabilecek yer var mı?" / "Kaç kişi var?" / "Yardım isteyebileceğim biri var mı?"
   Cevap (varsa): Konumu belirt. Cevap (yoksa): "Şu an [X] görünmüyor."

8. TAKİP SORUSU (en az 1-2 tane ekle)
   Önceki bir cevaba atıfta bulunan soru. Örnekler:
   - "Az önce bahsettiğin bankoya sağ taraftan da ulaşabilir miyim?"
   - "Daha iyi anlayamadım, farklı bir nesneye göre tarif eder misin?"
   - "Peki o sandalyenin yanında ne var?"
   - "Tehlikeli dedin, nasıl geçebilirim?"
   Cevap: Önceki cevabı tamamlar veya farklı açıdan açıklar.

GENEL KURALLAR:
- MUTLAKA 6-8 soru-cevap çifti üret — daha az üretme
- Konuşma doğal bir akış izlesin: genel soru → detay → takip → farklı konu → takip
- Cevaplar yalnızca sahne açıklamasındaki bilgilere dayansın
- Boş/yok cevapları gerçekçi yaz: "görünmüyor", "tespit edilemiyor"
- Yabancıların kişisel eşyalarına (başkasının çantası, cüzdanı vb.) ulaşma sorusu üretme

GENİŞ/AÇIK SAHNELER İÇİN (terminal, meydan, koridor):
Ulaşılabilir nesne az olsa bile şu tipleri kullan:
- "İnsanlara nasıl yaklaşırım?" / "Yardım isteyebileceğim biri var mı?"
- "Bu alanda nasıl yön bulabilirim?"
- "Koridor boyunca ilerlerken neyi rehber alabilirim?"
- "En yakın duvara nasıl ulaşırım?"
- "Ayaklarımın altındaki zemin değişiyor mu ilerledikçe?"
- Birden fazla yönsellik sorusu (sağ, sol, arka) üret

YASAK KELİMELER (cevaplarda asla kullanma):
- "göreceksiniz", "görebilirsiniz", "görürsünüz" → "hissedeceksiniz", "elinize değecek", "bulacaksınız"
- "bakın", "bakarsanız" → fiziksel yönlendirme kullan

Yalnızca geçerli JSON döndür:
[
  {"question": "...", "answer": "..."}
]"""

# VLM config
MAX_CONCURRENT_API_CALLS = 2
API_TIMEOUT = 240
IMG_MAX_DIM = 256
IMG_QUALITY = 30
IMG_EXTS = ('.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif')


# ============================================================
# Image utils
# ============================================================
def encode_image_for_api(img_path: Path) -> Dict:
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


def copy_image_as_jpeg(src: Path, dst: Path) -> None:
    Image.open(src).convert("RGB").save(dst, format="JPEG", quality=95)


# ============================================================
# VLM API helpers
# ============================================================
def _parse_json_from_raw(raw: str):
    raw = re.sub(r'<think>.*?</think>', '', raw, flags=re.DOTALL).strip()
    start = raw.find('{') if '{' in raw else raw.find('[')
    end   = raw.rfind('}') if '}' in raw else raw.rfind(']')
    if '{' in raw and '[' in raw:
        start = min(raw.find('{'), raw.find('['))
        end   = max(raw.rfind('}'), raw.rfind(']'))
    if start != -1 and end != -1:
        try:
            return json.loads(raw[start:end + 1])
        except json.JSONDecodeError:
            pass
    return None


def build_description_messages(img_data: Dict, class_name: str) -> List[Dict]:
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {
            "role": "user",
            "content": [
                {
                    "type": "text",
                    "text": (
                        f"Ortam türü: {class_name}\n\n"
                        "Tek cümle sahne özeti ile başla. Sonra ön plandan arka plana nesne envanteri yap: "
                        "her nesne için konum + materyal/renk + işlev belirt. "
                        "'Bu görselde görülüyor' / 'Resimde görülüyor' kullanma. "
                        "Kesin adım sayısı verme.\n"
                        'Yalnızca şu formatta geçerli JSON döndür: {"description": "tarifin buraya"}'
                    )
                },
                img_data
            ]
        }
    ]


def build_haptic_messages(description: str, class_name: str) -> List[Dict]:
    return [
        {"role": "system", "content": HAPTIC_SYSTEM_PROMPT},
        {
            "role": "user",
            "content": (
                f"Ortam türü: {class_name}\n\n"
                f"Sahne açıklaması:\n{description}\n\n"
                "Bu sahnedeki elle ulaşılabilir nesneler için 1-2 soru-cevap çifti üret. "
                "Geçerli JSON döndür."
            )
        }
    ]


async def _call_api(
    session: aiohttp.ClientSession,
    messages: List[Dict],
    label: str,
    max_tokens: int = 1024,
    temperature: float = 0.4,
    timeout: int = API_TIMEOUT,
    _retries: int = 0,
) -> Optional[str]:
    payload = {
        "model": VLLM_MODEL,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
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
                return re.sub(r'<think>.*?</think>', '', raw, flags=re.DOTALL).strip()
            else:
                body = await resp.text()
                print(f"\nERROR [{label}] HTTP {resp.status}: {body[:500]}")
                MAX_RETRIES = 3
                if _retries >= MAX_RETRIES:
                    return None
                if resp.status == 429:
                    await asyncio.sleep(float(resp.headers.get("Retry-After", "5")))
                elif resp.status >= 500:
                    await asyncio.sleep(min(5 * 2 ** _retries, 60))
                else:
                    return None
                return await _call_api(session, messages, label, max_tokens, temperature, timeout, _retries + 1)
    except asyncio.TimeoutError:
        print(f"\nTIMEOUT [{label}]")
        return None
    except Exception as e:
        print(f"\nEXCEPTION [{label}]: {e}")
        traceback.print_exc()
        return None


async def call_description(session, img_data, img_path, class_name) -> Optional[str]:
    messages = build_description_messages(img_data, class_name)
    raw = await _call_api(session, messages, f"desc:{img_path.name}", max_tokens=2048, temperature=0.3)
    if not raw:
        return None
    parsed = _parse_json_from_raw(raw)
    if isinstance(parsed, dict):
        return parsed.get("description", raw)
    return raw


async def call_haptic_qa(session, description: str, class_name: str) -> List[Dict]:
    messages = build_haptic_messages(description, class_name)
    raw = await _call_api(session, messages, f"haptic:{class_name}", max_tokens=2048, temperature=0.5)
    if not raw:
        return []
    parsed = _parse_json_from_raw(raw)
    if isinstance(parsed, list):
        return [qa for qa in parsed if isinstance(qa, dict) and "question" in qa and "answer" in qa]
    return []


# ============================================================
# Build Unsloth conversation entry
# ============================================================
def build_conversation(img_name: str, description: str, haptic_qa: List[Dict]) -> Dict:
    """
    Unsloth multi-turn vision format:
    - system: TR.md system prompt (model learns to follow rules)
    - First user turn: image + opening question
    - First assistant turn: scene description
    - Subsequent turns: diverse Q&A + follow-ups (text only)
    """
    conversations = [
        {
            "role": "system",
            "content": SYSTEM_PROMPT
        },
        {
            "role": "user",
            "content": [
                {"type": "image"},
                {"type": "text", "text": "Ne var önümde?"}
            ]
        },
        {
            "role": "assistant",
            "content": description
        }
    ]

    for qa in haptic_qa:
        conversations.append({"role": "user",      "content": qa["question"]})
        conversations.append({"role": "assistant", "content": qa["answer"]})

    return {"image": img_name, "conversations": conversations}


# ============================================================
# Processing pipeline
# ============================================================
async def process_dataset(data_dir: Path, output_dir: Path) -> None:
    images_dir        = output_dir / "images"
    progress_dir      = output_dir / "_progress"
    conversations_path = output_dir / "conversations.json"   # Unsloth training format
    data_json_path    = output_dir / "data.json"             # legacy flat format
    failed_path       = output_dir / "failed_images.txt"

    images_dir.mkdir(exist_ok=True)
    progress_dir.mkdir(exist_ok=True)

    class_dirs = sorted([d for d in data_dir.iterdir() if d.is_dir()])
    print(f"Found {len(class_dirs)} classes in {data_dir}")

    total_images = sum(
        len([f for f in d.iterdir() if f.suffix.lower() in IMG_EXTS])
        for d in class_dirs
    )
    print(f"Total images: {total_images}")

    existing_imgs = sorted(images_dir.glob("img_*.jpg"))
    counter = [len(existing_imgs)]

    all_conversations: List[Dict] = []
    all_flat: List[Dict] = []

    if conversations_path.exists():
        try:
            all_conversations = json.loads(conversations_path.read_text(encoding="utf-8"))
            print(f"Resuming — {len(all_conversations)} conversations loaded")
        except json.JSONDecodeError:
            pass

    if data_json_path.exists():
        try:
            all_flat = json.loads(data_json_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            pass

    global_semaphore = asyncio.Semaphore(MAX_CONCURRENT_API_CALLS)
    global_failed: set = set()
    global_completed = [counter[0]]
    start_time = time.monotonic()

    async with aiohttp.TCPConnector(limit=MAX_CONCURRENT_API_CALLS, ttl_dns_cache=300) as connector:
        async with aiohttp.ClientSession(connector=connector) as session:

            for cls_dir in class_dirs:
                cls_name    = cls_dir.name
                done_marker = progress_dir / f"{cls_name}.done"

                img_files = sorted([f for f in cls_dir.iterdir() if f.suffix.lower() in IMG_EXTS])
                if not img_files:
                    continue

                if done_marker.exists():
                    print(f"[SKIP] {cls_name}")
                    global_completed[0] += len(img_files)
                    continue

                print(f"\n[START] {cls_name} — {len(img_files)} images")

                cls_conversations: List[Dict] = []
                cls_flat: List[Dict] = []
                cls_failed: set = set()
                cls_completed = [0]

                async def process_task(
                    img_path: Path,
                    _cls=cls_name,
                    _cls_conv=cls_conversations,
                    _cls_flat=cls_flat,
                    _cls_failed=cls_failed,
                    _cls_completed=cls_completed,
                ):
                    try:
                        async with global_semaphore:
                            img_data    = encode_image_for_api(img_path)
                            description = await call_description(session, img_data, img_path, _cls)

                        if description:
                            # Haptic Q&A (text-only, no image needed)
                            haptic_qa = await call_haptic_qa(session, description, _cls)

                            n = counter[0]
                            counter[0] += 1
                            img_name = f"img_{n + 1:04d}.jpg"
                            copy_image_as_jpeg(img_path, images_dir / img_name)

                            _cls_conv.append(build_conversation(img_name, description, haptic_qa))
                            _cls_flat.append({"image": img_name, "description": description})
                        else:
                            _cls_failed.add(img_path.name)

                        _cls_completed[0] += 1
                        global_completed[0] += 1
                        if _cls_completed[0] % 5 == 0 or _cls_completed[0] == len(img_files):
                            elapsed  = time.monotonic() - start_time
                            rate     = global_completed[0] / elapsed if elapsed > 0 else 0
                            eta      = (total_images - global_completed[0]) / rate if rate > 0 else 0
                            bar_len  = global_completed[0] / total_images * 40
                            bar      = '█' * int(bar_len) + '░' * (40 - int(bar_len))
                            pct      = global_completed[0] / total_images * 100
                            print(
                                f"\r[{bar}] {global_completed[0]}/{total_images} ({pct:.1f}%) "
                                f"| {_cls}: {_cls_completed[0]}/{len(img_files)} "
                                f"| {rate:.1f} img/s | ETA: {eta:.0f}s",
                                end='', flush=True
                            )
                    except Exception:
                        _cls_failed.add(img_path.name)
                        _cls_completed[0] += 1
                        global_completed[0] += 1

                tasks = [process_task(img_path) for img_path in img_files]
                await asyncio.gather(*tasks)

                all_conversations.extend(cls_conversations)
                all_flat.extend(cls_flat)

                async with aiofiles.open(conversations_path, "w", encoding="utf-8") as f:
                    await f.write(json.dumps(all_conversations, ensure_ascii=False, indent=2))
                async with aiofiles.open(data_json_path, "w", encoding="utf-8") as f:
                    await f.write(json.dumps(all_flat, ensure_ascii=False, indent=2))

                done_marker.write_text("done")
                print(
                    f"\n[SAVED] {cls_name} — {len(cls_conversations)}/{len(img_files)} labeled, "
                    f"{len(cls_failed)} failed | total: {len(all_conversations)}"
                )

                if cls_failed:
                    async with aiofiles.open(failed_path, "a") as f:
                        for img in cls_failed:
                            await f.write(img + "\n")

                global_failed.update(cls_failed)

    print(f"\n{'='*60}")
    print(f"Done! {len(all_conversations)} conversations")
    print(f"conversations.json → {conversations_path}")
    print(f"data.json          → {data_json_path}")
    print(f"images/            → {images_dir}")
    print(f"{'='*60}")


# ============================================================
# Main
# ============================================================
async def main():
    # Test multimodal
    try:
        test_img = Image.new('RGB', (16, 16), (255, 0, 0))
        buf = io.BytesIO()
        test_img.save(buf, 'JPEG', quality=30)
        test_b64 = base64.b64encode(buf.getvalue()).decode()
        r = requests.post(
            f"{VLLM_BASEURL}/v1/chat/completions",
            headers={"Authorization": f"Bearer {VLLM_API_KEY}", "Content-Type": "application/json"},
            json={"model": VLLM_MODEL, "messages": [{"role": "user", "content": [
                {"type": "text", "text": "one word"},
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{test_b64}"}}
            ]}], "max_tokens": 5},
            timeout=30
        )
        if r.status_code == 200 and r.json().get("choices"):
            print(f"✓ VLLM multimodal OK: {r.json()['choices'][0]['message']['content']}")
        else:
            print(f"✗ VLLM multimodal FAILED: {r.status_code}")
    except Exception as e:
        print(f"✗ VLLM check error: {e}")

    print(f"\nVLM Model : {VLLM_MODEL}")
    print(f"Data Dir  : {DATA_DIR.absolute()}")
    print(f"Output    : {OUTPUT_DIR.absolute()}")
    print(f"Concurrency: {MAX_CONCURRENT_API_CALLS} parallel API calls\n")

    await process_dataset(DATA_DIR, OUTPUT_DIR)


if __name__ == "__main__":
    asyncio.run(main())
