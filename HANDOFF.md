# Goal

Raspberry Pi e-ink frame server + PWA for Inky Impression 7.3". Must work over local network (`pi.local`) and Tailscale, including queue management and device actions.

This repo is **Pi/PWA only**.
- Pi/PWA repo: `PixeledCode/pi-ink`
- iOS app repo: `PixeledCode/plink-ios` (local path: `/Users/shoaibahmed/code/personal/Plink`)

---

## Current State

### PWA + backend (working)
- Upload photos, crop, show-now or add-to-queue
- Queue operations: list, remove, manual next, interval rotation
- Device actions: rotate image, clear ghosting, reboot, shutdown
- Status polling with offline detection (fast retry when offline)
- Contextual host hints between `pi.local` and Tailscale URL
- Service worker app-shell caching on HTTPS/Tailscale

Primary endpoints:
- `http://pi.local` (mDNS on local Wi‑Fi)
- `https://pi.tail4e929d.ts.net` (Tailscale)

---

## Files in flight

| Local | Deployed on Pi |
|---|---|
| `webserver_new.py` | `/home/pi/PiInk/src/webserver.py` |
| `main.html` | `/home/pi/PiInk/src/templates/main.html` |

Deploy:
```bash
./deploy.sh
```

---

## Connection flow

| Route | When | Notes |
|---|---|---|
| `http://pi.local` | Same WiFi network | mDNS via Avahi; most reliable on local network now |
| `http://192.168.1.50` | Same WiFi, direct IP | Fragile — DHCP can reassign; use as fallback only |
| `https://pi.tail4e929d.ts.net` | Any network | Most reliable overall; only route where SW caching activates |
| `http://192.168.4.1` | Phone on `plink-setup` AP | Hotspot mode only |

**Hotspot flow:** Hold Button A 1.5s → Pi tears down WiFi client, brings up `plink-setup` AP at `192.168.4.1` → e-ink shows QR with join info → phone connects → iOS app auto-discovers frame via Bonjour → Hold Button A again to return to WiFi client mode. Avahi restarts after each mode switch so it always advertises on the correct interface.

---

## Recent changes

- iOS code was removed from this repo so app development can happen in dedicated repo `PixeledCode/plink-ios`.
- Existing Pi/PWA flow remains the active source for device APIs and browser UI.
- Fixed `rotate` and `clear_ghost` actions in `/api/action` (and legacy `clearScreen()`/`rotateImage()`) using `os.listdir()[0]` (arbitrary filesystem order) instead of the current queue item — all now read `queue.json` and operate on `items[current]`.
- Replaced Python `zeroconf` library with an Avahi service file (`pi-scripts/plink.avahi.service` → `/etc/avahi/services/plink.service`). Root cause of `pi.local` randomly dying: both Avahi and the Python zeroconf library were binding UDP port 5353. Now only Avahi runs mDNS. Also fixes Bonjour always advertising `127.0.0.1` in AP/hotspot mode (Python used a route-to-8.8.8.8 trick that fails in AP mode; Avahi reads the correct interface IP automatically).
- Removed `_get_lan_ip`, `_LAN_IP`, `_start_bonjour`, the thread, and `socket` import from `webserver_new.py`. Also removed the leftover `lan_ip` field from `/api/status` response that was referencing the deleted variable.
- `toggle_hotspot.sh` now restarts `avahi-daemon` after each mode switch so Bonjour re-advertises on the newly active network interface.

---

## Planned: WiFi provisioning via hotspot

Not yet built. Goal: let a user provision the frame onto their home WiFi directly from the iOS app while connected via hotspot — so they don't have to trigger hotspot mode every time.

### New Pi endpoints needed

| Endpoint | Purpose |
|---|---|
| `GET /api/wifi/networks` | Returns `{known: ["SSID1"], visible: ["SSID2", ...]}`. `known` = SSIDs already in `wpa_supplicant.conf`. `visible` = Pi WiFi scan results. |
| `POST /api/wifi` | Body: `{ssid, password?}`. Password omitted if SSID is already known. Writes `wpa_supplicant.conf`, returns 200 immediately, then triggers hotspot→client switch after a 2s delay in a background thread. |

`/api/status` also needs an `ap_mode: bool` field (check for `/tmp/plink_ap_mode` flag file).

### iOS flow

1. After adding a frame, if `status.ap_mode == true`, auto-present a "Connect frame to WiFi" sheet (dismissible).
2. Same sheet always accessible from frame settings so users who dismiss it by accident can re-open it.
3. Sheet shows three tiers: **Known networks** (Pi has credentials — tap to connect, no password needed), **Nearby networks** (Pi scan results — tap then enter password), **Enter manually** (SSID + password text fields).
4. On submit: POST `/api/wifi`. Show "Switch your iPhone back to [home WiFi]" step with a deep-link to iOS Settings > WiFi.
5. App polls `pi.local` every 3s (up to ~60s). When it responds, update the existing `Frame` object's `baseURL` in SwiftData (replace in place — no duplicate entry, same frame name, just the URL changes from `192.168.4.1` to `pi.local`).

---

## Known limitations

- Service worker caching does not register on plain HTTP (`http://pi.local`); offline shell is effectively for HTTPS/Tailscale route.
- On iOS, after toggling Tailscale VPN off, `.local` DNS can lag for ~30–60s (OS-level behavior).
- Direct IP (`192.168.1.50`) breaks if DHCP reassigns — no fix planned, it's just a manual-entry fallback.

---

## Related repo

For native iOS status, features, and open issues, read:
- Local: `/Users/shoaibahmed/code/personal/Plink/HANDOFF.md`
- Remote: `git@github.com-pcode:PixeledCode/plink-ios.git`
