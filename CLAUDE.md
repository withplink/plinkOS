# Plink — Claude Context

## Multi-repo setup

Plink is a two-repo project. Both repos are always in scope regardless of which one Claude is opened from:

| Repo | Path | Purpose |
|---|---|---|
| `plinkOS` (this repo) | `/Users/shoaibahmed/code/personal/plink/plinkOS` | Pi server (Flask), PWA frontend, setup scripts |
| `plink-ios` | `/Users/shoaibahmed/code/personal/plink/plink-ios` | iOS SwiftUI app |

**On every session start**, read all markdown (`.md`) files in the root of all three repositories to get full context. Specifically, read these files before doing anything:

- `/Users/shoaibahmed/code/personal/plink/plink-ios/AGENTS.md`
- `/Users/shoaibahmed/code/personal/plink/plink-ios/HANDOFF.md`
- `/Users/shoaibahmed/code/personal/plink/plink-ios/README.md`
- `/Users/shoaibahmed/code/personal/plink/plink-ios/TESTING.md`
- `/Users/shoaibahmed/code/personal/plink/plinkOS/AGENTS.md`
- `/Users/shoaibahmed/code/personal/plink/plinkOS/HANDOFF.md`
- `/Users/shoaibahmed/code/personal/plink/plinkOS/README.md`
- `/Users/shoaibahmed/code/personal/plink/plink-ops/AGENTS.md`
- `/Users/shoaibahmed/code/personal/plink/plink-ops/README.md`

**Issues**: fetch from GitHub, not local files. Use `gh issue list` per repo:

```bash
gh issue list --repo withplink/plink-ios
gh issue list --repo withplink/plinkOS
gh issue list --repo withplink/plink-site
gh issue list --repo withplink/plink-ops
```

**Cross-repo changes**: if a task requires changes in `plink-ios` (iOS), make them directly — edit the Swift files as needed. Do not ask the user to switch repos.

**Deploy command** (this repo → Pi): `cd /Users/shoaibahmed/code/personal/plink/plinkOS && bash push.sh`

## Project

Mobile-first PWA companion app for a Raspberry Pi Zero 2W driving an Inky Impression 7.3" e-ink display. Send photos to the frame from your phone.

## Testing doc

After any fix or change to the Pi server, check `/Users/shoaibahmed/code/personal/plink/plink-ios/TESTING.md` section **"13. Pi Server (plinkOS)"** and update or add test coverage for the changed functionality if not already present.

## Key Files

- `webserver_new.py` → deployed to `/home/pi/PiInk/src/webserver.py` (Flask backend)
- `main.html` → deployed to `/home/pi/PiInk/src/templates/main.html` (React frontend, single file)
- `pi-scripts/patch_inky.py` → patches Inky library v2.x for GPIO/SPI compatibility (runs during install)
- `pi-scripts/setup-local.sh` → full Pi-side setup (deps, deploy, services, boot config, patch)
- `pi-scripts/setup-remote.sh` → remote setup over SSH (called by `plink.sh`, has spinner UI)
- `pi-scripts/reset.sh` → resets Pi to pre-install state
- `pi-scripts/scripts/show_hotspot_screen.py` → renders lifecycle screens: `draw_ap_screen` (state 3), `draw_default_screen` (state 4), `draw_setup_screen` (state 2); each tries loading a designed image from `assets/` first, falls back to programmatic render; called via `/api/hotspot/screen` or directly at boot
- `pi-scripts/scripts/check_wifi_boot.sh` → runs at boot via `plink-boot-check.service`; if no non-rescue WiFi profiles → renders setup screen via `show_hotspot_screen.py setup` and exits; if profiles exist but no IP/internet → starts AP mode
- `pi-scripts/scripts/toggle_hotspot.sh` → toggles between AP and client mode; on switch-back, shows current queue item if queue non-empty, else calls `render_screen default`
- `pi-scripts/assets/` → designed e-ink screen images: `unbox_screen.png` (state 1), `no_wifi_screen.png` (state 2), `ap_screen.png` (state 3), `empty_queue_screen.png` (state 4); deployed by `setup-remote.sh` and `push.sh`
- `plink.sh` → single entry point at repo root (curl | bash compatible, shows Install/Transfer/Reset/Push menu)

