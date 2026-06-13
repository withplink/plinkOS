# Release 03: BLE + SD + frame name

**Status:** Stable — hardware-validated 2026-06-13 (stable-03: all v0.1 bugs #1–#8 fixed).

## What's new vs 02-ble-sd

- **Frame name on the device** — persisted in NVS (`Preferences`), exposed via a READ+WRITE name
  characteristic (`BLE_NAME_CHAR_UUID`). The app writes a new name over BLE; the firmware rebuilds
  its advertising/scan-response so the new name broadcasts **live on the next reconnect — no reboot**
  (`applyAdvertising()`), and persists across power-cycle.
- **Orientation moved to the app (firmware is rotation-agnostic).** The app always sends a
  panel-native 800×480 BMP already rotated for the mount; `renderBmpFromSd` renders it directly. The
  old dimension-inference rotation + rotation PSRAM buffer are removed. Both portrait mounts are
  480×800 visible → indistinguishable by dims, so rotation must live app-side.

## What this firmware does

Boot → power EPD → init Spectra 6 panel → mount SD → render `/image0.bmp` if present → load NVS
name → start BLE advertising as that name.

iOS connects via BLE, streams a pre-dithered panel-native 24-bit BMP, sends COMMIT → frame writes
BMP to SD → renders → sleeps display.

## BLE interface

**Device name:** the NVS-stored frame name (default `Plink Frame` until renamed).

**Service UUID:** `4fafc201-1fb5-459e-8fcc-c5c9c331914b`

| Characteristic | UUID | Properties | Purpose |
|---|---|---|---|
| Image data | `beb5483e-36e1-4688-b7f5-ea07361b26a8` | WRITE_NR | Stream BMP bytes (MTU-sized chunks) |
| Control | `cba1d466-344c-4be3-ab3f-189f80dd7518` | WRITE | `0x01`=COMMIT, `0x00`=ABORT |
| Status | `f4b8ef7d-1e3a-4b9c-8d2f-6a7c5e9f0b1d` | NOTIFY+READ | `0x00`=READY, `0x01`=RECEIVING, `0x02`=RENDERING, `0xFF`=ERROR |
| Name | `f4b8ef7d-1e3a-4b9c-8d2f-6a7c5e9f0c2e` | READ+WRITE | Read/set the NVS-backed frame name |

## Transfer flow

1. Connect → subscribe to status notify → receive `0x00` (READY)
2. Write BMP bytes to image data char in MTU-sized chunks (MTU 512 → 509 bytes/packet)
3. Write `0x01` to control char → receive `0x02` (RENDERING)
4. Wait for `0x00` (READY) notify → render complete

## Image format

- 24-bit BMP, no compression
- **Always 800×480 panel-native** (the app bakes mount rotation in before sending)
- Dithered to Spectra 6 palette on iOS before transfer

## Key config

- `EPD_USE_FAST_INIT 0` — slow init (~31s), cleaner render
- `kFrameRotation` — reference-only, unused (rotation is app-side)
- SD: SDHC only (≤32GB)

## Rebuild

```
cd plinkOS/firmware/frame/v0.1
./build-dev.sh    # builds top-level src/ + syncs bins; or `pio run` for an in-place build
```

## Flash

Use `frame.sh` from plink root. Select `03-ble-name`. Long-press SW2 during `Connecting......`.
