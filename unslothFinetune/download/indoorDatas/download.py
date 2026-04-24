import os
import random
import shutil
from pathlib import Path

# ============ CONFIGURE YOUR KEYS HERE ============
KAGGLE_USERNAME = "salihdede"
KAGGLE_API_KEY = "KGAT_8109465957955fc45ebaed1278969bf6"
# ==================================================

KAGGLE_DATASET = "itsahmad/indoor-scenes-cvpr-2019"
BASE_DIR = Path("unslothFinetune/download/indoorDatas")
IMAGES_DIR = BASE_DIR / "unslothFinetune" / "download" / "indoorDatas" / "indoorCVPR_09" / "Images"
IMG_COUNT_PER_DIR = 150
OUTPUT_DIR = BASE_DIR / "sampled_1150"
image_extensions = {".jpg", ".jpeg", ".png", ".bmp", ".gif", ".tiff", ".webp"}


def setup_kaggle():
    """Configure Kaggle API credentials locally."""
    kaggle_dir = Path.home() / ".kaggle"
    kaggle_dir.mkdir(exist_ok=True)

    kaggle_file = kaggle_dir / "kaggle.json"
    credentials = {
        "username": KAGGLE_USERNAME,
        "key": KAGGLE_API_KEY,
    }

    # Write credentials file
    import json
    with open(kaggle_file, "w") as f:
        json.dump(credentials, f)

    # Set permissions (Linux/Mac requires 600)
    try:
        os.chmod(kaggle_file, 0o600)
    except OSError:
        pass

    print(f"Kaggle credentials saved to {kaggle_file}")


def download_dataset():
    """Download the dataset via Kaggle API directly (no CLI needed)."""
    import urllib.request
    import zipfile

    BASE_DIR.mkdir(parents=True, exist_ok=True)

    # Prepare the API URL for dataset download
    api_url = f"https://www.kaggle.com/api/v1/datasets/download/{KAGGLE_DATASET}"

    print(f"Downloading dataset: {KAGGLE_DATASET}")

    # Create config.json for the download request headers
    kaggle_cfg = Path.home() / ".kaggle" / "kaggle.json"
    if not kaggle_cfg.exists():
        setup_kaggle()

    import json
    with open(kaggle_cfg) as f:
        creds = json.load(f)

    # Use urllib with authentication header
    req = urllib.request.Request(api_url)
    auth = f"Basic {creds['username']}:{creds['key']}"
    req.add_header("Authorization", auth)

    zip_path = BASE_DIR / "unslothFinetune" / "download" / "indoorDatas" / "dataset.zip"
    zip_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        with urllib.request.urlopen(req) as response:
            total = response.getheader("Content-Length", 0)
            total = int(total) if total else 0
            downloaded = 0
            chunk_size = 8192
            with open(zip_path, "wb") as out_file:
                while True:
                    chunk = response.read(chunk_size)
                    if not chunk:
                        break
                    out_file.write(chunk)
                    downloaded += len(chunk)
                    if total:
                        pct = downloaded / total * 100
                        print(f"\n  Progress: {pct:.1f}% ({downloaded}/{total} bytes)", end="")
        print()
    except Exception as e:
        print(f"ERROR downloading: {e}")
        raise

    # Extract zip to the nested location
    extract_target = BASE_DIR / "unslothFinetune" / "download" / "indoorDatas"
    print("Extracting zip file...")
    try:
        with zipfile.ZipFile(zip_path) as z:
            z.extractall(extract_target)
        print("Extraction complete.")
    finally:
        if zip_path.exists():
            zip_path.unlink()
            print("Removed temporary zip file.")


def sample_images():
    """Sample IMG_COUNT_PER_DIR images from each subdirectory of Images/."""
    if not IMAGES_DIR.exists():
        print(f"ERROR: Images directory not found: {IMAGES_DIR.resolve()}")
        print("Run download_dataset() first or place the extracted dataset here.")
        exit(1)

    # Get all immediate subdirectories of Images/
    category_dirs = [d for d in IMAGES_DIR.iterdir() if d.is_dir()]
    if not category_dirs:
        print(f"ERROR: No subdirectories found in {IMAGES_DIR.resolve()}")
        exit(1)

    sampled_total = 0
    print(f"\nFound {len(category_dirs)} categories in {IMAGES_DIR.name}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    for category_dir in sorted(category_dirs):
        category_name = category_dir.name

        # Find all image files recursively in this subdirectory
        image_files = [
            f for f in category_dir.rglob("*")
            if f.is_file() and f.suffix.lower() in image_extensions
        ]

        if not image_files:
            print(f"  [{category_name}] No images found — skipped.")
            continue

        print(f"[{category_name}] ({len(image_files)} images) → sampling {IMG_COUNT_PER_DIR}")

        # Select random sample
        sample_size = min(IMG_COUNT_PER_DIR, len(image_files))
        sampled = random.sample(image_files, sample_size)

        # Create output directory for this category
        final_dir = OUTPUT_DIR / category_name
        final_dir.mkdir(parents=True, exist_ok=True)

        # Copy images with incremental names: image1.jpg, image2.jpg, ...
        for i, img_path in enumerate(sorted(sampled), start=1):
            dest = final_dir / f"image{i}{img_path.suffix}"
            shutil.copy2(img_path, dest)

        sampled_total += sample_size
        print(f"  ✓ Copied {sample_size} images → {final_dir}")

    print(f"\n{'='*50}")
    print(f"Done! Total sampled: {sampled_total} images across {len(category_dirs)} categories")
    print(f"Output location: {OUTPUT_DIR.resolve()}")
    print(f"{'='*50}")


if __name__ == "__main__":
    # Step 1: Setup Kaggle credentials
    if KAGGLE_USERNAME == "your_kaggle_username" or KAGGLE_API_KEY == "your_kaggle_api_key":
        print("ERROR: Please fill in KAGGLE_USERNAME and KAGGLE_API_KEY at the top of this file.")
        exit(1)

    setup_kaggle()
    download_dataset()
    sample_images()
