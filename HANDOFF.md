# Handoff

## Goal
Tailscale disconnect reliability and UX polish.

## Current State
- Disconnect no longer stops tailscaled — just `tailscale logout` — so HTTP response completes cleanly
- iOS has 5s timeout on disconnect request (was 90s)
- "Switch to Remote Frame?" confirm alert removed — auto-connects when reachable
- Auto-selects another frame after disconnect with toast ("Switched to...")
- Tailscale auth tries Universal Links first (Tailscale app), falls back to Safari
- Pi disconnect endpoint needs deploy via push.sh

## Files in Flight
- `webserver_new.py` — disconnect no longer kills tailscaled
- `Plink/Views/Tabs/SettingsTab.swift` — auto-connect, auto-select, Universal Links auth
- `Plink/Networking/FrameClient.swift` — 5s timeout on disconnect

## Changed
- **Disconnect (Pi)**: removed `systemctl disable --now tailscaled` — just `tailscale logout` so TCP response completes
- **Disconnect timeout (iOS)**: `tailscaleDisconnect` now uses `URLSession.shared` with 5s timeout instead of `actionSession` (90s)
- **Auto-connect (iOS)**: removed "Switch to Remote Frame?" alert — when frame is reachable via Tailscale after auth, connects automatically
- **Auto-select (iOS)**: after disconnect, if the TS frame was active, activates the next available frame with toast; if none, shows "No frames available" toast
- **Auth deep link (iOS)**: auth URL opens with `.universalLinksOnly: true` first — Tailscale app handles it if installed, else Safari

## Next Step
Run `push.sh` to deploy Pi changes, then test full Tailscale disconnect→auto-select→reconnect flow on hardware.
