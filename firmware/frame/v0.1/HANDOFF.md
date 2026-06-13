# Frame v0.1 — HANDOFF

## Goal

**FrameTool-first v0.1.** Build full Plink-app feature parity inside the **FrameTool** prototype app
(BLE/ESP32), validate end-to-end on hardware, then migrate into the main Plink app (plink-ios#22).
See `docs/products/frame/v0.1/parity-gap-audit.md` and architecture build-strategy section.

## Build / flash workflow (IMPORTANT)

- User flashes **only via `frame.sh`** (plink root → execs `firmware/frame/v0.1/frame.sh`).
- `frame.sh` scans `releases/` (stable) + `staging/` (unvalidated, tagged `[TEMP]`) and flashes the
  selected dir's `bins/`.
- ⚠️ **CRITICAL GOTCHA:** `pio run` writes `.pio/build/`, but `frame.sh` flashes
  `staging/dev/bins/`. **Nothing auto-syncs them.** Editing `src/` + running `pio run` + flashing
  silently flashes STALE bins (this cost a whole session — orientation + NVS-log edits never reached
  the frame; symptom = expected new Serial logs simply absent at boot).
- **ALWAYS build the dev firmware with `./build-dev.sh`** (runs `pio run` + copies fresh bins AND
  the src snapshot into `staging/dev/`). Then `frame.sh` → Flash → dev. Never `pio run` alone before
  a staging flash.
- Validate on hardware **before** committing (build-verify alone is not enough).
- Promote when stable: `git mv staging/<name> releases/NN-<name>`, retitle README, commit.

## Current stable build: `releases/03-ble-name` (STABLE — promoted 2026-06-13)

Promoted from `staging/dev` after stable-03 (all bugs #1–#8 fixed + HW-validated). On top of
`releases/02-ble-sd`. Contains:
1. **Frame name on ESP** — NVS-persisted, READ+WRITE `BLE_NAME_CHAR_UUID` (`…0c2e`), name in
   scan-response; live re-advertise on rename (Bug #2). App writes name over BLE.
2. **App-side orientation** — firmware rotation removed; renders panel-native 800×480 directly
   (Bug #1). `staging/` is now empty; new dev work recreates `staging/dev` via `build-dev.sh`.

## State — everything committed + pushed

- All this-session work committed + pushed (plink-ios + plinkOS), root submodule pointers bumped.
- Stable-03 firmware lives in `releases/03-ble-name` (this commit promotes it).

Both apps build clean (`xcodebuild FrameTool` + `pio run` both SUCCEED). Validate-first → not committed.

## What's built (feature → status)

| Feature | Built | Validated on HW |
|---|---|---|
| Discovery / pair / persistence (single frame) | ✅ | ✅ pairs, shows name |
| Signal flap fix (no allowDuplicates) | ✅ | ~ (no complaint; reverify) |
| Core send + render (regression) | ✅ | ✅ works |
| Orientation (app-side rotation, 3 mounts) | ✅ | ✅ all 3 mounts upright (Bug #1 fixed) |
| Name on ESP (NVS + write char) | ✅ | ✅ NVS + live re-advertise (Bug #2 fixed) |
| Settings sheet (orientation, rename, unpair) | ✅ | ✅ mostly; rename hangs if frame off (Bug #5) |
| Live Activity (timer-estimate render bar) | ✅ | ✅ works, better than in-app bar |
| beginBackgroundTask send guard | ✅ | ✅ (earlier session) |

## BUGS FOUND THIS SESSION (block stable-03)

**#1 — Orientation model. ✅ FIXED (HW-validated).** Resolved via the **app-side rotation** model:
orientation = per-frame physical MOUNT (`landscape` / `portraitLeft` / `portraitRight`). App
crops-to-fill the visible canvas, dithers, and BAKES the mount rotation into a panel-native 800×480
BMP; firmware renders it directly (rotation + rotation PSRAM buffer removed). Both portrait mounts
are 480×800 visible → indistinguishable by dims, so rotation MUST live app-side. Validated: all three
mounts render upright. CONSEQUENCE (logged on plinkOS#31): stored BMPs are orientation-locked — a
mount change won't re-rotate already-stored queue images; decide re-push vs firmware-rotate when the
queue is designed.

**#2 — Frame name live re-advertise fails. ✅ FIXED (HW-validated).** Two-part fix, both required:
- **Firmware** (`main.cpp`): build adv + scan-response explicitly from `gFrameName` via
  `applyAdvertising()` (name in scan response) instead of BLEAdvertising's default device-name
  include, which cached the init-time name so `startAdvertising()` replayed stale bytes. Rebuilt in
  `NameCallbacks` on rename → app disconnects → `onDisconnect`→`startAdvertising()` sends new name.
  (nRF Connect confirmed the firmware was already broadcasting the fresh name.)
- **iOS** (`FrameScanner.swift`): prefer `CBAdvertisementDataLocalNameKey` (live scan-response name)
  over `peripheral.name` (sticky bluetoothd cache, survives app delete); scan with
  `allowDuplicates` so the scan-response packet arrives + refreshes the name (RSSI frozen → no flap).
  Without this it took a second unpair to pick up the new name.
Result: rename → single unpair → new name in discovery, no reboot, no flap.

**#3 — Frame-off not detected. ✅ FIXED (HW-validated).** Upload-stuck-on-connecting killed by the
15s scan→connect→discover timeout in `BLEFrameClient` (shared with #4). NOTE: full proactive
offline indicator on the idle screen (liveness ping) deferred as follow-up — timeout removes the
dead-end, idle screen still doesn't pre-warn frame-offline.

**#4 — Scan/connect has no timeout. ✅ FIXED (HW-validated).** `BLEFrameClient` arms a 15s
`connectTimer` in `send()`; fires while still `.scanning/.connecting/.discovering` → stops scan,
cancels conn, `fail("Couldn't reach the frame. Make sure it's powered on and nearby.")`. Cleared
once characteristics resolve (transfer start), on fail, and in reset.

**#5 — Rename has no timeout. ✅ FIXED (HW-validated).** `FrameConfigClient.setName` arms a 15s
`timeoutTimer`; fires → `fail(.notReachable)`. Cleared in succeed/fail.

**#6 — No retry on send failure. ✅ FIXED (HW-validated).** Error sheet (`ContentView`) now shows
"Retry" (re-sends stored `flow.pendingBmp`, no re-crop/dither) + "Cancel". `AppFlow.pendingBmp`
always holds the most recent send attempt.

**#7 — In-app render bar drifts on background. ✅ FIXED (HW-validated).** Render bar now derived
from wall-clock elapsed since `BLEFrameClient.renderStartedAt` (set at COMMIT) instead of a
foreground-only per-tick accumulator, so suspended seconds count and it no longer snaps to done
early. Estimate 40→45s to match Live Activity.

**#8 — Live Activity stuck at "Sending photo… 100%", never flips to Rendering. ✅ FIXED (HW-validated).** Lock/minimise right
as send completes → LA frozen on `.sending` phase, progress 1.0 (orange bar full, "Sending photo…").
ROOT CAUSE: in `BLEFrameClient.sendNextChunk` the final chunk fires BOTH `liveActivity.updateTransfer(1.0)`
and (right after, at COMMIT) `liveActivity.beginRender()`. Each spawns an **independent unordered**
`Task { await activity.update(...) }` (see `FrameLiveActivity.swift`). No ordering guarantee → the
`.rendering` update can land first, then the trailing `.sending(1.0)` update clobbers it back. Locking
freezes whatever landed last. FIX OPTIONS: (a) skip `updateTransfer` on the final chunk
(`offset >= count`) since `beginRender` immediately supersedes it, and/or (b) serialize all LA updates
through one ordered actor/task queue so a later call can't be overtaken by an earlier one. NOTE: the
"allow Live Activities from FrameTool?" lock-screen prompt is iOS periodic re-consent, not a bug.
FIX SHIPPED: (a) skip final-chunk `updateTransfer`; (b) all LA mutations serialized through an
ordered `enqueue()` (FIFO) in `FrameLiveActivityController`.

## Validated OK
Core send/render; Live Activity render-during-lock (clears on reopen); force-kill during render →
returns to "choose photo" (expected — frame renders autonomously); Disconnected error dialog shows.

## Still untested
Two frames nearby (single-frame scope — fine for now).

## Open design questions
- (none blocking stable-03 — all resolved)
- Queue-era: orientation vs stored images — re-push from phone vs firmware-rotate (logged plinkOS#31).

## Next steps (next session)
**Stable-03 DONE + promoted to `releases/03-ble-name`.** Final checklist pass was waived (each bug
validated individually this session).
1. Remaining v0.1 P0: queue slice (fw#31 + ios#26 — needs BLE queue protocol + SD layout; see the
   orientation-lock note on #31), then battery (PARKED — battery-sense method TBD: IP5306 I2C vs ADC).
2. Follow-ups (non-blocking): proactive idle-screen offline indicator (#3 liveness ping); app reads
   name char on connect to reconcile cached name vs frame NVS.
3. Dev-build reminder: `build-dev.sh` rebuilds top-level `src/` + syncs into a fresh `staging/dev`
   (run before flashing a staging build — avoids the stale-bins trap).

## Reference
- Status bytes (`frame_config.h`): `0x00` Ready, `0x01` Receiving, `0x02` Rendering, `0xFF` Error.
- Transfer ~10s; render ~43–45s (Spectra 6, hardware-limited).
- Render is firmware-autonomous after COMMIT — phone can disconnect/suspend; image still lands.
