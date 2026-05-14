# Goal

Mobile-first PWA companion for a Raspberry Pi Zero 2W driving an Inky Impression 7.3" e-ink display. Send photos from your phone, manage a queue, and have the app load even when the Pi is off (cached shell via service worker).

---

## Current State

App is fully working and deployed. Key capabilities:
- Upload photos → crop → show now or add to queue
- Queue management: reorder, remove, auto-rotate on interval, manual next
- Device controls: rotate image, clear ghosting, reboot, shutdown
- Service worker v6 caches app shell at install time → app loads offline
- Status dot below device card shows online/offline state
- **Contextual URL hints:** when on Tailscale URL and offline, status shows `offline · pi.local ↗` (tappable link). When on `pi.local` and Tailscale is reachable, shows `switch to tailscale ↗` below the dot.

Pi is accessible two ways:
- `http://pi.local` — local WiFi, mDNS
- `https://pi.tail4e929d.ts.net` — Tailscale VPN (Tailscale must be on)

Tailscale auto-starts on boot (`tailscaled` is enabled), but takes ~90 s after power-on.

---

## Files in flight

| Local | Deployed to |
|---|---|
| `webserver_new.py` | `/home/pi/PiInk/src/webserver.py` |
| `main.html` | `/home/pi/PiInk/src/templates/main.html` |

Deploy + restart:
```bash
sshpass -p '5409' scp webserver_new.py pi@pi.local:/home/pi/PiInk/src/webserver.py
sshpass -p '5409' scp main.html pi@pi.local:/home/pi/PiInk/src/templates/main.html
sshpass -p '5409' ssh pi@pi.local "echo '5409' | sudo -S systemctl restart piink && echo done"
```

---

## Changed

All in this session (newest first):

**`dd05a2c` — Replace cross-origin fallback with contextual URL hints**
Reverted the `apiBase`/`api`/`imgSrc` abstraction. All fetches are back to plain relative `fetch('/api/...')`. Instead of trying to auto-probe across origins (which fails due to mixed content), the status indicator now shows a helpful link: offline on HTTPS → `pi.local ↗`; on pi.local → `switch to tailscale ↗` (appears if a Tailscale probe succeeds on mount).

**`70855b4` — Auto-connect: try same-origin then pi.local fallback** *(reverted by above)*
Added `apiBase` ref and probe loop. Reverted because browser mixed content policy blocks HTTP fetches from an HTTPS page — the fallback silently failed.

**`719b69e` — Replace offline banner with inline status dot**
Removed the fixed top banner that showed when offline. Status is now purely the dot + text below the device card. Dot is green (online) or red (offline). Text changes to `offline · reconnecting` or `offline · pi.local ↗`.

**`0ffe588` — SW v5: move shell caching from activate → install**
Root fix for iOS offline caching. iOS Safari can kill the SW process right after `activate` fires, before async network fetches complete. Moving caching to `install` (while the user is provably online) and calling `skipWaiting()` only after caching completes fixed this. Bumped to v6 to force reinstall.

**CORS headers added to `webserver_new.py`**
`@app.before_request` handles OPTIONS preflight; `@app.after_request` adds `Access-Control-Allow-Origin: *` to all responses. Needed for the Tailscale-probe fetch from `http://pi.local` (HTTP→HTTPS cross-origin, which browsers do allow).

---

## Failed attempts

**SW caching in the `activate` event (v4 and earlier)**
iOS Safari terminates the SW process during the activate event's `waitUntil` promise chain if the user closes the tab quickly. The `caches.add('/')` fetch never completed, leaving the cache empty. Fix: move to `install`.

**Auto-connect `apiBase` fallback — `http://pi.local` from Tailscale HTTPS URL**
When the page is loaded over HTTPS (`https://pi.tail4e929d.ts.net`), browsers enforce mixed content policy and block any `fetch('http://pi.local/...')` call — it throws a TypeError immediately. The probe loop's `.catch()` caught this as a failure and moved on, resulting in `setOnline(false)` regardless of local network state. No code fix can work around this without HTTPS on the Pi itself.

**`pi.local` not resolving on iOS with Tailscale VPN active**
Tailscale intercepts DNS on iOS, breaking mDNS `.local` resolution. Toggling Tailscale off/on resets DNS. Not fixed in code — it's a Tailscale/iOS interaction.

---

## Next step

**Verify SW offline caching end-to-end on iOS Safari with the Tailscale URL:**

1. Pi on, Tailscale VPN on
2. Open `https://pi.tail4e929d.ts.net` in Safari → wait ~3 s
3. Turn Pi off (or toggle Tailscale off)
4. Force-quit Safari and reopen
5. Navigate to `https://pi.tail4e929d.ts.net` — should load the app shell with red offline dot

If the cache still isn't persisting, check Safari → Settings → Privacy → clear website data hadn't wiped it, and confirm the SW is registered under Application tab in desktop Safari dev tools pointed at the phone.
