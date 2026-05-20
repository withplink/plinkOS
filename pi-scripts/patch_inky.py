#!/usr/bin/env python3
"""
Patch Inky library to resolve GPIO8 CS0 conflict on Pi Zero 2W.
Required for Inky Impression 7.3" (Spectra 6 / E673) with inky >= 2.0.0.

Usage: sudo python3 patch_inky.py
"""
import os
import glob

def patch_inky_file(path):
    with open(path, "r") as f:
        content = f.read()

    original = content

    # 1. Skip GPIO pin availability check — replace entire if condition
    # Original: if gpiodevice.check_pins_available(gpiochip, { ... }):
    # Becomes:  if True:  (body still runs, but pin check is skipped)
    import re
    content = re.sub(
        r'if gpiodevice\.check_pins_available\(gpiochip, \{.*?\}\):',
        'if True:  # Skip GPIO pin check — SPI driver handles CS',
        content,
        flags=re.DOTALL
    )

    # 2. Don't request CS pin via gpiod (spidev owns it)
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

    # Also handle E673 variant (with bias params)
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

    # 3. Don't manually control CS pin in _spi_write (spidev handles it)
    old_spi = """self._gpio.set_value(self.cs_pin, Value.INACTIVE)
        self._gpio.set_value(self.dc_pin, Value.ACTIVE if dc else Value.INACTIVE)

        if isinstance(values, str):
            values = [ord(c) for c in values]

        for byte_value in values:
            self._spi_bus.xfer([byte_value])

        self._gpio.set_value(self.cs_pin, Value.ACTIVE)"""
    new_spi = """# CS handled by SPI driver
        self._gpio.set_value(self.dc_pin, Value.ACTIVE if dc else Value.INACTIVE)

        if isinstance(values, str):
            values = [ord(c) for c in values]

        for byte_value in values:
            self._spi_bus.xfer([byte_value])"""
    content = content.replace(old_spi, new_spi)

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
