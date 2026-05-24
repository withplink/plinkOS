#!/usr/bin/env python3
"""Resize all queue image files (filename + orig_filename) to max 800x480 in-place.
Skips files already at or below target size.

Run on Pi:
    python3 /home/pi/PiInk/scripts/resize_images.py
"""
import os, sys, json
from PIL import Image

PATH = "/home/pi/PiInk"
QUEUE_FILE = os.path.join(PATH, "config/queue.json")
UPLOAD_FOLDER = os.path.join(PATH, "img")
MAX_SIZE = (800, 480)

def resize_file(filepath):
    img = Image.open(filepath)
    w, h = img.size
    if w <= MAX_SIZE[0] and h <= MAX_SIZE[1]:
        return False, w, h
    img.thumbnail(MAX_SIZE, Image.LANCZOS)
    img = img.convert('RGB')
    img.save(filepath, 'JPEG', quality=90)
    return True, w, h

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

    resized = 0
    skipped = 0
    failed = 0

    for i, item in enumerate(items):
        label = item.get("label") or item["filename"]
        fields = [("filename", item.get("filename")), ("orig_filename", item.get("orig_filename"))]

        for field, fname in fields:
            if not fname:
                continue
            fpath = os.path.join(UPLOAD_FOLDER, fname)
            if not os.path.isfile(fpath):
                print(f"[{i+1}/{total}] SKIP  {label!r} [{field}] — missing")
                skipped += 1
                continue
            try:
                did_resize, ow, oh = resize_file(fpath)
                if did_resize:
                    img = Image.open(fpath)
                    nw, nh = img.size
                    print(f"[{i+1}/{total}] RESIZED  {label!r} [{field}]  {ow}x{oh} → {nw}x{nh}")
                    resized += 1
                else:
                    print(f"[{i+1}/{total}] OK       {label!r} [{field}]  {ow}x{oh} (already small)")
                    skipped += 1
            except Exception as e:
                print(f"[{i+1}/{total}] FAILED  {label!r} [{field}]: {e}")
                failed += 1

    print(f"\n{'─'*40}")
    print(f"Resized: {resized}  Skipped/OK: {skipped}  Failed: {failed}")

if __name__ == "__main__":
    main()
