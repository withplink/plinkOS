#!/bin/bash

set -e

VERBOSE=0
for arg in "$@"; do
  if [ "$arg" = "--verbose" ] || [ "$arg" = "-v" ]; then
    VERBOSE=1
  fi
done

# Load .env if present (repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
  set -a
  source "$SCRIPT_DIR/../.env"
  set +a
fi

PI_USER="${PI_USER:-pi}"
PI_HOST="${PI_HOST:-192.168.1.50}"
if [ -z "$PI_PASS" ]; then
  echo "Error: PI_PASS not set. Copy .env.example to .env and fill in your Pi password."
  exit 1
fi
PI="$PI_USER@$PI_HOST"
PI_HOME="/home/pi/PiInk"

# SSH with -T to suppress banner, -q to suppress progress
SSH="sshpass -p $PI_PASS ssh -T -q -o StrictHostKeyChecking=no -o LogLevel=ERROR $PI"
SCP="sshpass -p $PI_PASS scp -q -o StrictHostKeyChecking=no -o LogLevel=ERROR"

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
    "$@" 2>&1
  else
    spinner_start "$label" &
    SPINNER_PID=$!
    if "$@" >>/tmp/plink-setup.log 2>&1; then
      kill "$SPINNER_PID" 2>/dev/null
      wait "$SPINNER_PID" 2>/dev/null
      printf "\r  ${GREEN}✓${NC} %s\n" "$label"
    else
      kill "$SPINNER_PID" 2>/dev/null
      wait "$SPINNER_PID" 2>/dev/null
      printf "\r  ${RED}✗${NC} %s (run with --verbose to see full logs)\n" "$label"
    fi
  fi
}

echo ""

# Wait for Pi
printf "  ${YELLOW}⋯${NC} Waiting for Pi to come online"
until sshpass -p "$PI_PASS" ssh -T -q -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=5 \
  "$PI" "echo ok" >>/tmp/plink-setup.log 2>/dev/null; do
  printf "."
  sleep 5
done
printf "\r  ${GREEN}✓${NC} Pi is online\n"

echo ""
printf "  ${BOLD}Configuring Pi${NC}\n\n"

# Enable passwordless sudo
step "Enable passwordless sudo" \
  $SSH "echo '$PI_PASS' | sudo -S bash -c 'echo \"pi ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/pi && chmod 440 /etc/sudoers.d/pi'"

# Static IP
step "Save static IP profile (applies after reboot)" \
  $SSH "sudo bash -c 'CON=\$(nmcli -t -f NAME connection show --active | grep wlan | head -1) && nmcli connection modify \"\$CON\" ipv4.addresses 192.168.1.50/24 ipv4.gateway 192.168.1.1 ipv4.dns \"8.8.8.8 1.1.1.1\" ipv4.method manual ipv6.method link-local'"

# WiFi power save
step "Disable WiFi power save" \
  $SSH "sudo bash -c 'mkdir -p /etc/NetworkManager/conf.d && echo -e \"[connection]\nwifi.powersave=2\" > /etc/NetworkManager/conf.d/wifi-powersave.conf && systemctl restart NetworkManager'"

# Directory structure
step "Create directory structure" \
  $SSH "mkdir -p $PI_HOME/src/templates $PI_HOME/config $PI_HOME/uploads $PI_HOME/scripts"

# Python deps
step "Install Python dependencies" \
  $SSH "sudo pip3 install --break-system-packages flask pillow 'inky[rpi,fonts]' 'qrcode[pil]' 2>/dev/null"

# Patch Inky
step "Patch Inky library for GPIO/SPI compatibility" \
  $SCP pi-scripts/patch_inky.py "$PI:/tmp/patch_inky.py" && \
  $SSH "sudo python3 /tmp/patch_inky.py"

# System deps
step "Install system packages" \
  $SSH "sudo apt-get update -qq && sudo apt-get install -y dnsmasq hostapd avahi-daemon -qq 2>/dev/null"

# Deploy webserver + frontend
step "Deploy webserver and frontend" \
  $SCP webserver_new.py "$PI:$PI_HOME/src/webserver.py" && \
  $SCP main.html "$PI:$PI_HOME/src/templates/main.html"

# Boot config
step "Enable SPI + disable CS conflict" \
  $SSH "sudo sed -i 's/^#dtparam=spi=on/dtparam=spi=on/' /boot/firmware/config.txt && grep -q 'dtoverlay=spi0-0cs' /boot/firmware/config.txt || sudo sh -c \"echo 'dtoverlay=spi0-0cs' >> /boot/firmware/config.txt\""

# Install scripts
step "Install helper scripts" \
  $SCP pi-scripts/scripts/toggle_hotspot.sh "$PI:$PI_HOME/scripts/toggle_hotspot.sh" && \
  $SCP pi-scripts/scripts/show_hotspot_screen.py "$PI:$PI_HOME/scripts/show_hotspot_screen.py" && \
  $SCP pi-scripts/scripts/check_wifi_boot.sh "$PI:$PI_HOME/scripts/check_wifi_boot.sh" && \
  $SCP pi-scripts/button_listener.py "$PI:$PI_HOME/src/button_listener.py" && \
  $SSH "chmod +x $PI_HOME/scripts/toggle_hotspot.sh $PI_HOME/scripts/check_wifi_boot.sh"

# dnsmasq config
step "Install dnsmasq config" \
  $SCP pi-scripts/dnsmasq.conf "$PI:/tmp/dnsmasq.conf" && \
  $SSH "sudo cp /tmp/dnsmasq.conf /etc/dnsmasq.conf"

# systemd services
step "Install systemd services" \
  $SCP pi-scripts/plink-buttons.service "$PI:/tmp/plink-buttons.service" && \
  $SCP pi-scripts/plink-boot-check.service "$PI:/tmp/plink-boot-check.service" && \
  $SSH "sudo bash -c '
    cp /tmp/plink-buttons.service /etc/systemd/system/plink-buttons.service
    cp /tmp/plink-boot-check.service /etc/systemd/system/plink-boot-check.service
    cat > /etc/systemd/system/piink.service <<SERVICE
[Unit]
Description=Plink e-ink frame server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 /home/pi/PiInk/src/webserver.py
WorkingDirectory=/home/pi/PiInk/src
User=pi
Environment=PYTHONPATH=/home/pi/.local/lib/python3.13/site-packages
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE
    systemctl daemon-reload
    systemctl enable piink plink-buttons plink-boot-check
    systemctl unmask hostapd || true
  '"

# Avahi
step "Install Avahi mDNS service" \
  $SCP pi-scripts/plink.avahi.service "$PI:/tmp/plink.avahi.service" && \
  $SSH "sudo bash -c 'mkdir -p /etc/avahi/services && cp /tmp/plink.avahi.service /etc/avahi/services/plink.service && systemctl restart avahi-daemon'"

echo ""
printf "  ${BOLD}Rebooting Pi${NC}\n\n"

# Reboot
$SSH "sudo reboot" >>/tmp/plink-setup.log 2>&1 || true
printf "  ${YELLOW}⋯${NC} Rebooting..."

until sshpass -p "$PI_PASS" ssh -T -q -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=5 \
  "$PI" "echo ok" >>/tmp/plink-setup.log 2>/dev/null; do
  printf "\r  ${YELLOW}⋯${NC} Waiting for Pi to come back online"
  sleep 5
done
printf "\r  ${GREEN}✓${NC} Pi is back online\n"

sleep 3

# Start piink
step "Start piink service" \
  $SSH "sudo systemctl start piink"

echo ""