### e-ink lifecycle screens

4 states, each backed by a designed asset with programmatic fallback:

| # | State | Asset path | Fallback |
|---|-------|-----------|---------|
| 1 | Unbox / powered-off | `assets/unbox_screen.png` | — (rendered during Transfer, retained without power) |
| 2 | Boot, no WiFi | `assets/no_wifi_screen.png` | "Welcome to Plink / Hold Button A to begin setup" |
| 3 | AP mode | `assets/ap_screen.png` | Programmatic QR + `plink-setup` / `plink123` |
| 4 | Connected, empty queue | `assets/empty_queue_screen.png` | "Ready / Open Plink and upload your first photo" |

- `draw_setup_screen()` → state 2; called by `check_wifi_boot.sh` when no WiFi profiles present
- `draw_ap_screen(password)` → state 3; called by `toggle_hotspot.sh` and `/api/hotspot/screen`
- `draw_default_screen()` → state 4; called after WiFi reconnect if queue is empty
- State 1 is rendered explicitly by `plink.sh Transfer` before shutdown; e-ink retains it without power

### Rescue WiFi

- SSID format: `plink-rescue-<frame-label>` (e.g. `plink-rescue-johns-frame`)
- Configured during `plink.sh` install via `prompt_rescue_wifi()`; random 8-char alphanumeric password generated per frame
- `check_wifi_boot.sh` filters out any NM connection with `^plink-rescue` prefix before counting WiFi profiles — rescue network doesn't trigger normal-boot path
- Credentials stored on Pi at `/home/pi/PiInk/config/rescue.conf` (chmod 600)
- Per-frame log saved to `plink-ops/customers/<label>.md` during install (optional)

### Developer SSH key

- `plink_frames` ed25519 key installed on every frame during `setup-remote.sh`
- Public key hardcoded in `setup-remote.sh` → appended to `~/.ssh/authorized_keys` on Pi
- Private key at `~/.ssh/plink_frames` on Mac + in `plink-ops` repo
- Recovery path: hold A → AP mode → `ssh -i ~/.ssh/plink_frames pi@192.168.4.1`

### Setup Script UX

- Default mode: animated spinner per step, all output logged to `/tmp/plink-setup.log` on Pi
- `--verbose` or `-v`: shows full command output inline, no spinner, no log file
- SSH uses `-T -q -o LogLevel=ERROR` to suppress Linux banners and progress indicators

## Deploy Commands

```bash
# One-command deploy (use this)
./push.sh

# Manual equivalent (replace <password> with your Pi's password)
sshpass -p '<password>' scp webserver_new.py pi@pi.local:/home/pi/PiInk/src/webserver.py
sshpass -p '<password>' scp main.html pi@pi.local:/home/pi/PiInk/src/templates/main.html
sshpass -p '<password>' ssh pi@pi.local "echo '<password>' | sudo -S systemctl restart piink && echo done"
```

- SSH host: `pi@pi.local` or `192.168.1.50`
- Sudo password: same as SSH password
- Service: `piink` (systemd)

## Stack

- **Backend:** Flask on port 80, `host="0.0.0.0"`, `threaded=True`
- **Frontend:** React 18 + Babel standalone (no build step), Jinja2 template
- JSX is wrapped in `{% raw %}...{% endraw %}` to avoid Jinja2 `{{}}` conflicts
- No component library — all UI is hand-rolled with inline styles

## Display Driver — CRITICAL

