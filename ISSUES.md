## [Onboarding] No way to use frame without setting up WiFi first

**Repro:**
1. Pi in hotspot mode, iPhone connected to plink-setup
2. Open Plink — "Find your frame" shows Pi IP
3. Tap IP → lands directly on Choose WiFi screen
4. No skip/later option — user cannot use frame (upload photos, view queue) without completing WiFi setup first

**Root cause:** Onboarding flow treats frame discovery as WiFi setup entry point with no bypass.

**Status:** Not investigated.

---

## [Onboarding] E-ink stays on QR screen after WiFi provisioning with empty queue

**Repro:**
1. Complete WiFi provisioning (hotspot → choose WiFi → Pi reconnects)
2. Queue is empty
3. Expected: e-ink clears QR screen and shows default/welcome state
4. Actual: e-ink stays on QR screen until background ping job finds internet and calls `/api/queue/show`, which does nothing on empty queue

**Root cause:** `toggle_hotspot.sh` switch-back calls `/api/queue/show` with `index: 0` unconditionally. Empty queue → index 0 invalid → 400 → display never changes.

**Fix:** Check queue length before calling `queue/show`. If empty, skip or show a "ready to use" clear screen instead.

**Status:** Not investigated.

---

## [Upload] No loading state after crop confirm — 3-4s blank before toast

**Repro:**
1. Tap + in Queue tab, pick photo
2. Crop view opens, tap confirm (checkmark)
3. Returns to queue page — loading overlay appears but only after 3-4s delay
4. Toast "sending to screen" appears

**Root cause:** Loading overlay exists but triggers too late — shown after upload starts, not immediately on crop confirm tap.

**Status:** In progress.

---


## [WiFi] Validate WiFi connection logic across all scenarios — no loopholes

**Repro:** Not described. Audit all WiFi scenarios end-to-end and verify no silent failures or gaps:
- **Initial setup** — Pi connects to home WiFi for first time via `plink.sh`
- **AP mode → client mode** — after user enters WiFi creds in hotspot UI, does it reliably switch back?
- **Network loss** — Pi loses WiFi mid-session, does it reconnect or hang?
- **Known network priority** — multiple saved networks, which wins?
- **Tailscale + WiFi** — does Tailscale survive a WiFi reconnect?
- **Static IP conflicts** — if `192.168.1.50` is taken, what happens?
- **wpa_supplicant vs nmcli** — both touch network config; any race conditions?

**Root cause:** Partially investigated.

**Status:** In progress.

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

## [WiFi] "Switch to X?" confirm dialog shows even when Pi already connected to that network

**Repro:**
1. Pi connected to Airtel_2A_2.4
2. Open Choose WiFi — Airtel_2A_2.4 shows "Connected"
3. Tap Airtel_2A_2.4 → confirm dialog says "Pi will disconnect from its current network and connect to Airtel_2A_2.4"

**Root cause:** Not investigated.

**Status:** Not investigated.

---

## [ESP32-Controller] ESP32 as always-on controller, Pi only for rendering/image processing

**Repro:** Not described. Explore architecture where an ESP32 handles always-on tasks (WiFi connectivity, button inputs, queue management, AP mode) and wakes the Pi only when rendering/e-ink refresh is needed. Pi stays powered off or in deep sleep most of the time.

**Root cause:** Not investigated.

**Status:** Not investigated.

---
