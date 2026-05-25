## [Onboarding] E-ink stays on QR screen after WiFi provisioning with empty queue

**Repro:**
1. Complete WiFi provisioning (hotspot → choose WiFi → Pi reconnects)
2. Queue is empty
3. Expected: e-ink clears QR screen and shows default/welcome state
4. Actual: e-ink stays on QR screen until background ping job finds internet and calls `/api/queue/show`, which does nothing on empty queue

**Root cause:** `toggle_hotspot.sh` switch-back calls `/api/queue/show` with `index: 0` unconditionally. Empty queue → index 0 invalid → 400 → display never changes.

**Fix:** `toggle_hotspot.sh` now checks queue length on switch-back. Empty queue → `render_screen default` (shows "Ready / Open Plink to upload your first photo"). Non-empty → `/api/queue/show` with current index as before. `draw_client_screen` removed; replaced by `draw_default_screen` in `show_hotspot_screen.py`.

**Status:** Fix implemented, pending test.

---



## [DefaultScreen] Better default screen when Pi is connected to WiFi with empty queue

**Repro:**
1. Pi connected to WiFi, queue is empty
2. E-ink shows a plain text "Ready / Open Plink to upload your first photo" placeholder

**Root cause:** No designed default screen exists. Current placeholder is minimal text via `draw_default_screen()` in `show_hotspot_screen.py`.

**Status:** Not investigated.

---

## [SoftwareUpdate] OTA update of Pi software (webserver, frontend) triggered from mobile app

**Repro:** Not described.

**Root cause:** Not investigated.

**Status:** Not investigated.

---

## [Pi-PowerSaving] Reduce Pi power consumption: CPU governor, HDMI/USB, unused services, push vs polling

**Repro:** Not described. Research and implement power-saving measures:
- Set CPU governor to powersave/conservative for aggressive idle
- Permanently disable HDMI output
- Disable power to non-essential USB ports
- Disable unused system services (bluetooth, etc.)
- Replace polling (30s / 8s status interval) with push-based updates (WebSocket or SSE)

**Root cause:** Not investigated.

**Status:** Not investigated.

---

## [ESP32-Controller] ESP32 as always-on controller, Pi only for rendering/image processing

**Repro:** Not described. Explore architecture where an ESP32 handles always-on tasks (WiFi connectivity, button inputs, queue management, AP mode) and wakes the Pi only when rendering/e-ink refresh is needed. Pi stays powered off or in deep sleep most of the time.

**Root cause:** Not investigated.

**Status:** Not investigated.

---
