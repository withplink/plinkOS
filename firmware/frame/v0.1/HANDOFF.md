# Goal

BLE image transfer pipeline — hardware-validated end-to-end. Firmware stable.

## Current State

Full pipeline working:
- iOS FrameTool picks image → Mantis crop → Floyd-Steinberg dither (Spectra 6) → 24-bit BMP → BLE burst → ESP32 PSRAM buffer → SD write → render
- Transfer: ~10s for 1,152,054 bytes. Render: ~43–45s (hardware-limited).
- `releases/02-ble-sd/` — stable snapshot with PSRAM buffer fix. Pre-built bins committed.

## Files in Flight

None — firmware is stable. Next work is iOS main app integration.

## Changed This Session

- `src/main.cpp` — PSRAM buffer fix: removed all SD I/O from BLE callbacks. `ImageDataCallbacks::onWrite` now `memcpy` into PSRAM only. `ControlCallbacks::onWrite` (COMMIT) sets `gCommitPending` flag. `loop()` detects flag, writes PSRAM buffer to SD, renders, notifies status.
- `releases/02-ble-sd/bins/` — rebuilt with PSRAM fix
- `releases/02-ble-sd/src/main.cpp` — updated snapshot

## Failed Attempts

- SD write inside BLE callback → `Stack canary watchpoint triggered (btController)` crash. BT controller task stack overflows when SD I/O blocks the BLE task. Fix: PSRAM buffer, all SD I/O in `loop()`.
- After crash: SD card init fails on reboot (`GO_IDLE_STATE failed`) — needs full power cycle (unplug/replug), not just reset.

## Next Step

Integrate ditherer + BLE client into main Plink iOS app (tracked: plink-ios#22). FrameTool is the validated prototype — copy `Spectra6Ditherer.swift` and `BLEFrameClient.swift` into Plink target when ready.
