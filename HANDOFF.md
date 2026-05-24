# Handoff

## Goal

Implement fast, high-quality e-ink image processing for Spectra 6 — offload numpy Floyd-Steinberg dithering to iPhone (Swift), keeping Pi's numpy path as fallback for web share uploads.

## Current State

- **Numpy FS confirmed good quality**: tested on Pi at 800×480, 128s — warm tones preserved, clearly better than PIL
- **PIL path (current)**: fast (~0.1s) but washed out — fundamental flaw, saturated-primaries quantization maps warm/muted tones to wrong colors
- **Palette values correct**: our `_SPECTRA6_COLORS` already matches Pimoroni-measured values exactly — not the problem
- **resize_images.py done + deployed**: all 16 queue items resized from 1600×960 → 800×480 (30 files resized)
- **numpy test result saved**: `/Users/shoaibahmed/code/personal/pi-ink/compare/numpy.jpg` (Window Seat), `compare/friends_numpy.jpg` (Friends)
- **Friends numpy result**: copied to Pi at `/home/pi/PiInk/img/20260524_174307_display_photo.jpg` — NOT yet shown on frame (user blocked the show API call)
- **Decision made**: offload numpy FS to iPhone Swift before upload; Pi keeps async numpy as fallback for web share

## Files in Flight

- `Plink/Plink/` — Swift implementation of FS dithering needs to be added here
- `webserver_new.py` — needs async numpy fallback for web share / non-iOS uploads
- `pi-scripts/backfill_eink.py` — will need update once async Pi path is implemented

## Changed

- **`pi-scripts/resize_images.py`** (new): resizes all queue `filename` + `orig_filename` to max 800×480 in-place; deployed via push.sh; ran successfully (30 files resized)
- **`push.sh`**: added "Upload resize script" step
- **`compare/numpy.jpg`**: replaced with 719×431 Window Seat numpy result (correct quality reference)
- **`compare/friends_numpy.jpg`** (new): Friends image numpy result at 800×480

## Failed Attempts

- **PIL quantize with saturated primaries**: fast but washed out — euclidean RGB maps warm greys/browns to blue. Fundamental flaw, not fixable with preprocessing tweaks
- **myevit's approach**: same saturated-primaries trick, same fundamental flaw — their contrast 1.4 / EDGE_ENHANCE doesn't fix palette mismatch
- **LAB color space**: discussed but not tried yet — could improve numpy quality but doesn't solve the 128s speed problem

## Next Step

Implement Floyd-Steinberg dithering in Swift in the Plink iOS app. On upload: (1) apply preprocessing (autocontrast, contrast ×1.2, saturation ×1.3, unsharp mask), (2) run FS dithering against Spectra6 palette `[(0,0,0),(255,255,255),(160,32,32),(240,224,80),(96,128,80),(80,128,184)]` using euclidean RGB distance per pixel, (3) upload processed image to Pi as the display file. Pi server should accept a pre-processed flag or just store it directly as `display_filename`. Swift CPU path at 384k pixels should be <0.5s.
