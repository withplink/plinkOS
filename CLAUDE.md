# Plink — Claude Context

## Project

Mobile-first PWA companion app for a Raspberry Pi Zero 2W driving an Inky Impression 7.3" e-ink display. Send photos to the frame from your phone.

## Key Files

- `webserver_new.py` → deployed to `/home/pi/PiInk/src/webserver.py` (Flask backend)
- `main.html` → deployed to `/home/pi/PiInk/src/templates/main.html` (React frontend, single file)
- `pi-scripts/patch_inky.py` → patches Inky library v2.x for GPIO/SPI compatibility (runs during install)
- `pi-scripts/install.sh` → full Pi-side setup (deps, deploy, services, boot config, patch)

## Deploy Commands

```bash
# One-command deploy (use this)
./deploy.sh

# Manual equivalent (replace <password> with your Pi's password)
sshpass -p '<password>' scp webserver_new.py pi@pi.local:/home/pi/PiInk/src/webserver.py
sshpass -p '<password>' scp main.html pi@pi.local:/home/pi/PiInk/src/templates/main.html
sshpass -p '<password>' ssh pi@pi.local "echo '<password>' | sudo -S systemctl restart piink && echo done"
```

- SSH host: `pi@pi.local` or `192.168.1.50`
- Sudo password: same as SSH password
- Service: `piink` (systemd)

## Stack

- **Backend:** Flask on port 80, `host="::"`, `threaded=True`
- **Frontend:** React 18 + Babel standalone (no build step), Jinja2 template
- JSX is wrapped in `{% raw %}...{% endraw %}` to avoid Jinja2 `{{}}` conflicts
- No component library — all UI is hand-rolled with inline styles

## Display Driver — CRITICAL

- **Controller:** Spectra 6 (E673), identified via EEPROM on the display
- **Python import:** `from inky.inky_e673 import Inky`
- **NOT** `inky_ac073tc1a` — that's for older 7.3" revisions; using it causes `show()` to silently fail (no error, but display doesn't update)

### Required boot config (`/boot/firmware/config.txt`)

```
dtparam=spi=on
dtoverlay=spi0-0cs
```

The `spi0-0cs` overlay is **mandatory** on Pi Zero 2W + Bookworm. Without it, the SPI driver claims GPIO8 as chip-select, and the Inky library's gpiod requests fail with:
```
Woah there, some pins we need are in use!
  ⚠️   Chip Select: (line 8, GPIO8) currently claimed by spi0 CS0
```

### Inky library patch (`patch_inky.py`)

The Inky library v2.x (gpiod-based) has a conflict with spidev on the CS pin. The patch:
1. Skips `gpiodevice.check_pins_available()` (fails on Bookworm)
2. Removes CS pin from `request_lines()` config (spidev owns it)
3. Removes manual CS toggle in `_spi_write()` (spidev handles it)

