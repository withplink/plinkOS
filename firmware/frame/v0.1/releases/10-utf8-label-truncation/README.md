# Release 10: UTF-8-safe label truncation

**Status:** Stable — hardware-validated 2026-07-27 (emoji-heavy label added/renamed via app, read
back on frame with no "Bad queue payload" error). Builds on 09-ble-bonding.

## What's new vs 09-ble-bonding

- **UTF-8-safe label truncation** (plink-ios#39 / plinkOS#41) — `kBleAdd`/`kBleRename` label copies
  previously capped at a raw byte count, which could slice a multi-byte UTF-8 character (emoji,
  accented text) in half mid-sequence, corrupting the stored label and the queue JSON payload on
  next read. New `utf8SafeLen()` helper walks back over trailing continuation bytes / an incomplete
  lead byte before applying the cap — deliberately conservative (may drop one complete trailing
  character rather than risk keeping a partial one).
- App-side (plink-ios): matching `truncatedUTF8(_:maxBytes:)` retry-shrink helper applied in
  `buildAdd` and `rename()` (rename previously had zero truncation on the Swift side either).

## Known limitations

Same as 09-ble-bonding — Just Works bonding has no MITM protection (plinkOS#48 follow-up), VBUS/
charging detection unwired (plinkOS#47, v0.2).
