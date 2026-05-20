## [PiStability] Pi stops working and requires manual restart

**Repro:** Not described. Observed 2026-05-19 ~20:30 IST — both pi.local and static IP (192.168.1.50) unreachable. Manual restart restored access.

**Root cause:** Not investigated. Hardware watchdog (1min timeout) triggered reboot. Likely OOM during image processing or kernel freeze. Journal was not persistent at time of incident — no pre-reboot logs available. Persistent journal now enabled.

**Status:** Not investigated.

---
