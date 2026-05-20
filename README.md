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
- Hotspot/AP mode — Pi broadcasts `plink-setup` Wi-Fi for initial provisioning
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

### 2. Configure credentials

Clone this repo and create a `.env` file with your Pi's SSH credentials:

```bash
git clone https://github.com/PixeledCode/pi-ink.git
cd pi-ink
cp .env.example .env
# Edit .env with your username and password
```

### 3. Boot the Pi

Insert the card into the Pi Zero 2W, connect power, and wait ~60 seconds for first boot.

### 4. Run first-boot setup

Make sure `sshpass` is installed (`brew install sshpass`), then:

```bash
bash pi-scripts/first-boot-setup.sh
```

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
- Reboot the Pi (required for boot config changes)
- Start the frame server

### 5. Done

The frame is live at `http://pi.local` or `http://192.168.1.50`. Open it on your phone and upload a photo.

## Deploying changes

After the initial setup, push code changes with:

```bash
./deploy.sh
```

Copies `webserver_new.py` and `main.html` to the Pi and restarts the service.

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

This runs automatically during `first-boot-setup.sh`.

## Design

Cream paper background, muted rose accent, 1px hairlines, halftone dot textures, Instrument Serif + Geist typefaces.

## Based on

[PiInk](https://github.com/tlstommy/PiInk) by [@tlstommy](https://github.com/tlstommy)
