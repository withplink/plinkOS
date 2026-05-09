# pi-ink

A mobile-first PWA companion app for a Raspberry Pi Zero 2W driving an [Inky Impression](https://shop.pimoroni.com/products/inky-impression-7-3) e-ink display.

Send photos to your e-ink frame from your phone.

## Stack

- **Backend** — Flask (Python), runs on the Pi at port 80
- **Frontend** — React 18 + Babel standalone (no build step), single `main.html` Jinja2 template
- **Display** — Inky Impression 7-colour e-ink, driven by Pimoroni's Python library

## Features

- Upload photos from your phone (file picker or URL)
- Crop to the display's aspect ratio before sending
- Photo queue with auto-rotate interval
- Palette themes: rose / ash / sun / ink
- Portrait & landscape orientation support
- PWA — add to home screen on iOS/Android
- Device controls: rotate, clear ghosting, reboot, shutdown

## Hardware

- Raspberry Pi Zero 2W
- Inky Impression e-ink display (7.3")

## Setup

1. Clone onto the Pi:
   ```bash
   git clone https://github.com/PixeledCode/pi-ink /home/pi/PiInk
   ```

2. Install dependencies:
   ```bash
   pip install flask pillow inky
   ```

3. Copy files to their expected paths:
   - `webserver_new.py` → `/home/pi/PiInk/src/webserver.py`
   - `main.html` → `/home/pi/PiInk/src/templates/main.html`

4. Run:
   ```bash
   sudo python /home/pi/PiInk/src/webserver.py
   ```

   Or set up as a systemd service for auto-start on boot.

## Design

Cream paper background, muted rose accent, 1px hairlines, halftone dot textures, Instrument Serif + Geist typefaces.

## Based on

[PiInk](https://github.com/tlstommy/PiInk) by [@tlstommy](https://github.com/tlstommy)
