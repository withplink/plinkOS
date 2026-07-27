# Release 11: Stream overflow recovery + fw/proto version handshake

**Status:** Stable — validated 2026-07-27. Builds on 10-utf8-label-truncation.

## What's new vs 10-utf8-label-truncation

- **Thumbnail leak on remove** (plinkOS#40) — `deleteItemFiles` now also removes `/thumb/<id>.jpg`
  (previously only `/img` and `/orig` were cleaned up on remove; the thumbnail was stranded until
  the next add/boot prune). Fixed the stale comment on `pruneOrphanFiles` claiming it ran on
  remove — it only ever ran on add + boot; remove is handled directly by `deleteItemFiles` instead.
- **Version/capability handshake** (plinkOS#37) — the Info characteristic's payload gains two
  trailing bytes: `fwVersion` (matches this release's number) and `protoVersion` (bumps only when
  the BLE opcode/characteristic set itself changes). Same backward-compatible trailing-append
  pattern as `featureFlags` (plinkOS#45) — older app builds that only read the earlier prefix are
  unaffected. App-side: `BLEQueueClient.fwVersion`/`protoVersion` parse these, reset on disconnect.
- **Stream overflow no longer poisons the connection** (plinkOS#44) — `ImageDataCallbacks::onWrite`
  previously left the buffer and `gStreamKind` alive after an overflow, so every subsequent chunk
  re-tripped the same check until the app sent ABORT. Now frees the buffer and resets state
  immediately, making the failure terminal. App-side: an 0xFF status notify during an active stream
  now aborts locally instead of continuing to pump the rest of the asset into a dead stream.

## Known limitations

Same as prior releases — Just Works bonding has no MITM protection (plinkOS#48 follow-up), VBUS/
charging detection unwired (plinkOS#47, v0.2).
