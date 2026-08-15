# Release 13: App-instance mismatch no longer deletes the live BLE bond

**Status:** Stable — validated 2026-08-15 (repeated restart+delete+forget+reinstall cycles on
iPhone). Builds on 12-ble-app-instance-identity.

## Bug

After 12-ble-app-instance-identity shipped, a delete-app + forget-BLE + reinstall cycle would
sometimes get permanently stuck: the app kept showing "This device isn't recognized by the frame
anymore. In Settings, forget ... then reconnect" even after doing exactly that, requiring a frame
power cycle to recover.

## Root cause

The app-instance mismatch handler (`kBleIdentify`, triggered on reinstall since the app-instance
UUID is regenerated per install) called `NimBLEDevice::deleteBond(peerAddr)` on detecting a
mismatch. But `kBleIdentify` only ever arrives over an already-encrypted link — meaning the LTK
just used to get there is valid and current on *both* sides at that exact moment (often freshly
re-negotiated seconds earlier, e.g. after the phone forgot and re-paired). Deleting it there
destroyed a bond the phone still trusted (it just used it), while the frame no longer had a copy.
Every reconnect after that failed auth with `CBErrorDomain code=14 "Peer removed pairing
information"`, and — since iOS believed it was already bonded — never re-initiated a fresh Just
Works pairing to recover on its own. Only an explicit iOS-side forget could break the deadlock,
and if that forget happened outside the frame's 2-minute pairing window, even that failed until a
power cycle reopened the window.

Confirmed on hardware: `onConnect` logs showed `isBonded=1→0` flip exactly across the
`deleteBond()` call between consecutive attempts, and a pairing-window-open counter-example (bug
still reproduced with `pairingWindowOpen=1` throughout) ruled out the window itself as the cause.

## Fix

`main.cpp`, app-instance mismatch branch: removed the `NimBLEDevice::deleteBond(peerAddr)` call.
The mismatch is app-identity bookkeeping (`gPairedDevices[idx].appId` stale) — not evidence the
BLE-level pairing is invalid. Now only the stale `gPairedDevices` slot is cleared (`memset` +
`savePairedDevices()`); the actual LTK/bond is left alone. The next `kBleIdentify` from the
(now-current) app instance just re-enrolls into the cleared slot — no restart, no second
forget-and-retry needed.

`kBleRevokeDevice` (explicit "forget this device" user action) is unaffected — deleting the bond
there is correct, that's a deliberate revocation, not an automatic mismatch cleanup.

## Known follow-ups (not in this release)

- iOS-side: after an OS-level BLE forget, the app's `needsRepairMessage` state doesn't reliably
  clear and retry on next launch — sometimes needs delete+reinstall to recover. Separate bug,
  client-side, not yet root-caused.
- iOS-side: toggling Bluetooth back on after the "Bluetooth Denied" alert doesn't self-heal the
  "Frame Offline" badge — requires relaunching the app. Confirmed 2026-08-15, not yet fixed.
- Fresh install with BLE permission denied: Plink frame silently doesn't appear in the Add Frame
  scanner, no warning shown. Confirmed 2026-08-15, not yet fixed.
