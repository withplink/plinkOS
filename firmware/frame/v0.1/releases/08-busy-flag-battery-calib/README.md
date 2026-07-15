# Release 08: BLE busy-flag detection, battery ADC recalibration, NimBLE migration

**Status:** Stable — hardware-validated 2026-07-15 (two-device busy-detection test on iPad +
iPhone; battery calibration validated against a multi-hour soak test, 94%→89% over 2h51m,
~1.75%/hr, smooth). Builds on 07-telemetry-perf-reset.

## What's new vs 07-telemetry-perf-reset

- **BLE single-connection-slot busy-flag** (plink-ios#52) — the frame's one GATT connection slot
  silently occupying meant a second phone trying to connect just hung in `.connecting` forever,
  with no error, no timeout, no explanation. Firmware now fires brief periodic non-connectable
  advertising bursts (`kBusyBurstIntervalMs=10s`, `kBusyBurstDurationMs=400ms`) while connected,
  carrying a 1-byte busy flag in manufacturer data (company ID `0xFFFF`, byte[2]==1). Bursts only
  fire when idle — both between asset-write transfers (`gBleBuffer`/`gStreamKind`) and with a
  1.5s quiet window since the last GetQueue/GetAsset/GetChunk read-back step
  (`gLastAssetActivityMs`) — an earlier version without the read-back quiet-gate corrupted a live
  GetQueue decode on hardware. Busy bursts don't carry scan-response data (spec: only
  `ADV_IND`/`ADV_SCAN_IND` can, not `ADV_NONCONN_IND`). `onDisconnect` explicitly reapplies
  connectable advertising so a stale non-connectable config can never block the next phone.
  App-side: `didDiscover` recognizes the busy flag and surfaces a distinct "frame busy" state
  instead of hanging — see plink-ios's own release notes for the app-side half.
  - First attempt (continuous non-connectable advertising while connected) was reverted earlier
    2026-07-15 — caused radio contention on this single-antenna chip (missed connection events,
    corrupted chunked reads). This periodic-burst + quiet-gated version is the validated fix.
- **Battery ADC recalibration + boot-settle** (carried over from main, previously uncommitted to
  a release) — `readBatterySense()` discards reads during a ~4s boot-settle window, takes a
  median of 9 samples via `analogReadMilliVolts()` (eFuse-calibrated) instead of a single-shot
  `analogRead()`/4095*3.3 (the old math under-read the pin by ~9.5%). `kBatteryDividerFactor`
  recalibrated 0.1688 → 0.1712 against the corrected math.
- **NimBLE-Arduino migration** — replaced the classic ESP32 BLE Arduino (Bluedroid) library.
  Bluedroid's `BLEAdvertising` couldn't keep advertising through an active connection (needed for
  the busy-flag feature above) and was also silently failing to start in some configs under the
  old library, independent of that feature.

## Known limitations

- Busy-burst timing (10s interval, 400ms duration, 1.5s read-back quiet gate) is a first-pass
  tuning, not exhaustively load-tested under heavy simultaneous queue/asset traffic.
- VBUS/charging detection still unwired — unchanged from 07, tracked as plinkOS#47 (v0.2).
