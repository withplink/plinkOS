# Release 06: device actions over BLE

**Status:** Stable — hardware-validated 2026-06-15. Builds on 05-crop-cache; adds the
clear-ghost + reboot device actions over BLE (the last v0.1 parity gap vs the Pi `/api/action`
surface). Paired with the FrameTool Settings "Device" section + clear-ghost blocking overlay.

## What's new vs 05-crop-cache

- **`kBleClearGhost` (0x2C)** — runs the ghosting-clear cycle (4 black/white full-panel passes,
  ~124s) then restores the shown image. Signals busy (`0x02`) for the whole cycle so the app can
  gate interaction; the restore render's `0x00` ends it (or it releases immediately when the queue
  is empty). Refuses if a render is already in flight. (Same routine the serial `clear` command runs.)
- **`kBleReboot` (0x2D)** — `esp_restart()`. The connection drops; the app's connection keeper
  reconnects. (No `shutdown` — ESP32 has no OS shutdown; deep-sleep is the v0.2 / power story.)

## Device-action parity (vs Pi `/api/action`)

| Pi action | Frame v0.1 |
|---|---|
| rotate | ✅ auto-rotate + skip/next |
| clear_ghost | ✅ kBleClearGhost (0x2C) |
| reboot | ✅ kBleReboot (0x2D) |
| shutdown | N/A (no OS; deep-sleep is v0.2) |

## Notes carried from 04/05

- Render on a dedicated FreeRTOS task (`lcd_chkstatus` yields). Chunked `GetQueue` (0x2B).
  Per-item crop persisted in queue.json (`kAssetCrop`). Boot-render skip via NVS `last_render`.
- **clear-ghost blocks loop() for ~124s** (it drives the EPD directly from loop). The app shows a
  blocking, collapsible overlay and disables all interaction for the duration; commands sent anyway
  would queue and apply late.

## Flash

Use `frame.sh` from plink root. Select `06-device-actions`. Long-press SW2 during `Connecting......`.
