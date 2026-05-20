#!/usr/bin/env python3
"""
Patch Inky library to resolve GPIO8 CS0 conflict on Pi Zero 2W.
Required for Inky Impression 7.3" (Spectra 6 / E673) with inky >= 2.0.0.

Usage: sudo python3 patch_inky.py
"""
import os
import glob
import re

def patch_inky_file(path):
    with open(path, "r") as f:
        content = f.read()

    original = content

    # 1. Skip GPIO pin availability check — replace entire if condition
    content = re.sub(
        r'if gpiodevice\.check_pins_available\(gpiochip, \{.*?\}\):',
        'if True:  # Skip GPIO pin check — SPI driver handles CS',
        content,
        flags=re.DOTALL
    )

    # 2. Don't request CS pin via gpiod (spidev owns it)
    # E673 variant (with bias params)
    old_request_e673 = """self._gpio = gpiochip.request_lines(consumer="inky", config={
                        self.cs_pin: gpiod.LineSettings(direction=Direction.OUTPUT, output_value=Value.ACTIVE, bias=Bias.DISABLED),
                        self.dc_pin: gpiod.LineSettings(direction=Direction.OUTPUT, output_value=Value.INACTIVE, bias=Bias.DISABLED),
                        self.reset_pin: gpiod.LineSettings(direction=Direction.OUTPUT, output_value=Value.ACTIVE, bias=Bias.DISABLED),
                        self.busy_pin: gpiod.LineSettings(direction=Direction.INPUT, bias=Bias.PULL_UP)
                    })"""
    new_request_e673 = """# Only request DC, RESET, BUSY — SPI driver handles CS
                    self._gpio = gpiochip.request_lines(consumer="inky", config={
                        self.dc_pin: gpiod.LineSettings(direction=Direction.OUTPUT, output_value=Value.INACTIVE, bias=Bias.DISABLED),
                        self.reset_pin: gpiod.LineSettings(direction=Direction.OUTPUT, output_value=Value.ACTIVE, bias=Bias.DISABLED),
                        self.busy_pin: gpiod.LineSettings(direction=Direction.INPUT, bias=Bias.PULL_UP)
                    })"""
    content = content.replace(old_request_e673, new_request_e673)

    # Non-E673 variant (no bias params)
    old_request = """self._gpio = gpiochip.request_lines(consumer="inky", config={
                        self.cs_pin: gpiod.LineSettings(direction=Direction.OUTPUT, output_value=Value.ACTIVE),
                        self.dc_pin: gpiod.LineSettings(direction=Direction.OUTPUT, output_value=Value.INACTIVE),
                        self.reset_pin: gpiod.LineSettings(direction=Direction.OUTPUT, output_value=Value.ACTIVE),
                        self.busy_pin: gpiod.LineSettings(direction=Direction.INPUT, edge_detection=Edge.RISING, debounce_period=timedelta(milliseconds=10))
                    })"""
    new_request = """# Only request DC, RESET, BUSY — SPI driver handles CS
                    self._gpio = gpiochip.request_lines(consumer="inky", config={
                        self.dc_pin: gpiod.LineSettings(direction=Direction.OUTPUT, output_value=Value.INACTIVE),
                        self.reset_pin: gpiod.LineSettings(direction=Direction.OUTPUT, output_value=Value.ACTIVE),
                        self.busy_pin: gpiod.LineSettings(direction=Direction.INPUT, edge_detection=Edge.RISING, debounce_period=timedelta(milliseconds=10))
                    })"""
    content = content.replace(old_request, new_request)

    # 3. Don't manually control CS pin (spidev handles it)
    # Remove ALL cs_pin set_value calls — works for any variant
    content = re.sub(
        r'\s*self\._gpio\.set_value\(self\.cs_pin, Value\.(INACTIVE|ACTIVE)\)\s*\n',
        '\n',
        content
    )

    if content != original:
        with open(path, "w") as f:
            f.write(content)
        return True
    return False

# Find all inky driver files
paths = glob.glob("/usr/local/lib/python3.*/dist-packages/inky/inky_*.py") + \
        glob.glob("/home/pi/.local/lib/python3.*/site-packages/inky/inky_*.py")

patched = 0
for p in paths:
    if patch_inky_file(p):
        print(f"Patched: {p}")
        patched += 1

if patched == 0:
    print("No files needed patching (already patched or not found)")
else:
    print(f"Patched {patched} file(s)")
