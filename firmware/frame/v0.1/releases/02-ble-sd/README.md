# Release 02: BLE + SD

**Status:** Stable — hardware-validated 2026-06-12 (bins updated: PSRAM buffer fix)

## What this firmware does

Boot → power EPD → init Spectra 6 panel → mount SD card → render `/image0.bmp` if present → start BLE advertising.

iOS connects via BLE, streams a pre-dithered 24-bit BMP, sends COMMIT → frame writes BMP to SD → renders → sleeps display.

## BLE interface

**Device name:** `Plink Frame`

**Service UUID:** `4fafc201-1fb5-459e-8fcc-c5c9c331914b`

| Characteristic | UUID | Properties | Purpose |
|---|---|---|---|
| Image data | `beb5483e-36e1-4688-b7f5-ea07361b26a8` | WRITE_NR | Stream BMP bytes (MTU-sized chunks) |
| Control | `cba1d466-344c-4be3-ab3f-189f80dd7518` | WRITE | `0x01`=COMMIT, `0x00`=ABORT |
| Status | `f4b8ef7d-1e3a-4b9c-8d2f-6a7c5e9f0b1d` | NOTIFY | `0x00`=READY, `0x01`=RECEIVING, `0x02`=RENDERING, `0xFF`=ERROR |

## Transfer flow

1. Connect → subscribe to status notify → receive `0x00` (READY)
2. Write BMP bytes to image data char in MTU-sized chunks (MTU 512 → 509 bytes/packet)
3. Write `0x01` to control char → receive `0x02` (RENDERING)
4. Wait for `0x00` (READY) notify → render complete

## Image format

- 24-bit BMP, no compression
- 800×480 landscape or 480×800 portrait (must match `kFrameRotation` in `frame_config.h`)
- Dithered to Spectra 6 palette on iOS before transfer

## Key config (same as 01-sd-display)

- Portrait mode (`kFrameRotation 1`)
- `EPD_USE_FAST_INIT 0` — slow init (~31s), cleaner render
- `CDI=0x3F`
- SD: SDHC only (≤32GB)

## Rebuild

```
cd releases/02-ble-sd
pio run
```

## Flash

Use `frame.sh` from plink root. Select `02-ble-sd`. Long-press SW2 during `Connecting......`.

## Verify with nRF Connect

1. Flash and boot
2. Open nRF Connect → scan → find `Plink Frame`
3. Connect → confirm 3 characteristics appear under the service UUID
4. Subscribe to status char → confirm `0x00` notify on connect
