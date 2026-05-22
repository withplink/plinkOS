## [PiStability] Pi stops working and requires manual restart

**Repro:** Not described. Observed 2026-05-19 ~20:30 IST — both pi.local and static IP (192.168.1.50) unreachable. Manual restart restored access.

**Root cause:** Not investigated. Hardware watchdog (1min timeout) triggered reboot. Likely OOM during image processing or kernel freeze. Journal was not persistent at time of incident — no pre-reboot logs available. Persistent journal now enabled.

**Status:** Not investigated.

---

## [WiFi] Validate WiFi connection logic across all scenarios — no loopholes

**Repro:** Not described. Need to audit how the Pi connects to WiFi in different scenarios (initial setup, AP mode, client mode, network loss, Tailscale, etc.) and ensure there are no edge cases or loopholes.

**Root cause:** Not investigated.

**Status:** Not investigated.

---

## [Tailscale] Add Tailscale installation and proper setup to initial Pi setup

**Repro:** Not described. Tailscale should be installed and configured as part of the initial Pi setup flow.

**Root cause:** Not investigated.

**Status:** Fix implemented, pending test.

---
