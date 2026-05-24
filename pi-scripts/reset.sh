#!/bin/bash
# Reset Pi to pre-install state — removes all Plink files, services, packages, and config changes
# Usage: bash pi-scripts/reset.sh [--verbose]

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
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'
BOLD='\033[1m'

SPINNER_CHARS=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

section() {
  echo ""
  if [ -n "$1" ]; then
    printf "${CYAN}${BOLD}[%s] %s${NC}\n" "$1" "$2"
  else
    printf "${CYAN}${BOLD}%s${NC}\n" "$2"
  fi
  echo ""
}

step() {
  local label="$1"
  shift
  if [ "$VERBOSE" -eq 1 ]; then
    printf "  ${DIM}→${NC} %s\n" "$label"
    "$@" 2>&1 || true
  else
    local i=0
    while true; do
      printf "\r  ${YELLOW}%s${NC} %s" "${SPINNER_CHARS[$((i % ${#SPINNER_CHARS[@]}))]}" "$label"
      i=$((i + 1))
      sleep 0.1
      if kill -0 $! 2>/dev/null; then true; else break; fi
    done &
    local pid=$!
    if "$@" >/dev/null 2>&1; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      printf "\r  ${GREEN}✓${NC} %s\n" "$label"
    else
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      printf "\r  ${RED}✗${NC} %s (run with -v to see logs)\n" "$label"
    fi
  fi
}

divider() {
  printf "${DIM}%s${NC}\n" "────────────────────────────────────────"
}

echo ""
section "" "Cleaning Pi"

# ── Show default image before wiping (e-ink persists after reset) ──
_DEFAULT_IMG=""
_DEFAULT_EXT=""
for _ext in jpg jpeg png webp; do
  if [ -f "$SCRIPT_DIR/../default-image.$_ext" ]; then
    _DEFAULT_IMG="$SCRIPT_DIR/../default-image.$_ext"
    _DEFAULT_EXT="$_ext"
    break
  fi
done
if [ -n "$_DEFAULT_IMG" ]; then
  SCP="sshpass -p $PI_PASS scp -q -o StrictHostKeyChecking=no -o LogLevel=ERROR"
  _step_show_default() {
    $SCP "$_DEFAULT_IMG" "$PI_USER@$PI_HOST:/tmp/default-image.$_DEFAULT_EXT" && \
    $SSH "curl -sf -X POST -F 'file=@/tmp/default-image.$_DEFAULT_EXT' http://localhost/api/upload > /dev/null && rm -f /tmp/default-image.$_DEFAULT_EXT"
  }
  step "Set default image" _step_show_default
fi

step "Stop services" \
  $SSH "echo '$PI_PASS' | sudo -S systemctl stop piink plink-buttons plink-boot-check 2>/dev/null || true"

step "Remove services" \
  $SSH "echo '$PI_PASS' | sudo -S rm -f /etc/systemd/system/piink.service /etc/systemd/system/plink-buttons.service /etc/systemd/system/plink-boot-check.service && echo '$PI_PASS' | sudo -S systemctl daemon-reload"

step "Remove app files" \
  $SSH "echo '$PI_PASS' | sudo -S rm -rf /home/pi/PiInk /home/pi/scripts"

step "Remove config files" \
  $SSH "echo '$PI_PASS' | sudo -S rm -f /etc/avahi/services/plink.service /etc/dnsmasq.conf /etc/NetworkManager/conf.d/wifi-powersave.conf /etc/sudoers.d/pi"

step "Revert boot config" \
  $SSH "echo '$PI_PASS' | sudo -S sed -i '/dtoverlay=spi0-0cs/d' /boot/firmware/config.txt && echo '$PI_PASS' | sudo -S sed -i 's/^dtparam=spi=on/#dtparam=spi=on/' /boot/firmware/config.txt"

step "Remove Python packages" \
  $SSH "echo '$PI_PASS' | sudo -S pip3 uninstall -y --break-system-packages inky gpiodevice qrcode RPi.GPIO zeroconf ifaddr 2>/dev/null || true && echo '$PI_PASS' | sudo -S rm -rf /home/pi/.local/lib/python3.*/site-packages/inky* /home/pi/.local/lib/python3.*/site-packages/gpiodevice* /home/pi/.local/lib/python3.*/site-packages/qrcode* /home/pi/.local/lib/python3.*/site-packages/RPi* /home/pi/.local/lib/python3.*/site-packages/zeroconf* /home/pi/.local/lib/python3.*/site-packages/ifaddr*"

step "Remove system packages" \
  $SSH "echo '$PI_PASS' | sudo -S apt-get remove -y dnsmasq hostapd -qq 2>/dev/null || true"

step "Remove Tailscale" \
  $SSH "echo '$PI_PASS' | sudo -S bash -c 'tailscale down 2>/dev/null || true; systemctl stop tailscaled 2>/dev/null || true; systemctl disable tailscaled 2>/dev/null || true; apt-get remove -y tailscale -qq 2>/dev/null || true; rm -f /etc/apt/sources.list.d/tailscale.list'"

step "Reset network to DHCP" \
  $SSH "echo '$PI_PASS' | sudo -S bash -c 'CON=\$(nmcli -t -f NAME connection show --active | grep wlan | head -1) && [ -n \"\$CON\" ] && nmcli connection modify \"\$CON\" ipv4.method auto ipv6.method auto'"

echo ""
divider
echo ""
printf "  ${GREEN}${BOLD}Pi is clean${NC}\n\n"
printf "  ${DIM}Ready for a fresh setup.${NC}\n"
echo ""
