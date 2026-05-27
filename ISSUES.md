## [Onboarding] E-ink stays on QR screen after WiFi provisioning with empty queue

**Repro:**
1. Complete WiFi provisioning (hotspot → choose WiFi → Pi reconnects)
2. Queue is empty
3. Expected: e-ink clears QR screen and shows default/welcome state
4. Actual: e-ink stays on QR screen until background ping job finds internet and calls `/api/queue/show`, which does nothing on empty queue

**Root cause:** `toggle_hotspot.sh` switch-back calls `/api/queue/show` with `index: 0` unconditionally. Empty queue → index 0 invalid → 400 → display never changes.

**Fix:** `toggle_hotspot.sh` now checks queue length on switch-back. Empty queue → `render_screen default` (shows "Ready / Open Plink to upload your first photo"). Non-empty → `/api/queue/show` with current index as before. `draw_client_screen` removed; replaced by `draw_default_screen` in `show_hotspot_screen.py`.

**Status:** ✅ Fixed.

---



## [DefaultScreen] Design images for all Pi lifecycle states

UI/assets only — code wiring tracked in separate issues. Need designed images for:

1. **Unbox / powered-off** — brand/welcome image written to display during first install so the frame looks good out of the box.
2. **Boot, no WiFi configured** — "Hold A to begin setup" prompt screen. Shown on boot when no WiFi profiles exist.
3. **AP mode / WiFi setup** — QR code + credentials screen. Existing `draw_ap_screen()` functional but needs polish.
4. **Connected, empty queue** — ✅ done (`great_wave_retro.png` via `draw_default_screen()`).

**Root cause:** No designed images for states 1, 2. State 3 needs polish. State 4 done.

**Status:** 🔵 In progress — state 4 done. States 1, 2 need images; state 3 needs polish.

---

## [BootNoWiFi] Boot with no WiFi should show prompt screen, not auto-start AP mode

**Repro:**
1. Pi boots with no WiFi profiles configured (fresh install or reset)
2. Expected: e-ink shows "Hold A to begin setup" prompt screen; Pi waits for button press
3. Actual: `check_wifi_boot.sh` detects no profiles → immediately calls `toggle_hotspot.sh` → AP mode starts without user input

**Root cause:** `check_wifi_boot.sh` auto-started AP on no-WiFi condition instead of showing a prompt.

**Fix:** `check_wifi_boot.sh` no-profiles branch now calls `show_hotspot_screen.py setup` directly (webserver not yet up at boot-check time). `show_hotspot_screen.py` gains `draw_setup_screen()` — renders centered "Welcome to Plink / Hold Button A to begin setup" text. Falls back to `SETUP_SCREEN_PATH` (`/home/pi/PiInk/assets/setup_screen.png`) if that image exists. `plink-buttons` service handles long-press A → `toggle_hotspot.sh` → AP mode (unchanged).

**Status:** ✅ Fixed.

---

## [SoftwareUpdate] OTA update of Pi software (webserver, frontend) triggered from mobile app

**Repro:** Not described.

**Root cause:** Not investigated.

**Status:** ⚪ Not investigated.

---

## [Pi-PowerSaving] Reduce Pi power consumption: CPU governor, HDMI/USB, unused services, push vs polling

**Repro:** Not described. Research and implement power-saving measures:
- Set CPU governor to powersave/conservative for aggressive idle
- Permanently disable HDMI output
- Disable power to non-essential USB ports
- Disable unused system services (bluetooth, etc.)
- Replace polling (30s / 8s status interval) with push-based updates (WebSocket or SSE)

**Root cause:** Not investigated.

**Status:** ⚪ Not investigated.

---

## [ESP32-Controller] ESP32 as always-on controller, Pi only for rendering/image processing

**Repro:** Not described. Explore architecture where an ESP32 handles always-on tasks (WiFi connectivity, button inputs, queue management, AP mode) and wakes the Pi only when rendering/e-ink refresh is needed. Pi stays powered off or in deep sleep most of the time.

**Root cause:** Not investigated.

**Status:** ⚪ Not investigated.

---
