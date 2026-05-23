# Handoff

## Goal
Tailscale disconnect reliability and auth UX polish.

## Current State
- Disconnect on Pi just `tailscale logout` (no `systemctl disable --now`) — HTTP response completes cleanly
- iOS disconnect has 5s timeout (was 90s)
- Auto-connects after auth without confirmation dialog
- Auto-selects next frame after disconnect with toast
- `tailscale://` deep link preferred over Safari (stays logged in in app)
- All pushed to both repos; Pi deployed via push.sh
- Full disconnect→auto-select→reconnect flow untested on hardware

## Files in Flight
- `webserver_new.py` — disconnect endpoint (no tailscaled kill); deployed to Pi
- `Plink/Views/Tabs/SettingsTab.swift` — auth deep link, auto-connect, auto-select
- `Plink/Networking/FrameClient.swift` — 5s disconnect timeout
- `Plink/Info.plist` — `LSApplicationQueriesSchemes` for `tailscale://`

## Changed
- **Disconnect (Pi)**: removed `systemctl disable --now tailscaled` — just `tailscale logout` so response completes, tailscaled stays running for quick reconnect
- **Disconnect timeout (iOS)**: `tailscaleDisconnect` uses `URLSession.shared` with 5s timeout instead of `actionSession` (90s)
- **Auto-connect (iOS)**: removed "Switch to Remote Frame?" alert — auto-connects when reachable after auth
- **Auto-select (iOS)**: after disconnect, activates next frame with toast; if none, "No frames available" toast
- **Auth deep link (iOS)**: `tailscale://` URL scheme if app installed (avoids re-login); falls back to Safari
- **Info.plist**: added `LSApplicationQueriesSchemes` with `tailscale` for `canOpenURL` check

## Failed Attempts
- `.universalLinksOnly: true` for auth URL — Tailscale app doesn't register Universal Links for `login.tailscale.com`; replaced with `tailscale://` URL scheme
- `systemctl disable --now tailscaled` during disconnect — kills TCP connection mid-response, hangs iOS request for 90s

## Next Step
Test full disconnect→auto-select→reconnect flow on hardware. Verify `tailscale://` opens Tailscale app. Verify auto-connect after auth skips confirmation dialog.
