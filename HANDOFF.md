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
- `plink.sh`: prompts frame label → slugified → used as SSID suffix; offers to save creds to `plink-private/customers/<label>.md`
- `check_wifi_boot.sh`: ignores any NM connection with name prefix `plink-rescue` when counting WiFi profiles
- Creds saved on Pi at `/home/pi/PiInk/config/rescue.conf` (chmod 600)

### Developer SSH Key
- `plink_frames` ed25519 key pair generated; public key hardcoded in `setup-remote.sh`
- Installed to `~/.ssh/authorized_keys` on every frame during setup
- Private key stored at `~/.ssh/plink_frames` on Mac + in `plink-private` repo
- Recovery: hold A → AP mode → `ssh -i ~/.ssh/plink_frames pi@192.168.4.1`

### plink-private repo
- Created at `/Users/shoaibahmed/code/personal/plink-private` → `github.com/PixeledCode/plink-private` (private)
- Contains: `plink_frames` key pair, README with recovery steps, `customers/` directory for per-frame logs

## 4 e-ink lifecycle screens

| # | State | Status |
|---|-------|--------|
| 1 | Unbox / Pi powered off | Image needed |
| 2 | Boot, no WiFi configured | ✅ Code done — image needed (`setup_screen.png`) |
| 3 | AP mode / WiFi setup (after long-press A) | Existing `draw_ap_screen()` — needs polish |
| 4 | Connected, empty queue | ✅ `great_wave_retro.png` deployed |

## Next Steps

- Provide designed images for screens 1, 2, 3 (`[DefaultScreen]` issue)
- Test `[BootNoWiFi]` + `[Onboarding]` fixes on real Pi
- `[SoftwareUpdate]` — Pi pulls latest from GitHub on demand via API endpoint
