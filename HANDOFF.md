# Handoff

## Goal

Ship Tailscale VPN support into the Pi setup flow, and clean up all script naming/presentation.

## Current State

- Tailscale: implemented in `setup.sh` (prompt), `setup-remote.sh` (SSH phase), `setup-local.sh` (local phase) — **not tested on real Pi yet**
- Script renames: complete, all internal references updated
- Script prettification: `push.sh` and `setup-local.sh` now match the spinner/section/color style of `setup-remote.sh` and `reset.sh`
- ISSUES.md: Tailscale issue marked "Fix implemented, pending test"

## Files in Flight

- `pi-scripts/setup-remote.sh` — main SSH orchestration script; Tailscale phase added (phases 5/6 + 6/6)
- `pi-scripts/setup-local.sh` — on-Pi install script; Tailscale section added at end
- `pi-scripts/setup.sh` — entry point; Tailscale prompt + auth key prompt added
- `push.sh` — renamed from `deploy.sh`; prettified with spinner/section UI
- `ISSUES.md` — Tailscale status = "Fix implemented, pending test"

## Changed

- **Tailscale flow added to `setup.sh`**: prompts "Set up Tailscale VPN? [y/N]", then optional auth key (links to tailscale.com/admin/settings/keys). Exports `SETUP_TAILSCALE` + `TAILSCALE_AUTH_KEY`.
- **Tailscale phase in `setup-remote.sh`**: installs via official install.sh. If auth key → `tailscale up --auth-key` non-interactively. If no key → runs `tailscale up` in background, captures login URL from `/tmp/tailscale-auth.log`, displays it, polls `tailscale ip` until authenticated. Final output shows Tailscale IP as third access URL.
- **Tailscale in `setup-local.sh`**: same env-var gate (`SETUP_TAILSCALE=y`).
- **Script renames via `git mv`**: `first-boot-setup.sh→setup-remote.sh`, `install.sh→setup-local.sh`, `clean-pi.sh→reset.sh`, `deploy.sh→push.sh`. All references updated in `setup.sh`, `CLAUDE.md`, `README.md`, `HANDOFF.md`.
- **`push.sh` prettified**: spinner/section/divider/log style matching other scripts.
- **`setup-local.sh` prettified**: full 6-phase section/step/spinner UI, same pattern.

## Failed Attempts

None.

## Next Step

Test the full Tailscale flow on the actual Pi: run `bash pi-scripts/setup.sh`, answer `y` to Tailscale, skip auth key (use browser flow), verify the login URL appears, authenticate, confirm Tailscale IP shows in final output. If `nohup sudo tailscale up > /tmp/tailscale-auth.log 2>&1 &` doesn't flush the URL fast enough (sleep 4 may be too short), increase the sleep or poll the log file until the URL appears.
