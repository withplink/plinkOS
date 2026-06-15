# Release 05: crop persistence + boot-render skip

**Status:** Stable — hardware-validated 2026-06-15. Builds on 04-queue-gallery (render task, chunked
queue, fast boot) and adds per-item crop persistence + a redundant-boot-render skip. Paired with the
FrameTool crop-cache app batch.

## What's new vs 04-queue-gallery

- **Per-item crop transformation persisted in `queue.json`.** New asset kind `kAssetCrop` (0x03):
  the app streams the Mantis crop transformation as JSON; `handleCommit` parses it into the queue
  item's `crop` field (stored opaque, never interpreted; preserved across reorder/rename). Lets the
  app re-seed Mantis exactly on recrop and render crop-accurate thumbnails, and it survives reinstall
  / another phone because the frame owns it. Carried over the existing asset-stream path (no new
  control opcode, no `FrameCmd` bloat).
- **Boot-render skip (e-ink retention).** The last-painted item id is persisted to NVS
  (`frame/last_render`) after every render. On boot, if the resolved current item already equals it,
  the frame skips the redundant ~31s repaint (the panel retains it with no power); it still renders
  when the id differs (e.g. SD swapped while off). NVS skips the write when the value is unchanged,
  so repeated renders of the same id don't wear flash. Legacy/ghost-clear paths keep id=0 → always
  render (rare back-compat).

## Asset kinds

| Kind | Value | Destination |
|---|---|---|
| BMP   | 0x00 | `/img/<id>.bmp` (panel-native display) |
| JPEG  | 0x01 | `/orig/<id>.jpg` (recrop master) |
| Thumb | 0x02 | `/thumb/<id>.jpg` (list thumbnail) |
| Crop  | 0x03 | `queue.json` item `crop` (transformation JSON, not an SD file) |

See `include/frame_config.h` for the full opcode + UUID table.

## Notes carried from 04

- Render runs on a dedicated FreeRTOS task; `lcd_chkstatus()` yields so the ~31s waveform doesn't
  starve `loop()`. Chunked `GetQueue` (0x2B) bypasses the ~600 B GATT cap. BLE advertises ~1s at boot
  (boot render is async on the task).

## Flash

Use `frame.sh` from plink root. Select `05-crop-cache`. Long-press SW2 during `Connecting......`.
Note: the first boot after flashing re-renders once (NVS `last_render` not yet set), then power-cycles
skip.
