# Goal

BLE image transfer pipeline — push image from iOS app to ESP32 frame over BLE.

## Current State

Display driver migration complete and committed. All timing A/B done. Firmware on board is stable.

- GooDisplay native driver (`Display_EPD_W21`) replaces GxEPD2 — both committed and pushed
- Hot re-render via serial keypress works (framebuffer cached in PSRAM)
- Refresh timing confirmed: EPD_init (PLL=0x08) → ~31s hot, EPD_init_fast (PLL=0x02) → ~36s hot
- `EPD_USE_FAST_INIT 0` set as default in `frame_config.h`
- `kFrameRotation 1` → portrait mode (480w × 800h logical, 90°CW to physical 800×480)
- docs updated, committed, pushed — hardware-reference.md has full timing table
- No open issues

Current firmware behavior:
1. Boot → EPD power ON → EPD_init → SD init → read `/image0.bmp` → decode+rotate → PIC_display → EPD_sleep
2. Serial keypress → epd_reinit → PIC_display(gFrameBuffer) → EPD_sleep (hot re-render)

## Files in Flight

- `src/main.cpp` — add BLE server, receive image bytes, write to gFrameBuffer, trigger re-render
- `include/frame_config.h` — may need BLE config constants (MTU, service/char UUIDs)
- `platformio.ini` — verify BLE libs available (ESP32 Arduino core has BLE built-in)

## Changed

Previous session (all committed + pushed):
- Migrated from GxEPD2 to GooDisplay native driver (`Display_EPD_W21.cpp/h`, `Display_EPD_W21_spi.cpp/h`)
- Added `gFrameBuffer` global (PSRAM, persisted after first render)
- Added `epd_reinit()` (no SPI re-init, 200ms settle) — fixes double SPI.begin crash on hot re-render
- Added hot re-render via `Serial.available()` in `loop()` with ms timing output
- `EPD_USE_FAST_INIT 0` config flag in `frame_config.h`
- `kFrameRotation 1` flag — portrait mode
- docs/hardware-reference.md: full refresh timing table, precaution #10 corrected, assessment updated
- Removed GxEPD2 + Adafruit GFX from `platformio.ini`

## Failed Attempts

- Hot re-render via `initDisplay()` call in loop — crashed (double SPI.begin + beginTransaction). Fixed by extracting `epd_reinit()` that skips SPI init.
- Flashing from `build/` (stale GxEPD2 bins) instead of `.pio/build/esp32-s3-devkitc-1/` — produced wrong timing data. Correct path: `.pio/build/esp32-s3-devkitc-1/`.

## Next Step

Start BLE image transfer: add BLE GATT server to `src/main.cpp` that accepts 384KB (800×480) raw token buffer over BLE, stores into a new PSRAM buffer, then calls `epd_reinit()` + `PIC_display()` + `EPD_sleep()`. iOS side (Issue #29) needs matching BLE image push. Start with ESP32 side — define service UUID, characteristic UUID, chunked write handler.
