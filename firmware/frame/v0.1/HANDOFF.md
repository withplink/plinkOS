# Frame v0.1 — HANDOFF

## Goal

**FrameTool-first v0.1.** Build full Plink-app feature parity inside the **FrameTool** prototype app
(BLE/ESP32), validate end-to-end on hardware, then migrate into the main Plink app (plink-ios#22).
See `docs/products/frame/v0.1/parity-gap-audit.md` and architecture build-strategy section.

## Build / flash workflow (IMPORTANT)

- User flashes **only via `frame.sh`** (plink root → execs `firmware/frame/v0.1/frame.sh`).
- `frame.sh` scans `releases/` (stable) + `staging/` (unvalidated, tagged `[TEMP]`).
- Build bins: `cd firmware/frame/v0.1 && ~/.local/bin/pio run` → `.pio/build/esp32-s3-devkitc-1/*.bin`.
- Validate on hardware **before** committing (build-verify alone is not enough).
- Promote when stable: `git mv staging/<name> releases/NN-<name>`, retitle README, commit.

## Current dev build: `staging/dev` (NOT YET STABLE)

Rolling unvalidated build on top of `releases/02-ble-sd`. Contains:
1. **Dimension-driven orientation** — `renderBmpFromSd` rotates portrait BMP (h>w) 90°CW; landscape
   (800×480) renders direct. ⚠️ see Bug #1 — the orientation *model* is wrong.
2. **Frame name on ESP** — NVS-persisted, READ+WRITE `BLE_NAME_CHAR_UUID` (`…0c2e`), name in
   scan-response; live re-advertise on rename (Bug #2 ✅ fixed). App writes name over BLE.
3. Render-pipeline timing logs.

## Uncommitted work (BOTH repos — nothing below is committed; persists on disk)

**plinkOS** (firmware): `src/main.cpp` (name-on-ESP: NVS + name char + `esp_ble_gap_set_device_name`),
`include/frame_config.h` (`BLE_NAME_CHAR_UUID`), `frame.sh` (staging support), `staging/dev/` (new).
Already committed+pushed: `dd85c81` orientation (rotation-from-dims), `e148b8d` timing logs.

**plink-ios** (FrameTool): modified `ContentView.swift`, `CropView.swift`, `FrameScanner.swift`,
`FrameStore.swift`, `Spectra6Ditherer.swift`; new `FrameConfigClient.swift`, `SettingsView.swift`.
Already committed+pushed (foundation/LA/bg): `814fa08`, `b4f56c1`, `bbd1abe`, `827bd4f`.
NOTE: the iOS **orientation** commit was denied earlier → orientation changes are part of this
uncommitted set, not yet on remote (firmware orientation `dd85c81` IS on remote — mismatch).

Both apps build clean (`xcodebuild FrameTool` + `pio run` both SUCCEED). Validate-first → not committed.

## What's built (feature → status)

| Feature | Built | Validated on HW |
|---|---|---|
| Discovery / pair / persistence (single frame) | ✅ | ✅ pairs, shows name |
| Signal flap fix (no allowDuplicates) | ✅ | ~ (no complaint; reverify) |
| Core send + render (regression) | ✅ | ✅ works |
| Orientation crop+dither+render | ✅ | ⚠️ renders but MODEL wrong (Bug #1) |
| Name on ESP (NVS + write char) | ✅ | ✅ NVS + live re-advertise (Bug #2 fixed) |
| Settings sheet (orientation, rename, unpair) | ✅ | ✅ mostly; rename hangs if frame off (Bug #5) |
| Live Activity (timer-estimate render bar) | ✅ | ✅ works, better than in-app bar |
| beginBackgroundTask send guard | ✅ | ✅ (earlier session) |

## BUGS FOUND THIS SESSION (block stable-03)

**#1 — Orientation model is wrong (DESIGN DECISION NEEDED).**
Current: firmware rotates by BMP dims, so a portrait-cropped image sent while app is in Landscape
mode renders **sideways**. Correct (Pi-plink) behavior: orientation = the frame's **physical mount**
(how it hangs); a mismatched-aspect image is **letterboxed (white bars), kept upright**, never
rotated sideways. Rethink: orientation should describe the mount, app crops/letterboxes to it, and
firmware renders upright relative to mount. Decide the model before reworking.

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
Two frames nearby (single-frame scope — fine for now); orientation render couldn't be judged clearly
(ambiguous test photos) — moot until Bug #1 redesign.

## Open design questions
- **Orientation model** (Bug #1) — mount-orientation + letterbox vs per-image rotation. Blocks orientation.

## Next steps (next session)
1. Resolve orientation model (Bug #1) — decide, then rework firmware render + app crop/letterbox.
   **This is the LAST remaining stable-03 blocker** — all other bugs (#2–#8) fixed + HW-validated.
2. iOS bugs #3/#4/#5/#6 (connection robustness) + #7 (render-bar drift) + #8 (LA update race) +
   #2 (name re-advertise, fw+iOS) — ✅ ALL DONE (HW-validated). Follow-up only: proactive idle-screen
   offline indicator (#3 liveness ping).
3. Re-run full checklist (`docs/products/frame/v0.1/parity-gap-audit.md` + this HANDOFF) on hardware.
4. When green: promote `staging/dev` → `releases/03-…`, commit firmware + iOS, bump root pointers.
   NOTE: `staging/dev/src` snapshot is STALE vs top-level `src/` (top-level is the build source +
   has all fixes); reconcile or rebuild staging from top-level before promoting.
5. Then remaining v0.1: battery (PARKED — needs battery-sense method: IP5306 I2C vs ADC pin), queue
   slice (fw#31 + ios#26 — needs BLE queue protocol design + SD layout).

## Reference
- Status bytes (`frame_config.h`): `0x00` Ready, `0x01` Receiving, `0x02` Rendering, `0xFF` Error.
- Transfer ~10s; render ~43–45s (Spectra 6, hardware-limited).
- Render is firmware-autonomous after COMMIT — phone can disconnect/suspend; image still lands.
