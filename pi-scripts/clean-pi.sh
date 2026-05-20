#!/bin/bash
# Clean Pi to fresh state — removes all Plink files, services, and config changes
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
  echo '$PI_PASS' | sudo -S systemctl stop piink plink-buttons plink-boot-check 2>/dev/null || true
  echo '$PI_PASS' | sudo -S rm -rf /home/pi/PiInk /home/pi/scripts
  echo '$PI_PASS' | sudo -S rm -f /etc/systemd/system/piink.service /etc/systemd/system/plink-buttons.service /etc/systemd/system/plink-boot-check.service
  echo '$PI_PASS' | sudo -S rm -f /etc/avahi/services/plink.service
  echo '$PI_PASS' | sudo -S rm -f /etc/dnsmasq.conf
  echo '$PI_PASS' | sudo -S rm -f /etc/NetworkManager/conf.d/wifi-powersave.conf
  echo '$PI_PASS' | sudo -S rm -f /etc/sudoers.d/pi
  echo '$PI_PASS' | sudo -S sed -i '/dtoverlay=spi0-0cs/d' /boot/firmware/config.txt
  echo '$PI_PASS' | sudo -S rm -f /tmp/patch_inky.py /tmp/plink-buttons.service /tmp/plink-boot-check.service /tmp/plink.avahi.service /tmp/dnsmasq.conf
  echo '$PI_PASS' | sudo -S rm -rf /home/pi/.local/lib/python3.*/site-packages/inky
  echo 'Pi cleaned successfully'
"

echo "=== Done ==="
echo "Pi is ready for a fresh setup run."
