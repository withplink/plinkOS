# Release 01: SD Display

**Status:** Stable — validated on hardware 2026-06-12

## What this firmware does

Boot → power EPD → init Spectra 6 panel → mount SD card → read `/image0.bmp` → decode + rotate 90° CW → render → sleep.

No BLE. No gallery rotation. Single image, displayed once per boot.

## Key config

- Portrait mode (`kFrameRotation 1`) — 480×800 logical, 90°CW to physical 800×480
- `EPD_USE_FAST_INIT 0` — uses `EPD_init` (PLL=0x08), ~31s waveform, clean render
- `CDI=0x3F` — full-clear, no ghosting
- SD: SDHC only (≤32GB). SDXC fails on ESP32 SPI mode.

## Differences from dev firmware

Serial re-render (keypress → hot re-render from PSRAM) removed. `loop()` is idle. All other behavior identical.

## Pre-built bins

`bins/` contains binaries built from this source snapshot. Flash with:

```
python3 -m esptool --chip esp32s3 --port /dev/cu.usbserial-110 --baud 115200 \
  write_flash \
  0x0     bins/bootloader.bin \
  0x8000  bins/partitions.bin \
  0x10000 bins/firmware.bin
```

Or use `flash.sh` from the firmware root — it handles port detection and firmware selection.

## Rebuild

This is a complete PlatformIO project. To rebuild from source:

```
cd releases/01-sd-display
pio run
```

Binaries will be in `.pio/build/esp32-s3-devkitc-1/`.
