# Handoff

## Goal

iOS app upload flow polish: unified dark glass progress modal, no success toasts, correct state labels across all upload paths (new send, queue add, recrop).

## Current State

### iOS (Plink) — completed this session

- `TransferProgressModal` replaces `PreparingMediaView` as the upload overlay. Five states: `.preparing` → `.optimizing` / `.sending` → `.refreshing` → `.done`. Dark glass aesthetic, circular progress ring, spring entrance.
- Upload paths (`upload()`, `replaceQueueItem()`, `performAdd`) now batch `cancelPreparingMedia + setLoading` in single `MainActor.run` to prevent visual gap between preparing overlay clearing and progress modal appearing.
- Success toasts removed from `upload()` and `replaceQueueItem()` — `.done` modal state provides haptic + visual confirmation.
- Recrop/replace path shows "Updating display…" the whole time (not "Sending to frame…").
- Queue-add path shows "Adding to queue…" (not "Optimizing…").

### Server (pi-ink) — no changes this session

- `api_queue_add` and `api_queue_replace` accept optional `processed` multipart field; stored as `display_filename`.
- `process_for_eink()` runs server-side for non-iOS uploads (web share target).
- `_show_queue_item` prefers `display_filename` when `eink_enhance=on`.

## EinkProcessor (prior session, needs panel test)

Bayer 8×8 dithering replaces Floyd-Steinberg in `EinkProcessor.swift`:
- Two-palette system: saturated primaries for quantize bucket assignment, actual Spectra 6 colors for output
- Preprocessing: brightness +0.08, saturation ×1.4, contrast ×1.15, unsharp radius 1.5/0.9, Bayer threshold 12
- Warm golden-hour tones should dither red+yellow instead of collapsing to grey-brown
- **Not yet panel-tested** — needs rebuild + real-world display test

## Next Step

Build and deploy iOS app to device. Upload golden-hour warm-tone photo. Observe on panel at ~1m:
- Smooth surfaces (skin, background): less grainy/muddy than before
- Warm tones: red+yellow dithering instead of grey-brown
- If crosshatch still visible: lower `bayerThreshold` (try 8). If too posterized: raise (try 15).
