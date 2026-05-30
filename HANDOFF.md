# Handoff

## Goal

Boot flow hardening, rescue access, and developer SSH key infrastructure.

## This Session

### BootNoWiFi — implemented
- `check_wifi_boot.sh`: no-WiFi-profiles branch now calls `show_hotspot_screen.py setup` directly instead of `toggle_hotspot.sh` → no auto-AP on fresh boot
- `show_hotspot_screen.py`: new `draw_setup_screen()` — centered "Welcome to Plink / Hold Button A to begin setup" fallback text; checks `SETUP_SCREEN_PATH` (`/home/pi/PiInk/assets/setup_screen.png`) first
- Button A long-press → AP mode unchanged (handled by `plink-buttons` service)
- **Pending:** designed image for `setup_screen.png` (user to provide)

### Rescue WiFi
- Per-frame unique SSID `plink-rescue-<label>` with random 8-char password generated at install
- `plink.sh`: prompts frame label → slugified → used as SSID suffix; offers to save creds to `plink-ops/customers/<label>.md`
- `check_wifi_boot.sh`: ignores any NM connection with name prefix `plink-rescue` when counting WiFi profiles
- Creds saved on Pi at `/home/pi/PiInk/config/rescue.conf` (chmod 600)

### Developer SSH Key
- `plink_frames` ed25519 key pair generated; public key hardcoded in `setup-remote.sh`
- Installed to `~/.ssh/authorized_keys` on every frame during setup
- Private key stored at `~/.ssh/plink_frames` on Mac + in `plink-ops` repo
- Recovery: hold A → AP mode → `ssh -i ~/.ssh/plink_frames pi@192.168.4.1`
### plink-ops repo

- Created at `/Users/shoaibahmed/code/personal/plink/plink-ops` → `github.com/withplink/plink-ops` (private)
- Contains: `plink_frames` key pair, README with recovery steps, `customers/` directory for per-frame logs

## 4 e-ink lifecycle screens — ✅ Complete

| # | State | Asset | Status |
|---|-------|-------|--------|
| 1 | Unbox / Pi powered off | `unbox_screen.png` | ✅ Deployed |
| 2 | Boot, no WiFi configured | `no_wifi_screen.png` | ✅ Deployed |
| 3 | AP mode / WiFi setup (after long-press A) | `ap_screen.png` | ✅ Deployed |
| 4 | Connected, empty queue | `empty_queue_screen.png` | ✅ Deployed |

All assets in `pi-scripts/assets/`, deployed by `setup-remote.sh` and `push.sh`. Each falls back to a programmatic render if the file is missing.

## Transfer option — ✅ Added to plink.sh

`plink.sh` now has 4 options: Install / Transfer / Reset / Push. Transfer wipes photos, queue, settings, and all WiFi profiles, renders `unbox_screen.png` to e-ink, then shuts down. New owner powers on and presses Button A to begin setup.

## Next Steps

- Test `[BootNoWiFi]` + `[Onboarding]` fixes on real Pi
- `[SoftwareUpdate]` — Pi pulls latest from GitHub on demand via API endpoint