Handles both `inky_ac073tc1a.py` and `inky_e673.py` variants (including E673's `Bias.DISABLED` params).

## Frontend Architecture

- Single file: all React components, state, and styles live in `main.html`
- Fonts: Instrument Serif (display) + Geist (UI) + Geist Mono (labels)
- 4 palettes: rose / ash / sun / ink (dark)
- Design: cream paper bg, muted rose accent, 1px hairlines, halftone dot textures

## UI Patterns

- **Mobile-first:** touch targets, no hover states
- **Sheet/modal pattern:** Single `Sheet` component used everywhere. Overlay is `position:'absolute', inset:0` with `onPointerDown` that calls `onClose()` and installs a one-time `window` capture listener to swallow the next `click` (prevents background buttons firing after overlay dismisses). Sheet div blocks pointer with `onPointerDown={e=>e.stopPropagation()}`. Sheet div uses `padding:'14px 22px 144px', marginBottom:'-100px'` — NO `overflow:'hidden'` — so the extra 100px extends below the viewport and absorbs spring-back overshoot. Inner scroll area uses `data-scroll` attribute so swipe-to-dismiss pauses when content is scrolled.
- **Swipe-to-dismiss:** `useSwipeToDismiss` hook — direct ref style mutation (no state = 60fps). Dismiss if `delta > 120` or `(delta > 80 && velocity > 0.8)`. Spring-back uses `cubic-bezier(0.34,1.56,0.64,1)`. Entrance animation: `translateY(32px)→0` with same spring curve at `0.3s`.
- **Haptics:** `haptic(ms)` calls `navigator.vibrate?.(ms)` (Android) with `?? _iosHapticLabel.click()` fallback for iOS 18+ (`<input type="checkbox" switch>` trick). Must be called from a user-gesture handler to trigger on iOS.
- **e-ink refresh (~30s):** always run in a background `threading.Thread(daemon=True)` so HTTP returns immediately; show a loading overlay in the frontend
- **Upload:** file picker only — URL upload removed
- **Offline detection:** `refreshAll()` polls every 30s when online, 8s when offline. `fetch('/api/status')` has `AbortSignal.timeout(5000)` so mobile detects connectivity loss within ~5s.
- **Service worker:** `plink-v1`, network-first for navigation (re-caches shell on every online load), bypasses `/api/*` entirely. Caches `'/'`, `/manifest.json`, `/static/icon.png` at install time.
- **Contextual URL hints:** on HTTPS (Tailscale) + offline → shows `pi.local ↗`. On `pi.local` + Tailscale reachable → shows `switch to tailscale ↗`.

## Queue System

- `/home/pi/PiInk/config/queue.json`: `{items:[{filename, label, added_at, orig_filename?}], current:0, interval:0}`
- `orig_filename` is the pre-crop original; stored when uploaded via `/api/queue/replace`
- Filenames prefixed with timestamp (`YYYYMMDD_HHMMSS_`) to avoid collisions
- `threading.Timer` + `threading.Lock` for auto-rotate
- When queue becomes empty, keep the last file on disk (still showing on e-ink)

## Key API Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/status` | `{wifi, uptime, image_url, orientation, busy, ap_mode}` |
| `POST` | `/api/upload` | Multipart file upload; shows immediately or adds to queue |
| `POST` | `/api/action` | `{action}`: `rotate`, `clear_ghost`, `reboot`, `shutdown` |
| `POST` | `/api/settings` | Save orientation/aspect-ratio settings |
| `GET` | `/api/queue` | Full queue state |
| `POST` | `/api/queue/add` | Add item to queue |
| `POST` | `/api/queue/remove` | Remove item by index |
| `POST` | `/api/queue/reorder` | Reorder items |
| `POST` | `/api/queue/replace` | Replace item at index (multipart: `index`, `file`, optional `original`) |
| `POST` | `/api/queue/next` | Advance to next item |
| `POST` | `/api/queue/show` | Jump to item by index |
| `POST` | `/api/queue/interval` | Set auto-rotate interval in minutes |
| `GET` | `/api/hotspot/status` | `{active, ssid, password, ip}` — AP mode state |
| `GET` | `/api/wifi/networks` | `{known, visible}` — known SSIDs from `wpa_supplicant.conf` + Pi scan results |
| `POST` | `/api/wifi` | `{ssid, password?}` — write creds, trigger hotspot→client switch after 2s |
| `GET/POST` | `/share-target` | Web Share Target receiver; accepts shared photos from OS share sheet |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Display shows stale QR code, `show()` completes silently | Wrong driver (`inky_ac073tc1a` instead of `inky_e673`) | Use `inky.inky_e673.Inky` |
| "Chip Select: GPIO8 currently claimed by spi0 CS0" | Missing `dtoverlay=spi0-0cs` in boot config | Add overlay, reboot |
| `show()` fails with `FileNotFoundError: No such file or directory` | SPI not enabled | Add `dtparam=spi=on` to boot config |
| GPIO event detection fails | `plink-buttons` service already claimed GPIO chip | Normal — webserver catches this and skips |

## GitHub

- Repo: https://github.com/PixeledCode/pi-ink
- SSH remote: `git@github.com-pcode:PixeledCode/pi-ink.git`
- Based on: https://github.com/tlstommy/PiInk
