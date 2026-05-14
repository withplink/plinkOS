# Goal

Mobile-first PWA companion for a Raspberry Pi Zero 2W driving an Inky Impression 7.3" e-ink display. Send photos from your phone, manage a queue, and have the app load even when the Pi is off (cached shell via service worker).

---

## Current State

App is fully working and deployed. Key capabilities:
- Upload photos → crop → show now or add to queue
- Queue management: reorder, remove, auto-rotate on interval, manual next
- Device controls: rotate image, clear ghosting, reboot, shutdown
- Service worker `plink-v1` caches app shell at install time → app loads offline
- Status dot auto-detects online/offline every 30s (online) / 8s (offline) — no manual refresh needed
- **Contextual URL hints:** on Tailscale URL + offline → `offline · pi.local ↗`. On `pi.local` + Tailscale reachable → `switch to tailscale ↗` below dot.

Pi is accessible two ways:
- `http://pi.local` — local WiFi, mDNS
- `https://pi.tail4e929d.ts.net` — Tailscale VPN (Tailscale must be on)

Tailscale auto-starts on boot (`tailscaled` is enabled), but takes ~90s after power-on.

---

## Files in flight

| Local | Deployed to |
|---|---|
| `webserver_new.py` | `/home/pi/PiInk/src/webserver.py` |
| `main.html` | `/home/pi/PiInk/src/templates/main.html` |

Deploy:
```bash
./deploy.sh
```

---

## Recent changes (newest first)

**`2c2f053` — Rename to Plink, add deploy script, fix offline detection**
- App renamed from Piink → Plink everywhere (title, manifest, SW cache name, UI labels, hero copy)
- `AbortSignal.timeout(5000)` added to `/api/status` fetch — mobile detects offline within ~5s instead of hanging indefinitely
- Polling made continuous: 30s when online, 8s when offline — status dot flips automatically when Tailscale drops, no manual refresh required
- SW cache bumped `piink-v7` → `plink-v1` to force fresh re-cache of new shell
- `deploy.sh` added to root for one-command deploy from Mac

**`dd05a2c` — Replace cross-origin fallback with contextual URL hints**
Reverted the `apiBase`/`api`/`imgSrc` abstraction. All fetches are plain relative `fetch('/api/...')`. Instead of auto-probing across origins (blocked by mixed content), the status indicator shows a helpful link when offline.

**`0ffe588` — SW v5: move shell caching from activate → install**
Root fix for iOS offline caching. iOS Safari can kill the SW during `activate`. Moving caching to `install` and calling `skipWaiting()` only after caching completes fixed this.

---

## Known limitations

**`pi.local` slow to resolve after Tailscale VPN is turned off on iOS**
Tailscale intercepts DNS on iOS. After toggling VPN off, mDNS `.local` resolution and even direct IPs are broken for 30–60s while iOS tears down the VPN tunnel. Not fixable in app code. Potential future fix: include Pi's LAN IP in `/api/status` response, persist in `localStorage`, use IP link instead of `pi.local` (bypasses mDNS entirely).

**SW only works on HTTPS**
`http://pi.local` doesn't register a service worker (SW requires HTTPS except localhost). Offline caching only works via the Tailscale URL.

---

## No open tasks
