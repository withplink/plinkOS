## [Onboarding] E-ink stays on QR screen after WiFi provisioning with empty queue

**Repro:**
1. Complete WiFi provisioning (hotspot → choose WiFi → Pi reconnects)
2. Queue is empty
3. Expected: e-ink clears QR screen and shows default/welcome state
4. Actual: e-ink stays on QR screen until background ping job finds internet and calls `/api/queue/show`, which does nothing on empty queue

**Root cause:** `toggle_hotspot.sh` switch-back calls `/api/queue/show` with `index: 0` unconditionally. Empty queue → index 0 invalid → 400 → display never changes.

**Fix:** `toggle_hotspot.sh` now checks queue length on switch-back. Empty queue → `render_screen default` (shows "Ready / Open Plink to upload your first photo"). Non-empty → `/api/queue/show` with current index as before. `draw_client_screen` removed; replaced by `draw_default_screen` in `show_hotspot_screen.py`.

**Status:** 🟡 Fix implemented, pending test.

---



## [DefaultScreen] Full set of e-ink state screens

4 screens needed across the Pi lifecycle:

1. **Unbox / powered-off** — e-ink retains last image when Pi is off; needs a welcome/brand image written to display during first install so the frame looks good out of the box.
2. **Boot, no WiFi configured** — Pi booted, no queue, no WiFi; prompts user to onboard ("Hold A to begin setup").
3. **AP mode / WiFi setup** — shown after long-press A; displays QR code + credentials so user can connect phone and enter WiFi. Existing `draw_ap_screen()` covers this.
4. **Connected, empty queue** — Pi on WiFi, no photos yet; `draw_default_screen()` now loads `great_wave_retro.png` (✅ done).

**Notes:**
- State 2: install already writes a default image to e-ink (`default_screen.png`). Image is generic — doesn't tell user to press A. Need new onboarding image + code path on boot that detects no-WiFi and renders it. AP screen still shows after long-press A as before.

**Root cause:** No designed images for states 1, 2. State 3 functional but unpolished. State 4 done.

**Status:** 🔵 In progress — state 4 done (great_wave_retro). States 1, 2 need images; state 3 needs polish.

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
