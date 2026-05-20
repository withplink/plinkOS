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

## Setup

### Flash

Use Raspberry Pi Imager with **Pi OS Lite (Bookworm 64-bit)**. In the advanced settings:

- Hostname: `pi`
- User: `pi`, password: `5409`
- WiFi: your home network
- Enable SSH

### First-boot setup (run from Mac)

Make sure `sshpass` is installed (`brew install sshpass`), then from the repo root:

```bash
bash pi-scripts/first-boot-setup.sh
```

This script waits for the Pi to come online, then:
- Sets static IP `192.168.1.50`
- Enables link-local IPv6 (required for iOS Bonjour discovery)
- Disables WiFi power save
- Installs Python + system deps
- Deploys `webserver_new.py` and `main.html`
- Installs all systemd services (`piink`, `plink-buttons`, `plink-boot-check`)
- Installs Avahi mDNS service
- Starts the frame server

Frame is live at `http://pi.local` when done.

## Deploying changes

From the repo root on your Mac:

```bash
./deploy.sh
```

Copies both files to the Pi and restarts the service.

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

This runs automatically during `install.sh`.

## Design

Cream paper background, muted rose accent, 1px hairlines, halftone dot textures, Instrument Serif + Geist typefaces.

## Based on

[PiInk](https://github.com/tlstommy/PiInk) by [@tlstommy](https://github.com/tlstommy)
