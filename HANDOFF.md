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

## Recent changes

- iOS code was removed from this repo so app development can happen in dedicated repo `PixeledCode/plink-ios`.
- Existing Pi/PWA flow remains the active source for device APIs and browser UI.
- Fixed `clearScreen()` and `rotateImage()` both used `os.listdir()[0]` (arbitrary filesystem order) instead of the current queue item — they now read `queue.json` and operate on the correct file.

---

## Known limitations

- Service worker caching does not register on plain HTTP (`http://pi.local`); offline shell is effectively for HTTPS/Tailscale route.
- On iOS, after toggling Tailscale VPN off, `.local` DNS can lag for ~30–60s (OS-level behavior).

---

## Related repo

For native iOS status, features, and open issues, read:
- Local: `/Users/shoaibahmed/code/personal/Plink/HANDOFF.md`
- Remote: `git@github.com-pcode:PixeledCode/plink-ios.git`
