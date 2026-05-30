# Plink

A mobile-first PWA companion app for a Raspberry Pi Zero 2W driving an [Inky Impression 7.3"](https://shop.pimoroni.com/products/inky-impression-7-3) e-ink display.

Send a moment to your plink.

## Stack

- **Backend** — Flask (Python), runs on the Pi at port 80
- **Frontend** — React 18 + Babel standalone (no build step), single `main.html` Jinja2 template
- **Display** — Inky Impression 7.3" Spectra 6 (E673 driver), 800×480, 7-colour e-ink

## Features

- Upload photos from your phone
- Crop to the display's aspect ratio before sending
- Photo queue with configurable auto-rotate interval; replace queue items in-place
- Palette themes: rose / ash / sun / ink (dark)
- Portrait & landscape orientation support
- PWA — add to home screen on iOS/Android, loads offline (cached shell via service worker)
- Web Share Target — share photos directly from the iOS/Android Photos app
- Haptic feedback on iOS 18+ and Android
- Swipe-to-dismiss sheets with spring animations
- Device controls: rotate display, clear ghosting, reboot, shutdown
- Hotspot/AP mode — Pi broadcasts `plink-setup` Wi-Fi for initial provisioning; shows "Ready" screen after connecting, or resumes queue if photos exist
- Online/offline status dot — auto-detects connectivity, shows local URL hint when on Tailscale and Pi is unreachable

## Hardware

- Raspberry Pi Zero 2W
- Inky Impression 7.3" e-ink display (Spectra 6 / E673 controller)
- microSD card (8GB+)

## New Frame Setup

From unboxing to a working frame:

### 1. Flash the microSD card

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/). **Important: use Raspberry Pi OS (Bookworm) 32-bit** — the 64-bit version has GPIO compatibility issues with the Inky library.

In the imager's advanced settings (gear icon):
- Hostname: `pi`
- Set a username and password
- WiFi: your home network
- Enable SSH

### 2. Boot the Pi

Insert the card into the Pi Zero 2W, connect power, and wait ~60 seconds for first boot.

### 3. Run setup

**One-line setup (recommended):**

```bash
curl -sL https://raw.githubusercontent.com/withplink/plinkOS/main/plink.sh | bash
```

This will prompt for your Pi's password (the one you set during flashing). It connects via `pi.local` (mDNS/Bonjour — works out of the box on macOS/iOS), then handles everything: dependency install, display driver patch, static IP setup, service installation, and reboot. Stale SSH host keys from reflashing are cleared automatically.

Add `--verbose` or `-v` to see full command output instead of the default spinner:

```bash
curl -sL https://raw.githubusercontent.com/withplink/plinkOS/main/plink.sh | bash -s -- --verbose
```

**Manual setup (alternative):**

```bash
git clone https://github.com/withplink/plinkOS.git
cd plinkOS
cp .env.example .env
# Edit .env — PI_PASS must match the password from step 1
bash pi-scripts/setup-remote.sh
```

During setup you'll be prompted for:
- **Pi password** (set during flashing)
- **Display model** (pick from list)
- **Frame label** — e.g. customer name; used to identify the frame and name the rescue WiFi network
- **Rescue WiFi** — a unique `plink-rescue-<label>` SSID with a generated 8-char password; create a hotspot with these credentials for emergency SSH access if the frame loses WiFi

The script will:
- Wait for the Pi to come online
- Set static IP `192.168.1.50`
- Enable SPI + add `dtoverlay=spi0-0cs` (required for the display)
- Disable WiFi power save
- Install all Python and system dependencies
- Deploy the webserver and frontend
- Install systemd services (`piink`, `plink-buttons`, `plink-boot-check`)
- Patch the Inky library for GPIO/SPI compatibility
- Install Avahi mDNS service
- Install developer SSH key (for recovery access)
- Configure rescue WiFi network on the Pi
- Reboot the Pi (required for boot config changes)
- Start the frame server

### 4. Done

The frame is live at `http://pi.local` or `http://192.168.1.50`. Open it on your phone and upload a photo.

## Boot Flow

| # | State | Trigger | Asset |
|---|-------|---------|-------|
| 1 | **Unbox / powered-off** | Frame ships or is transferred; e-ink retains image without power | `unbox_screen.png` |
| 2 | **Boot, no WiFi** | New owner powers on; no WiFi profiles saved | `no_wifi_screen.png` → fallback: "Hold A to begin setup" text |
| 3 | **AP mode / WiFi setup** | User holds Button A (~1.5s) | `ap_screen.png` → fallback: programmatic QR + `plink-setup` / `plink123` |
| 4 | **Connected, empty queue** | WiFi configured, no photos uploaded yet | `empty_queue_screen.png` → fallback: "Ready / upload first photo" text |
| — | **Queue active** | Photos in queue | Current photo from queue |

All screen assets live at `/home/pi/PiInk/assets/` on the Pi and `pi-scripts/assets/` in the repo. Each has a programmatic fallback so the frame is never blank.

The `plink-boot-check` service runs before the frame server on every boot. If no WiFi profiles are saved (excluding the rescue network), it renders state 2 directly to the display and exits — no AP mode is started automatically.

## Recovery Access

### Rescue WiFi (emergency SSH)

Each frame has a unique `plink-rescue-<label>` WiFi profile installed during setup. If the frame loses WiFi connectivity, create a hotspot with the rescue credentials (saved at `/home/pi/PiInk/config/rescue.conf` on the Pi) — the frame will connect automatically without showing the setup screen.

### Developer SSH key (AP mode recovery)

A shared `plink_frames` SSH key is installed on every frame during setup. To access any frame without pre-coordination:

1. Hold **Button A** (~1.5s) → frame switches to AP mode, e-ink shows QR + credentials
2. Connect your Mac to `plink-setup` WiFi
3. SSH in:
   ```bash
   ssh -i ~/.ssh/plink_frames pi@192.168.4.1
   ```

## Deploying changes

After the initial setup, push code changes with:

```bash
./push.sh
```

Copies `webserver_new.py` and `main.html` to the Pi and restarts the service.

## Resetting the Pi

To clean the Pi back to a pre-install state (removes packages, services, configs):

```bash
bash pi-scripts/reset.sh
```

Add `--verbose` or `-v` to see full command output instead of the default spinner. Then re-run `plink.sh` for a fresh install.

## Display Driver Notes

The Inky Impression 7.3" uses the **Spectra 6 (E673)** controller, identified via EEPROM. The codebase uses `inky.inky_e673` (not `inky_ac073tc1a`).

### Critical boot config

The following must be present in `/boot/firmware/config.txt`:

```
dtparam=spi=on
dtoverlay=spi0-0cs
```

The `spi0-0cs` overlay disables the SPI driver's chip-select claim on GPIO8, which conflicts with the Inky library's gpiod pin requests. Without it, `show()` fails with "Chip Select: (line 8, GPIO8) currently claimed by spi0 CS0".

### Inky library patch

The `pi-scripts/patch_inky.py` script patches the installed Inky library (v2.x) to:
1. Skip the GPIO pin availability check (fails on Bookworm)
2. Not request the CS pin via gpiod (spidev owns it)
3. Not manually toggle CS in `_spi_write` (spidev handles it)

This runs automatically during `setup-remote.sh`.

## Design for PWA

Cream paper background, muted rose accent, 1px hairlines, halftone dot textures, Instrument Serif + Geist typefaces.
