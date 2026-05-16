#!/usr/bin/env python3
"""
GPIO daemon: monitors Inky Impression Button A (BCM pin 5).
Long press (>1.5s) toggles between WiFi client and plink-setup AP mode.
Run as: systemd service plink-buttons.service
"""

import subprocess
import time
import RPi.GPIO as GPIO

BUTTON_A_PIN = 5
LONG_PRESS_SECONDS = 1.5
TOGGLE_SCRIPT = "/home/pi/PiInk/scripts/toggle_hotspot.sh"

GPIO.setmode(GPIO.BCM)
GPIO.setup(BUTTON_A_PIN, GPIO.IN, pull_up_down=GPIO.PUD_UP)

print("Plink button listener started. Hold Button A for 1.5s to toggle hotspot.")

try:
    while True:
        if GPIO.input(BUTTON_A_PIN) == GPIO.LOW:
            press_start = time.time()
            while GPIO.input(BUTTON_A_PIN) == GPIO.LOW:
                time.sleep(0.05)
            held = time.time() - press_start
            if held >= LONG_PRESS_SECONDS:
                print(f"Long press detected ({held:.1f}s) — toggling hotspot")
                subprocess.run(["bash", TOGGLE_SCRIPT], check=False)
        time.sleep(0.05)
except KeyboardInterrupt:
    pass
finally:
    GPIO.cleanup()
