# Goal

BLE image transfer pipeline — push image from iOS app to ESP32 frame over BLE.

## Current State

Firmware management system in place. `releases/01-sd-display` is the stable snapshot — SD card
read → BMP decode → Spectra 6 render, no serial re-render. Pre-built bins committed.

- `releases/01-sd-display/` — complete source snapshot + `bins/` (bootloader, partitions, firmware)
- `frame.sh` — unified tool: port auto-detect, Flash or Monitor menu, quit hint before screen launch
- `flash.sh` — flash-only variant (still functional standalone)
- Dev `src/main.cpp` — serial re-render removed; `loop()` is idle (`delay(1000)`)

## Files in Flight

- `src/main.cpp` — add BLE server, receive image bytes into PSRAM buffer, trigger re-render
- `include/frame_config.h` — add BLE UUID constants (MTU, service/char UUIDs)
- `platformio.ini` — verify BLE deps (ESP32 Arduino core has BLE built-in, no extra lib needed)

## Changed This Session

- `releases/01-sd-display/` — created: full source snapshot, pre-built bins, README
- `frame.sh` — new unified flash+monitor tool with quit hint and pre-launch pause
- `flash.sh` — monitor-after-flash prompt moved pre-flash; bash 3.2 compat fix
- `src/main.cpp` — serial re-render trigger removed from `loop()`
- `README.md` — updated Stack section (GxEPD2 → GooDisplay native driver), added releases/frame.sh entries
- `docs/hardware-reference.md` — added CDI=0x3F precaution (#11)

## Failed Attempts

- Hot re-render via `initDisplay()` call in loop — crashed (double SPI.begin + beginTransaction). Fixed by extracting `epd_reinit()` that skips SPI init.
- Flashing from `build/` (stale GxEPD2 bins) instead of `.pio/build/esp32-s3-devkitc-1/` — produced wrong timing data.

## Next Step

Start BLE image transfer (`02-ble` release):
1. Add BLE GATT server to dev `src/main.cpp`
2. Service UUID: `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
3. 384KB PSRAM receive buffer `gBleReceiveBuf` + offset counter
4. Image data char (write-no-response): chunk → memcpy → advance offset
5. Control char: `0x01`=COMMIT → `epd_reinit()` + `PIC_display()` + `EPD_sleep()`; `0x00`=ABORT
6. Status char (notify): READY/RECEIVING/RENDERING/ERROR
7. Verify advertising with nRF Connect before touching iOS side
8. Snapshot stable build → `releases/02-ble/`
