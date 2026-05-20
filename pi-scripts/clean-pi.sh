#!/bin/bash
# Clean Pi to fresh state — removes all Plink files, services, packages, and config changes
# Usage: bash pi-scripts/clean-pi.sh

set -e

# Load .env if present
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
  set -a
  source "$SCRIPT_DIR/../.env"
  set +a
fi

PI_USER="${PI_USER:-pi}"
PI_HOST="${PI_HOST:-pi.local}"
PI_PASS="${PI_PASS:-}"

if [ -z "$PI_PASS" ]; then
  echo "Error: PI_PASS not set. Copy .env.example to .env and fill in your Pi password."
  exit 1
fi

SSH="sshpass -p $PI_PASS ssh -q -o StrictHostKeyChecking=no -o LogLevel=ERROR $PI_USER@$PI_HOST"

echo "=== Cleaning Pi ==="

$SSH "
  # Stop services
  echo '$PI_PASS' | sudo -S systemctl stop piink plink-buttons plink-boot-check 2>/dev/null || true
  echo '$PI_PASS' | sudo -S systemctl disable piink plink-buttons plink-boot-check 2>/dev/null || true

  # Remove services
  echo '$PI_PASS' | sudo -S rm -f /etc/systemd/system/piink.service /etc/systemd/system/plink-buttons.service /etc/systemd/system/plink-boot-check.service
  echo '$PI_PASS' | sudo -S systemctl daemon-reload

  # Remove app files
  echo '$PI_PASS' | sudo -S rm -rf /home/pi/PiInk /home/pi/scripts

  # Remove configs
  echo '$PI_PASS' | sudo -S rm -f /etc/avahi/services/plink.service
  echo '$PI_PASS' | sudo -S rm -f /etc/dnsmasq.conf
  echo '$PI_PASS' | sudo -S rm -f /etc/NetworkManager/conf.d/wifi-powersave.conf
  echo '$PI_PASS' | sudo -S rm -f /etc/sudoers.d/pi

  # Revert boot config
  echo '$PI_PASS' | sudo -S sed -i '/dtoverlay=spi0-0cs/d' /boot/firmware/config.txt
  echo '$PI_PASS' | sudo -S sed -i 's/^dtparam=spi=on/#dtparam=spi=on/' /boot/firmware/config.txt

  # Remove temp files
  echo '$PI_PASS' | sudo -S rm -f /tmp/patch_inky.py /tmp/plink-buttons.service /tmp/plink-boot-check.service /tmp/plink.avahi.service /tmp/dnsmasq.conf

  # Remove Python packages
  echo '$PI_PASS' | sudo -S pip3 uninstall -y --break-system-packages inky gpiodevice qrcode RPi.GPIO zeroconf ifaddr 2>/dev/null || true
  echo '$PI_PASS' | sudo -S rm -rf /home/pi/.local/lib/python3.*/site-packages/inky* /home/pi/.local/lib/python3.*/site-packages/gpiodevice* /home/pi/.local/lib/python3.*/site-packages/qrcode* /home/pi/.local/lib/python3.*/site-packages/RPi* /home/pi/.local/lib/python3.*/site-packages/zeroconf* /home/pi/.local/lib/python3.*/site-packages/ifaddr*

  # Remove system packages
  echo '$PI_PASS' | sudo -S apt-get remove -y dnsmasq hostapd 2>/dev/null || true

  # Reset static IP to DHCP
  CON=\$(nmcli -t -f NAME connection show --active | grep wlan | head -1)
  if [ -n \"\$CON\" ]; then
    echo '$PI_PASS' | sudo -S nmcli connection modify \"\$CON\" ipv4.method auto ipv6.method auto 2>/dev/null || true
  fi

  echo 'Pi cleaned successfully'
"

echo "=== Done ==="
echo "Pi is ready for a fresh setup run."
