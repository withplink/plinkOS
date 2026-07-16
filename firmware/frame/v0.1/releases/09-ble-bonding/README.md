# Release 09: BLE bonding/encryption (Just-Works)

**Status:** Stable — hardware-validated 2026-07-16 (pairing prompt, `BLE: bonding complete
(encrypted=1)`, full queue read + send + render cycle over the encrypted link, silent reconnect
after re-pair). Builds on 08-busy-flag-battery-calib.

## What's new vs 08-busy-flag-battery-calib

- **BLE bonding/encryption** (plink-ios#36 / plinkOS#38) — the GATT service previously had zero
  auth: any device in range could connect and read every stored photo, wipe the gallery, replace
  the displayed image, rename the frame, or reboot it. `NimBLEDevice::setSecurityAuth(bonding=true,
  mitm=false, sc=true)` + `setSecurityIOCap(BLE_HS_IO_NO_INPUT_OUTPUT)` (Just Works — the frame has
  no display/keyboard for a passkey). Every characteristic now carries `READ_ENC`/`WRITE_ENC`, so
  any access forces the bonding handshake on first connect from a new device; bonded devices
  reconnect silently. `ServerCallbacks::onAuthenticationComplete` logs bond/encryption state.
- App-side (plink-ios): `BLEError.pairingFailed` + `CBATTError` → `BLEError` mapping, so a
  declined/interrupted pairing surfaces as an actionable message instead of a misleading generic
  failure ("Bad queue payload", raw system-worded "Write failed: ...").

## Known limitations

- **Just Works has no MITM protection** — stops passive eavesdropping and casual walk-by
  connections, but not an attacker who deliberately targets the frame and simply accepts the
  pairing prompt from outside BLE range (no ownership check, no PIN). Follow-up filed as
  plinkOS#48 (gate bonding acceptance to a time/button-triggered pairing window).
- `CONFIG_BT_NIMBLE_MAX_BONDS` defaults to 3 — up to 3 devices can stay bonded simultaneously
  (only one connected at a time; see 08's busy-flag feature for the connection-slot constraint).
- VBUS/charging detection still unwired — unchanged, tracked as plinkOS#47 (v0.2).
