# Release 12: App-instance identity, Manage Paired Devices, pairing-window advertising

**Status:** Stable — validated 2026-07-29 across multiple devices (iPhone + iPad). Builds on
11-stream-fix-version-handshake.

## What's new vs 11-stream-fix-version-handshake

- **App-instance identity layer** (plinkOS#48) — closes the gap where "Forget This Device" or an
  app reinstall/uninstall couldn't actually revoke a frame's trust in a phone, since iOS's BLE
  bond (IRK/LTK) lives entirely outside app control. The app now generates a UUID once per install
  (`UserDefaults`, not Keychain — wiped on uninstall by design) and sends it once per connection
  via `kBleIdentify` (0x30). The frame remembers `{BLE address → app-instance UUID}` per bonded
  device (NVS namespace `"pairing"`, `kMaxPairedDevices = 3`). A mismatch (reinstall, or a revoked-
  then-restored mapping) deletes the BLE bond outright, forcing the next connection through the
  pairing window.
- **New-device pairing window** — a not-yet-bonded device can only connect within a 2-minute
  window after boot, or after `kBleOpenPairing` (0x2E) is sent by an already-connected device
  ("Pair a new device" in Settings). `kBleForgetMe` (0x2F) lets a phone self-unbind when the user
  deletes that frame from the app.
- **Manage Paired Devices** — `kBleGetPairedDevices` (0x31) lists every trusted device (address,
  name, "is this the current connection"); `kBleRevokeDevice` (0x32) deletes a specific device's
  bond + mapping, disconnecting it immediately if it's the live connection.
- **Pairing-window state now advertised** — the connectable advertisement's manufacturer-data
  payload gains a 4th byte (`pairingWindowOpen()`), refreshed on window open/close/rename/
  disconnect. Lets the app's "Add Frame" scanner show "Not accepting new pairings" upfront for a
  closed window instead of letting the user tap through to a connection that's guaranteed to be
  rejected.
- **`kBleStatusIdentifyOk` (0x13)** — explicit ack for a successful identify (enroll or match).
  Closes a real security gap found during testing: without this ack, the app used to treat the
  connection as fully live as soon as the GATT link came up, before the frame had actually
  confirmed the app-instance id — a revoked/mismatched device had one full BLE round trip's worth
  of window to read real queue/photo data before the mismatch check kicked it off. The app now
  gates all data reads behind this ack.
- **Serial `wipe` command** now also clears BLE bonds (`NimBLEDevice::deleteAllBonds()`) and the
  paired-device table — factory reset previously left every prior phone's trust intact.

## App-side fixes found during this validation pass (plink-ios)

- A `didFailToConnect`/`didDisconnectPeripheral` race where a fast frame-side reject (pairing
  window closed) could land via either delegate callback depending on timing — only one was
  counted toward the stale-bond-loop detector, silently missing the alert in some cases.
  Consolidated into one counter fed by both paths, plus the 15s connect-timeout path.
  timing-order race (`AppState`'s independent poll timer could read real data via the same
  op-lock before the identify-awaiting Task had even started) closed with a synchronous gate set
  the instant characteristics finish discovery.
- `identifyOkPending` race — the frame answers identify in single-digit ms, fast enough that the
  `kBleStatusIdentifyOk` notify could land before the app's continuation was registered, silently
  dropped, stalling the connect flow for the full 10s timeout and forcing an unnecessary
  disconnect + re-pair even on a clean enrollment. Fixed with the same "landed before the waiter"
  buffering pattern already used elsewhere in this client (`assetReadyPending`).
- Repair-alert message now distinguishes "stale bond, forget in Settings" from "pairing window
  closed, restart the frame or pair from another device" — previously always said "forget in
  Settings" even when there was nothing to forget.
- Dismissing the repair alert now actually re-arms retry (previously required a full app
  relaunch even after the user had already fixed the underlying issue).

## Known limitations

- Just Works bonding has no MITM protection (accepted risk, no display/keyboard on the frame).
- iOS's own BLE auto-retry (stale LTK) can hammer the frame with rapid connect/reject cycles for
  a while after a revoke, independent of anything the app does — only "Forget This Device" in iOS
  Settings fully stops it. The app-side 3-strike detector stops the *app* from contributing to
  this, but can't reach into iOS's Bluetooth daemon.
- No public/documented iOS API exists to deep-link into system Bluetooth settings for a specific
  device — the repair alert names the device but can't jump straight to it.
- VBUS/charging detection unwired (plinkOS#47, v0.2).
