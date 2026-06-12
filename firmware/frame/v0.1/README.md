# Plink Frame v0.1 Firmware

This is the Plink-owned firmware project for The Frame v0.1.

## Goal

Get the simplest reliable path working first:

1. boot the board
2. mount the SD card
3. open `image0.bmp`
4. render it correctly on the Spectra 6 panel

Once that is stable, we can layer in gallery rules, queue semantics, onboarding, and multi-client
control.

## Stack

- Arduino via PlatformIO
- GooDisplay native driver (`Display_EPD_W21`) — replaces GxEPD2
- SD card on the board's native SD bus

## Files

- `src/main.cpp` — dev firmware (SD render + serial re-render trigger)
- `include/frame_config.h` — display and SD pin map
- `releases/` — stable firmware snapshots; each has full source + pre-built `bins/`
- `flash.sh` — flash tool with numbered release menu and auto port detection
- `reference/ESP32E6-E01-Schematic-Diagram.pdf` — schematic kept with the firmware for quick
  wiring reference

## Notes

- The display pin map is isolated in `include/frame_config.h` so we can fix wiring or orientation
  with one edit if the first flash needs a correction.
- Display bring-up now explicitly asserts `POWER_CTRL` before panel initialization.
- This project deliberately starts narrow. The queue/control-plane work belongs after the image
  render path is proven.
