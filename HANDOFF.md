# Handoff

## Goal
Build in-app Tailscale setup so users connect their Pi frame to their own Tailscale account from the iOS app (no terminal auth required), exposed as a selectable frame in the iOS Settings tab.

## Current State
Implementation complete, builds clean (exit 0), **not yet tested on real hardware**. Pi endpoints added to webserver. iOS UI wired. Tailscale installs silently during Pi setup; auth happens entirely in-app. No commits made yet in either repo.

## Files in Flight
`webserver_new.py` — two new Tailscale API routes  
`pi-scripts/setup-local.sh` — tailscale install only, no auth prompt  
`pi-scripts/setup-remote.sh` — same; removed interactive Tailscale block + TS_IP from final output  
`/Users/shoaibahmed/code/personal/Plink/Plink/Networking/FrameClient.swift` — tailscaleConnect() + tailscaleStatus() + response structs  
`/Users/shoaibahmed/code/personal/Plink/Plink/Views/Tabs/TuneTab.swift` — renamed TuneTab→SettingsTab, added TailscaleSection + TailscaleSetupSheet  
`/Users/shoaibahmed/code/personal/Plink/Plink/PiLinkApp.swift` — tab label "Tune"→"Settings"

## Changed
- **`webserver_new.py`**: `import re` added. `POST /api/tailscale/connect` — checks if already connected via `tailscale ip -4`, else pkills any existing `tailscale up`, starts fresh in bg logging to `/tmp/tailscale-auth.log`, polls up to 20s for auth URL, returns `{state:"auth_required", auth_url}` or `{state:"running", ip}`. `GET /api/tailscale/status` — returns `{state, ip}` via `tailscale ip -4`.
- **`setup-local.sh`**: Replaced 35-line interactive Tailscale block with single silent install step.
- **`setup-remote.sh`**: Removed entire interactive Tailscale prompt + auth flow + TS_IP from final output.
- **`FrameClient.swift`**: `tailscaleConnect()` (POST, actionSession 90s), `tailscaleStatus()` (GET), `TailscaleConnectResponse` / `TailscaleStatusResponse` structs.
- **`TuneTab.swift`**: Struct → `SettingsTab`, nav title + tab → "Settings". `TailscaleSection`: connected state shows full `http://100.x.x.x` URL, checkmark when active frame, `person.crop.circle` icon opens `login.tailscale.com/admin` in browser; tap row activates that frame. Not-connected state shows "Connect Tailscale" button. `TailscaleSetupSheet`: idle→connecting→waitingAuth→polling→done; polls `/api/tailscale/status` every 3s; on success inserts new `Frame(name: "<current> (Remote)", baseURL: "http://<ip>")` into SwiftData and activates it.
- **`ISSUES.md`** (pi-ink): `[Tailscale]` → "Fix implemented, pending test".

## Failed Attempts
None.

## Next Step
Deploy `webserver_new.py` to Pi (`./push.sh` or manual scp) and test end-to-end: Settings → Connect Tailscale → auth URL appears in sheet → authorize in browser → app detects Tailscale IP → new frame appears and is selected. Key risks to watch: `sudo tailscale up` permission from Flask process (Pi runs webserver as root on port 80 so likely fine), auth URL appearing in stdout vs stderr (Popen merges both to log file via `stderr=subprocess.STDOUT`), and duplicate frame creation if user runs connect twice.