- **Controller:** Spectra 6 (E673) — uses E673 chip, not AC073TC1A
- **Python import:** `from inky.inky_e673 import Inky`
- **NOT** `inky_ac073tc1a` — that's for older 7.3" revisions; using it causes `show()` to silently fail (no error, but display doesn't update)
- **EEPROM is None** on Spectra 6 — I2C bus has no devices; EEPROM-based auto-detect does not work

## Display Model (shown in iOS app)

- `get_display_model()` reads `DISPLAY_MODEL` env var from the systemd service — plain human-readable string e.g. `"Inky Impression 7.3\"`
- Written into `/etc/systemd/system/piink.service` during `setup-remote.sh`
- **Single source of truth:** `displays.conf` in repo root — one display name per line; `plink.sh` reads it and presents numbered picker during install
- Adding a new display = add one line to `displays.conf`; nothing else to change

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
- `orig_filename` — pre-crop original; stored when uploaded via `/api/queue/replace`
- Filenames prefixed with timestamp (`YYYYMMDD_HHMMSS_`) to avoid collisions
- `threading.Timer` + `threading.Lock` for auto-rotate; `_queue_lock` guards `api_queue_add` writes for thread safety
- When queue becomes empty, keep the last file on disk (still showing on e-ink)

## Key API Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/status` | `{wifi, uptime, image_url, orientation, busy, ap_mode, model}` |
| `POST` | `/api/upload` | Multipart file upload; shows immediately or adds to queue |
| `POST` | `/api/action` | `{action}`: `rotate`, `clear_ghost`, `reboot`, `shutdown` |
| `POST` | `/api/settings` | Save orientation/aspect-ratio settings |
| `GET` | `/api/queue` | Full queue state |
| `POST` | `/api/queue/add` | Add item to queue (multipart: `file`, `label?`, `show_now?`) |
| `POST` | `/api/queue/remove` | Remove item by index |
| `POST` | `/api/queue/reorder` | Reorder items |
| `POST` | `/api/queue/replace` | Replace item at index (multipart: `index`, `file`, optional `original`) |
| `POST` | `/api/queue/next` | Advance to next item |
| `POST` | `/api/queue/show` | Jump to item by index |
| `POST` | `/api/queue/interval` | Set auto-rotate interval in minutes |
| `POST` | `/api/queue/rename` | Rename item at index: `{index, label}` |
| `GET` | `/api/hotspot/status` | `{active, ssid, password, ip}` — AP mode state |
| `GET` | `/api/wifi/networks` | `{known, visible}` — known SSIDs from `wpa_supplicant.conf` + Pi scan results |
| `POST` | `/api/wifi` | `{ssid, password?}` — write creds, trigger hotspot→client switch after 2s |
| `GET/POST` | `/share-target` | Web Share Target receiver; accepts shared photos from OS share sheet |
| `POST` | `/api/wifi/switch` | Switch WiFi while in client mode (no hotspot toggle): `{ssid, password?}` |
| `POST` | `/api/hotspot/screen` | Render AP or default screen to e-ink: `{mode: 'ap'|'default', password?}` |
| `GET` | `/api/tailscale/status` | `{state: 'running'|'stopped', ip, url}` |
| `POST` | `/api/tailscale/connect` | Start Tailscale; returns auth URL if not yet authenticated |
| `POST` | `/api/tailscale/disconnect` | `tailscale logout` |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Display shows stale QR code, `show()` completes silently | Wrong driver (`inky_ac073tc1a` instead of `inky_e673`) | Use `inky.inky_e673.Inky` |
| "Chip Select: GPIO8 currently claimed by spi0 CS0" | Missing `dtoverlay=spi0-0cs` in boot config | Add overlay, reboot |
| `show()` fails with `FileNotFoundError: No such file or directory` | SPI not enabled | Add `dtparam=spi=on` to boot config |
| GPIO event detection fails | `plink-buttons` service already claimed GPIO chip | Normal — webserver catches this and skips |
| `ModuleNotFoundError: No module named 'inky'` (systemd) | `pip3 install` without `sudo` installs to `~/.local/` | Use `sudo pip3 install --break-system-packages` + add `Environment=PYTHONPATH=/home/pi/.local/lib/python3.13/site-packages` to systemd service |
| `ValueError: (22, 'Invalid argument')` on `set_value(cs_pin)` | Inky library tries to toggle CS pin via gpiod, but spidev owns GPIO8 | Patch removes ALL `self._gpio.set_value(self.cs_pin, ...)` calls — SPI driver handles CS automatically |
| `SyntaxError: illegal target for annotation` after patch | Patch replaced `if check_pins_available(` with `if True:` but left dict literal dangling | Use regex to replace entire `check_pins_available(gpiochip, { ... })` call including multi-line dict |
| `nmcli connection up` breaks SSH mid-setup | Re-establishing WiFi drops active SSH session | Remove `nmcli connection up` — static IP applies after reboot |
| SSH banner text repeats on every remote command | SSH allocates pseudo-terminal by default | Add `-T` flag to SSH commands |
| `PermissionError` on `patch_inky.py` | Patch writes to `/usr/local/lib/python3.*/dist-packages/` (root-owned) | Run `sudo python3 patch_inky.py` |
| `curl \| bash` breaks `read` prompts | stdin is the script content, not keyboard | Use `read < /dev/tty` or plain `read` (script runs in interactive shell) |
| `push.sh` fails with `cp: cannot stat '../webserver_new.py'` | `setup-local.sh` runs from `/tmp/plink-scripts/` — `../` doesn't point to repo root | `push.sh` handles webserver/frontend copy; `setup-local.sh` skips it when run from `/tmp` |

