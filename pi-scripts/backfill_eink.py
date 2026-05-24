#!/usr/bin/env python3
"""Re-process all queue items through the current e-ink pipeline.
Uses orig_filename as source when available, falls back to filename.
Replaces display_filename in-place.

Run on Pi:
    python3 /home/pi/PiInk/scripts/backfill_eink.py
"""
import os, sys, json, time, datetime
from PIL import Image, ImageEnhance, ImageFilter, ImageOps

PATH = "/home/pi/PiInk"
QUEUE_FILE = os.path.join(PATH, "config/queue.json")
UPLOAD_FOLDER = os.path.join(PATH, "img")

_SPECTRA6_COLORS = [
    (0, 0, 0),
    (255, 255, 255),
    (160, 32, 32),
    (240, 224, 80),
    (96, 128, 80),
    (80, 128, 184),
]

_SPECTRA6_SATURATED = [
    (0, 0, 0),
    (255, 255, 255),
    (255, 0, 0),
    (255, 255, 0),
    (0, 255, 0),
    (0, 0, 255),
]

def _build_palette(colors):
    flat = []
    for r, g, b in colors:
        flat.extend([r, g, b])
    flat += [0] * (768 - len(flat))
    p = Image.new('P', (1, 1))
    p.putpalette(flat)
    return p

_QUANTIZE_PAL = _build_palette(_SPECTRA6_SATURATED)
_OUTPUT_PAL = []
for r, g, b in _SPECTRA6_COLORS:
    _OUTPUT_PAL.extend([r, g, b])
_OUTPUT_PAL += [0] * (768 - len(_OUTPUT_PAL))

def process_for_eink(src_path, dst_path):
    img = Image.open(src_path).convert('RGB')
    img = ImageOps.autocontrast(img, cutoff=1)
    img = ImageEnhance.Contrast(img).enhance(1.2)
    img = ImageEnhance.Color(img).enhance(1.3)
    img = img.filter(ImageFilter.UnsharpMask(radius=0.8, percent=80, threshold=3))
    quantized = img.quantize(palette=_QUANTIZE_PAL, dither=Image.Dither.FLOYDSTEINBERG)
    quantized.putpalette(_OUTPUT_PAL)
    quantized.convert('RGB').save(dst_path, 'JPEG', quality=95)

def main():
    try:
        with open(QUEUE_FILE) as f:
            q = json.load(f)
    except Exception as e:
        print(f"Failed to load queue: {e}")
        sys.exit(1)

    items = q.get("items", [])
    total = len(items)
    if not total:
        print("Queue empty. Nothing to do.")
        return

    print(f"Queue: {total} items\n")

    done = 0
    skipped = 0
    failed = 0

    for i, item in enumerate(items):
        src = item.get("orig_filename") or item["filename"]
        src_path = os.path.join(UPLOAD_FOLDER, src)
        label = item.get("label") or item["filename"]

        if not os.path.isfile(src_path):
            print(f"[{i+1}/{total}] SKIP  {label!r} — source missing: {src}")
            skipped += 1
            continue

        ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_display_')
        dst = ts + item["filename"]
        dst_path = os.path.join(UPLOAD_FOLDER, dst)

        print(f"[{i+1}/{total}] Processing  {label!r} ...", end=' ', flush=True)
        t0 = time.time()
        try:
            process_for_eink(src_path, dst_path)
            elapsed = time.time() - t0

            old_disp = item.get("display_filename")
            if old_disp:
                old_path = os.path.join(UPLOAD_FOLDER, old_disp)
                if os.path.isfile(old_path):
                    os.remove(old_path)
            item["display_filename"] = dst
            done += 1
            print(f"done ({elapsed:.1f}s)")
        except Exception as e:
            elapsed = time.time() - t0
            failed += 1
            print(f"FAILED ({elapsed:.1f}s): {e}")

    if done > 0:
        with open(QUEUE_FILE, "w") as f:
            json.dump(q, f)

    print(f"\n{'─'*40}")
    print(f"Done: {done}  Skipped: {skipped}  Failed: {failed}")
    if done > 0:
        print("queue.json updated.")

if __name__ == "__main__":
    main()
