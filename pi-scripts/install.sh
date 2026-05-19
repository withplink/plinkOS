#!/bin/bash
# Install Plink Pi-side components (hotspot + button listener).
# Run ON the Pi as: bash install.sh
# Or from your Mac via: sshpass -p '5409' ssh pi@pi.local 'bash -s' < pi-scripts/install.sh

set -e

PI_HOME=/home/pi/PiInk

echo "=== Installing system deps ==="
sudo apt-get install -y dnsmasq hostapd

echo "=== Installing Python deps ==="
pip3 install --break-system-packages zeroconf qrcode[pil] RPi.GPIO 2>/dev/null || \
  pip3 install zeroconf "qrcode[pil]" RPi.GPIO

echo "=== Copying scripts ==="
mkdir -p "$PI_HOME/scripts"
cp button_listener.py                    "$PI_HOME/src/button_listener.py"
cp scripts/toggle_hotspot.sh            "$PI_HOME/scripts/toggle_hotspot.sh"
cp scripts/show_hotspot_screen.py       "$PI_HOME/scripts/show_hotspot_screen.py"
cp scripts/check_wifi_boot.sh           "$PI_HOME/scripts/check_wifi_boot.sh"
chmod +x "$PI_HOME/scripts/toggle_hotspot.sh"
chmod +x "$PI_HOME/scripts/check_wifi_boot.sh"

echo "=== Installing dnsmasq config ==="
sudo cp dnsmasq.conf /etc/dnsmasq.conf

echo "=== Enabling hostapd ==="
sudo systemctl unmask hostapd || true
sudo systemctl enable hostapd || true

echo "=== Installing systemd services ==="
sudo cp plink-buttons.service /etc/systemd/system/plink-buttons.service
sudo cp plink-boot-check.service /etc/systemd/system/plink-boot-check.service
sudo systemctl daemon-reload
sudo systemctl enable plink-buttons
sudo systemctl enable plink-boot-check
sudo systemctl restart plink-buttons

echo "=== Installing Avahi service ==="
sudo cp plink.avahi.service /etc/avahi/services/plink.service
sudo systemctl restart avahi-daemon

echo ""
echo "Done. Hold Button A on the frame for 1.5s to toggle hotspot mode."
echo "The QR code on the display encodes the WiFi join info for your phone."