## Known Issues & Solutions (Session Log)

### 2026-05-20 — Full setup debugging session

1. **`tty_read` function lost during edit** — ASCII art edit accidentally removed the function definition. Fixed by restoring it.
2. **`sshpass -p ""` in wait loops** — Both SSH wait loops used empty password instead of `$PI_PASS`. Fixed.
3. **SSH banner spam** — Every `$SSH` call printed the Linux welcome banner. Fixed with `-T -q -o LogLevel=ERROR`.
4. **`pip3 install` to user site** — Without `sudo`, inky installed to `~/.local/` which systemd can't find. Fixed with `sudo pip3 install --break-system-packages` + `PYTHONPATH` in service.
5. **Inky patch didn't match E673's `_spi_write`** — E673 uses `xfer3` with try/except, not simple `xfer` loop. Original patch never matched. Fixed with regex that removes ALL `set_value(self.cs_pin, ...)` regardless of context.
6. **`_send_command` still had CS pin manipulation** — Regex only matched `_spi_write` context. `_send_command` also calls `set_value(self.cs_pin, Value.ACTIVE)`. Fixed with broader regex: `re.sub(r'\s*self\._gpio\.set_value\(self\.cs_pin, Value\.(INACTIVE|ACTIVE)\)\s*\n', '\n', content)`.
7. **`setup-local.sh` tries to copy `webserver_new.py` from wrong path** — When run from `/tmp/plink-scripts/`, `../webserver_new.py` doesn't exist. Fixed: `setup-local.sh` checks if file exists, skips if not (push.sh handles it).
8. **`patch_inky.py` needs sudo** — Writes to system Python packages directory. Fixed in `setup-local.sh` and `setup-remote.sh`.
9. **`nmcli connection up` breaks SSH** — Drops WiFi connection mid-setup. Removed — static IP applies after reboot.
10. **Default orientation** — Changed from portrait to landscape in `webserver_new.py` (`saveSettings("checked","",...)`).

## GitHub

- Repo: https://github.com/withplink/plinkOS
- SSH remote: `git@github.com-pcode:withplink/plinkOS.git`
- Based on: https://github.com/tlstommy/PiInk
