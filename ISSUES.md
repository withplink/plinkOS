## [ButtonA] Button A hotspot toggle broken — ping drops, no QR screen, image refresh instead

**Repro:**
1. Press Button A (hold 1.5s) to toggle hotspot mode
2. Ping to 192.168.1.50 drops for a couple seconds then resumes — suggests NetworkManager is restarting or WiFi blips
3. Hotspot mode does NOT start
4. Frame does not show QR screen
5. Pressing A a second time refreshes display with currently selected image instead of toggling hotspot

**Root cause:** Not investigated. Likely `toggle_hotspot.sh` fails silently — hotspot doesn't come up but something (NetworkManager restart? partial script execution?) causes brief WiFi interruption and a display refresh side-effect.

**AP mode lifecycle spec (desired behavior):**
1. Button A press → Pi enters AP mode
2. AP stays up for **at least 30 seconds** regardless (grace window for user to connect)
3. If a client connects within those 30s → stay in AP mode until:
   - Button A pressed again, OR
   - No client connected for **30 seconds** (idle timeout)
4. On AP exit (either trigger) → connect to latest available known WiFi network

**Status:** Not investigated.

---

## [PiStability] Pi stops working and requires manual restart

**Repro:** Not described. Observed 2026-05-19 ~20:30 IST — both pi.local and static IP (192.168.1.50) unreachable. Manual restart restored access.

**Root cause:** Not investigated. Hardware watchdog (1min timeout) triggered reboot. Likely OOM during image processing or kernel freeze. Journal was not persistent at time of incident — no pre-reboot logs available. Persistent journal now enabled.

**Status:** Not investigated.

---

## [WiFi] Validate WiFi connection logic across all scenarios — no loopholes

**Repro:** Not described. Need to audit how the Pi connects to WiFi in different scenarios (initial setup, AP mode, client mode, network loss, Tailscale, etc.) and ensure there are no edge cases or loopholes.

**Root cause:** Not investigated.

**Status:** Not investigated.

---

## [Tailscale] Move Tailscale setup to mobile app instead of terminal

**Repro:** Terminal prompt in `setup-remote.sh` installs Tailscale and shows auth URL, but gives no visibility into the resulting device name (`pi`, `pi-1`, `pi-2`, etc. depending on prior registrations). User has no way to know which name to use for remote access without checking the Tailscale admin panel.

**Desired:** Move Tailscale setup into the PWA. Flow:
1. Install Tailscale on Pi silently during `setup-remote.sh` (no interactive prompt)
2. In the app's settings/network screen, show a "Connect to Tailscale" button
3. On tap: trigger `sudo tailscale up` on Pi, poll for auth URL, display it in-app as a tappable link
4. After auth, show assigned device name and Tailscale IP so user knows exactly which URL to use remotely

**Root cause:** Terminal-based flow has no feedback loop for device name resolution.

**Status:** Fixed.

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
