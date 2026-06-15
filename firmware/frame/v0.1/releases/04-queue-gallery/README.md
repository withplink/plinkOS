# Release 04: queue / gallery

**Status:** Stable — hardware-validated 2026-06-15 (queue/gallery engine + crash hardening + UI
parity with the FrameTool app; bugs S, U, B, C, A and app-side T/H/K/P/V/F/L/O/X fixed and tested).

## What's new vs 03-ble-name

- **On-device queue / gallery.** The frame is canonical: a persisted `/queue.json` holds the item
  list, current index, and auto-rotate interval. Assets live in `/img` (panel BMP), `/orig`
  (recrop master JPEG), `/thumb` (list thumbnail JPEG), keyed by a 32-bit id.
- **Full op set over BLE:** add (show-now or queue), remove, reorder, show, next/skip, rename,
  set-interval (seconds), clear-all, plus chunked asset read-back (thumbnails / recrop master).
- **Autonomous auto-rotate** — `threading`-free FreeRTOS timing in `loop()`; rotates with no phone
  connected; `next_in` countdown published for the app.
- **Render on a dedicated FreeRTOS task** — the ~31s Spectra 6 waveform no longer blocks command
  handling. `lcd_chkstatus()` yields (`delay(1)`) so the render task and `loop()` run concurrently.
  Commands tapped mid-render are serviced immediately (no stale-command replay). SD access is
  serialized by a recursive mutex; BLE status notifies by a second mutex.
- **Chunked queue read (`GetQueue` 0x2B)** — the queue JSON is served through the asset-chunk path,
  bypassing the ~600 B GATT value cap that silently dropped queues past ~6 items.
- **Fast boot connect** — the boot resume render is posted to the render task so BLE advertising
  starts within ~1s instead of being blocked behind the ~41s boot render (fixed connect churn).
- **Dev serial tools** (USB UART): `ls`, `cat [path]` (JSON pretty-printed), `clear` (ghosting
  cycle). Char-accumulated input with echo.

## Crash / correctness fixes (from staging validation)

- Op serialization, clear-gallery (heap vector, not stack array), send-after-clear (static
  FrameCmd in the BLE callback), chunked read-back loop, drop-oldest cmd queue, interval in SECONDS
  (UInt32 wire), `vfs remove()` guarded by `SD.exists`.

## Service / characteristics

**Service UUID:** `4fafc201-1fb5-459e-8fcc-c5c9c331914b`

| Characteristic | Properties | Purpose |
|---|---|---|
| Image data | WRITE_NR | Stream asset bytes (BeginAsset → chunks → COMMIT) |
| Control | WRITE | Op opcodes (0x01 COMMIT … 0x2B GetQueue) |
| Status | NOTIFY+READ | 0x00 READY, 0x01 RECEIVING, 0x02 RENDERING, 0x10 QUEUE-DIRTY, 0x11 ASSET-READY, 0x12 ASSET-MISSING, 0xFF ERROR |
| Name | READ+WRITE | NVS-backed frame name |
| Queue | READ | small-queue fast path (≤512 B); large queues via chunked GetQueue |
| Asset-out | READ | chunked asset / queue read-back |

See `include/frame_config.h` for the full opcode + UUID table.

## Image format

- 24-bit BMP, no compression, **800×480 panel-native** (app bakes mount rotation in before sending).
- Dithered to the Spectra 6 palette on iOS before transfer.

## Key config

- `EPD_USE_FAST_INIT 0` — slow init (~31s), cleaner render.
- SD: SDHC only (≤32GB).

## Flash

Use `frame.sh` from plink root. Select `04-queue-gallery`. Long-press SW2 during `Connecting......`.
