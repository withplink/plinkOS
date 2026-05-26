# Handoff

## Goal

E-ink state screens — design and wire up images for all Pi lifecycle states.

## Current State

### pi-ink — this session

- `draw_default_screen()` in `show_hotspot_screen.py` now loads `/home/pi/PiInk/assets/default_screen.png` (resized to 800×480 via LANCZOS); falls back to text placeholder if file missing.
- `great_wave_retro.png` copied to `pi-scripts/assets/default_screen.png` and deployed to Pi at `/home/pi/PiInk/assets/default_screen.png`.
- `push.sh` now includes two steps: create `/home/pi/PiInk/assets/` dir on Pi, upload `default_screen.png`.
- ISSUES.md `[DefaultScreen]` updated to track all 4 screens. `[BootNoWiFi]` issue added.

### 4 e-ink lifecycle screens

| # | State | Status |
|---|-------|--------|
| 1 | Unbox / Pi powered off | Image needed |
| 2 | Boot, no WiFi configured | Image + code needed (`[BootNoWiFi]`) |
| 3 | AP mode / WiFi setup (after long-press A) | Existing `draw_ap_screen()` — needs polish |
| 4 | Connected, empty queue | ✅ great_wave_retro deployed |

## EinkProcessor (prior session, needs panel test)

Bayer 8×8 dithering replaces Floyd-Steinberg in `EinkProcessor.swift`:
- Two-palette system: saturated primaries for quantize bucket assignment, actual Spectra 6 colors for output
- Preprocessing: brightness +0.08, saturation ×1.4, contrast ×1.15, unsharp radius 1.5/0.9, Bayer threshold 12
- Warm golden-hour tones should dither red+yellow instead of collapsing to grey-brown
- **Not yet panel-tested** — needs rebuild + real-world display test

## Next Steps

- Generate images for screens 1 and 2 (see `[DefaultScreen]` issue for specs)
- Implement `[BootNoWiFi]` — detect no-WiFi state on boot and call `render_screen default` or a new prompt screen
- Panel-test EinkProcessor Bayer dithering (upload warm-tone photo, observe at ~1m)
