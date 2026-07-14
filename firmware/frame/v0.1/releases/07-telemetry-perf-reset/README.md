# Release 07: battery telemetry, BLE Info (model/uptime), indexed BMP transfer, factory reset

**Status:** Stable — hardware-validated 2026-07-14. Builds on 06-device-actions; bundles
everything shipped since then (battery/dithering work, the new Info characteristic, the
indexed-BMP asset format, and a serial factory-reset command).

## What's new vs 06-device-actions

- **Battery telemetry** (plink-ios#31, plinkOS#34) — resistor-divider ADC read on IO1
  (`kBatteryAdcWired`), calibrated divider factor (0.1688, from a real multimeter reading, not
  nominal resistor math). Reported over the existing `BLE_BATTERY_CHAR_UUID` (READ+NOTIFY,
  `{percent, flags}`), polled/republished every ~30s. VBUS/charging detection stays unwired
  (`kVbusAdcWired = false`) — no onboard charge-detect circuit on this board; tracked separately
  as plinkOS#47 (blocked on a hand-soldered VIN divider, v0.2).
- **BLE Info characteristic** (`BLE_INFO_CHAR_UUID`, new) — READ+NOTIFY,
  `[uptimeSec:4 LE][modelLen:1][model][featureFlags:1]`. Reports firmware identity (model string,
  uptime) that had no prior BLE opcode — the app used to hardcode these nil for BLE frames.
  Republished on the same ~30s cadence as battery.
- **4bpp indexed BMP asset format** (plinkOS#45) — `parseBmpHeader`/`renderBmpFromSd` now accept
  `bpp==4` alongside the existing 24-bit path: reads the BMP's color table, builds a 16-entry
  index→token lookup once per render (reusing `nearestSpectra6Color` ≤16 times instead of once
  per pixel), and decodes packed nibbles. Gated by `featureFlags` bit0 in the Info payload — the
  app only sends indexed BMPs to firmware that advertises support, with automatic fallback to
  24-bit otherwise. Hardware-validated: 192,118 bytes vs the prior 1,152,054 (~6x smaller); send
  time ~40s → ~20s, render ~45s → ~30s.
- **Serial `wipe` command** — factory-reset over USB serial (`frame.sh` option 4): empties
  queue.json and deletes every file under `/img`, `/orig`, `/thumb`. Same handler
  (`handleClear()`) the BLE `kBleClear` (0x2A) op already ran — this just exposes it over serial
  too, for dev/support use without needing the app. Irreversible; `frame.sh` requires typing
  `wipe` to confirm before sending it.

## Notes carried from 04/05/06

- Render on a dedicated FreeRTOS task (`lcd_chkstatus` yields). Chunked `GetQueue` (0x2B).
  Per-item crop persisted in queue.json (`kAssetCrop`). Boot-render skip via NVS `last_render`.
- `kBleClearGhost` (0x2C) / `kBleReboot` (0x2D) device actions, unchanged from 06.

## Flash

Use `frame.sh` from plink root. Select `07-telemetry-perf-reset`. Long-press SW2 during
`Connecting......`.
