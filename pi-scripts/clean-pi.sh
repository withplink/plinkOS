#!/bin/bash
# Clean Pi to fresh state — removes all Plink files, services, packages, and config changes
# Usage: bash pi-scripts/clean-pi.sh [--verbose]

set -e

VERBOSE=0
for arg in "$@"; do
  if [ "$arg" = "--verbose" ] || [ "$arg" = "-v" ]; then
    VERBOSE=1
  fi
done

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

# SSH with -T to suppress banner, -q to suppress progress
SSH="sshpass -p $PI_PASS ssh -T -q -o StrictHostKeyChecking=no -o LogLevel=ERROR $PI_USER@$PI_HOST"

# Colors
CORAL='\033[38;2;255;127;80m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

SPINNER_PID=""
SPINNER_CHARS=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

spinner_start() {
  local i=0
  while true; do
    printf "\r  ${YELLOW}%s${NC} %s" "${SPINNER_CHARS[$i]}" "$1"
    i=$(( (i + 1) % ${#SPINNER_CHARS[@]} ))
    sleep 0.1
  done
}

step() {
  local label="$1"
  shift
  if [ "$VERBOSE" -eq 1 ]; then
    printf "  ${BOLD}→${NC} %s\n" "$label"
    "$@" 2>&1 || true
  else
    spinner_start "$label" &
    SPINNER_PID=$!
    if "$@" >/dev/null 2>&1; then
      kill "$SPINNER_PID" 2>/dev/null || true
      wait "$SPINNER_PID" 2>/dev/null || true
      printf "\r  ${GREEN}✓${NC} %s\n" "$label"
    else
      kill "$SPINNER_PID" 2>/dev/null || true
      wait "$SPINNER_PID" 2>/dev/null || true
      printf "\r  ${RED}✗${NC} %s (run with -v to see full logs)\n" "$label"
    fi
  fi
}

echo ""
printf "  ${BOLD}Cleaning Pi${NC}\n\n"

# Stop services
step "Stop Plink services" \
  $SSH "echo '$PI_PASS' | sudo -S systemctl stop piink plink-buttons plink-boot-check 2>/dev/null || true"

step "Disable Plink services" \
  $SSH "echo '$PI_PASS' | sudo -S systemctl disable piink plink-buttons plink-boot-check 2>/dev/null || true"

# Remove services
step "Remove systemd services" \
  $SSH "echo '$PI_PASS' | sudo -S rm -f /etc/systemd/system/piink.service /etc/systemd/system/plink-buttons.service /etc/systemd/system/plink-boot-check.service && echo '$PI_PASS' | sudo -S systemctl daemon-reload"

# Remove app files
step "Remove app files" \
  $SSH "echo '$PI_PASS' | sudo -S rm -rf /home/pi/PiInk /home/pi/scripts"

# Remove configs
step "Remove config files" \
  $SSH "echo '$PI_PASS' | sudo -S rm -f /etc/avahi/services/plink.service /etc/dnsmasq.conf /etc/NetworkManager/conf.d/wifi-powersave.conf /etc/sudoers.d/pi"

# Revert boot config
step "Revert boot config" \
  $SSH "echo '$PI_PASS' | sudo -S sed -i '/dtoverlay=spi0-0cs/d' /boot/firmware/config.txt && echo '$PI_PASS' | sudo -S sed -i 's/^dtparam=spi=on/#dtparam=spi=on/' /boot/firmware/config.txt"

# Remove temp files
step "Remove temp files" \
  $SSH "echo '$PI_PASS' | sudo -S rm -f /tmp/patch_inky.py /tmp/plink-buttons.service /tmp/plink-boot-check.service /tmp/plink.avahi.service /tmp/dnsmasq.conf"

# Remove Python packages
step "Remove Python packages" \
  $SSH "echo '$PI_PASS' | sudo -S pip3 uninstall -y --break-system-packages inky gpiodevice qrcode RPi.GPIO zeroconf ifaddr 2>/dev/null || true && echo '$PI_PASS' | sudo -S rm -rf /home/pi/.local/lib/python3.*/site-packages/inky* /home/pi/.local/lib/python3.*/site-packages/gpiodevice* /home/pi/.local/lib/python3.*/site-packages/qrcode* /home/pi/.local/lib/python3.*/site-packages/RPi* /home/pi/.local/lib/python3.*/site-packages/zeroconf* /home/pi/.local/lib/python3.*/site-packages/ifaddr*"

# Remove system packages
step "Remove system packages" \
  $SSH "echo '$PI_PASS' | sudo -S apt-get remove -y dnsmasq hostapd -qq 2>/dev/null || true"

# Reset static IP to DHCP
step "Reset network to DHCP" \
  $SSH "echo '$PI_PASS' | sudo -S bash -c 'CON=\$(nmcli -t -f NAME connection show --active | grep wlan | head -1) && [ -n \"\$CON\" ] && nmcli connection modify \"\$CON\" ipv4.method auto ipv6.method auto'"

echo ""
printf "  ${GREEN}${BOLD}Pi is clean and ready for a fresh setup.${NC}\n\n"
