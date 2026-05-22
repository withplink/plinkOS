# Handoff

## Goal
Fix setup-remote.sh so all install steps actually run on the Pi — not silently on the Mac.

## Current State
- All fixes applied locally in `pi-scripts/setup-remote.sh` — NOT yet committed or pushed
- User has NOT re-tested yet — needs fresh install run after push to confirm

## Files in Flight
- `pi-scripts/setup-remote.sh` — all fixes live here, unstaged

## Changed
- `eval "$@"` → `"$@"` in both branches of `step()`: fixes pipe/`&&`/`||` operators running locally
- Multi-command steps wrapped in bash functions (`_step_patch_drivers`, `_step_deploy`, `_step_install_scripts`, `_step_configure_services`) — fixes lag between ✓ and next section (previously `&&`-chained steps only ran first command inside `step()`, rest ran bare after ✓ printed)
- Tailscale removed from pre-reboot phases — now prompted at end ("Set up Tailscale? [y/N]"), installs + runs `tailscale up`, shows browser login URL, waits for auth. No auth key needed.
- WiFi power save: removed `&& systemctl restart NetworkManager` — drops own SSH connection
- Log hint: log is local at `/tmp/plink-setup.log`

## Failed Attempts
- Previous session tried to fix individual steps without finding root cause
- User ran `curl | bash` from GitHub (old code) for test run — confirmed failures from log

## Next Step
Commit and push `pi-scripts/setup-remote.sh`, then ask user to re-run install after resetting Pi with `./pi-scripts/reset.sh`.

Commit command:
```bash
git add pi-scripts/setup-remote.sh HANDOFF.md && git commit -m "fix: wrap multi-cmd steps in functions, move Tailscale to end with browser login"
```
