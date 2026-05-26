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

## Next Steps

- Generate images for screens 1 and 2 (see `[DefaultScreen]` issue for specs)
- Implement `[BootNoWiFi]` — detect no-WiFi state on boot and call `render_screen default` or a new prompt screen
