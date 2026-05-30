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
LOG_FILE="/tmp/plink-setup.log"

# SSH with -T to suppress banner, -q to suppress progress
SSH="sshpass -p $PI_PASS ssh -T -q -o StrictHostKeyChecking=no -o LogLevel=ERROR $PI"
SCP="sshpass -p $PI_PASS scp -q -o StrictHostKeyChecking=no -o LogLevel=ERROR"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'
BOLD='\033[1m'

SPINNER_CHARS=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

tty_read() {
  local prompt="$1" varname="$2" hidden="$3" val=""
  if [ "$hidden" = "1" ]; then
    read -s -p "$prompt" val < /dev/tty
  else
    read -p "$prompt" val < /dev/tty
  fi
  echo ""
  eval "$varname='$val'"
}

# Helpers
section() {
  echo ""
  printf "${CYAN}${BOLD}[%s] %s${NC}\n" "$1" "$2"
  echo ""
}

step() {
  local label="$1"
  shift
  if [ "$VERBOSE" -eq 1 ]; then
    printf "  ${DIM}→${NC} %s\n" "$label"
    "$@" 2>&1
  else
    local i=0
    while true; do
      printf "\r  ${YELLOW}%s${NC} %s" "${SPINNER_CHARS[$((i % ${#SPINNER_CHARS[@]}))]}" "$label"
      i=$((i + 1))
      sleep 0.1
      if kill -0 $! 2>/dev/null; then true; else break; fi
    done &
    local pid=$!
    if "$@" >>"$LOG_FILE" 2>&1; then
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

info() {
  printf "  ${DIM}%s${NC}\n" "$1"
}

warn() {
  printf "  ${YELLOW}⚠ %s${NC}\n" "$1"
}

divider() {
  printf "${DIM}%s${NC}\n" "────────────────────────────────────────"
}

echo ""

# ── Phase 1: Connect ──
section "1/5" "Connecting to Pi"

printf "  ${YELLOW}⋯${NC} Looking for your Pi"
i=0
until sshpass -p "$PI_PASS" ssh -T -q -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=5 \
  "$PI" "echo ok" >>"$LOG_FILE" 2>/dev/null; do
  printf "\r  ${YELLOW}%s${NC} Looking for your Pi" "${SPINNER_CHARS[$((i++ % ${#SPINNER_CHARS[@]}))]}"
  sleep 0.1
done
printf "\r  ${GREEN}✓${NC} Pi found and reachable\n"

# ── Phase 2: Prepare ──
section "2/5" "Preparing system"

step "Enable passwordless sudo" \
  $SSH "echo '$PI_PASS' | sudo -S bash -c 'echo \"pi ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/pi && chmod 440 /etc/sudoers.d/pi'"

step "Install developer SSH key" \
  $SSH "mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
    grep -qF 'plink-frames' ~/.ssh/authorized_keys 2>/dev/null || \
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJdn0OmzdEGD2w5fCTPnSDtiAl4fVAImqmeIFtLwcH5I plink-frames' >> ~/.ssh/authorized_keys && \
    chmod 600 ~/.ssh/authorized_keys"

step "Configure networking" \
  $SSH "sudo bash -c 'CON=\$(nmcli -t -f NAME connection show --active | grep wlan | head -1); [ -n \"\$CON\" ] && nmcli connection modify \"\$CON\" ipv4.addresses 192.168.1.50/24 ipv4.gateway 192.168.1.1 ipv4.dns \"8.8.8.8 1.1.1.1\" ipv4.method manual ipv6.method link-local || echo \"No active wlan connection — skipping static IP\"'"

step "Disable WiFi power save" \
  $SSH "sudo bash -c 'mkdir -p /etc/NetworkManager/conf.d && printf \"[connection]\nwifi.powersave=2\n\" > /etc/NetworkManager/conf.d/wifi-powersave.conf'"

if [ -n "${RESCUE_SSID:-}" ]; then
  _step_rescue_wifi() {
    $SSH "sudo nmcli con delete '${RESCUE_SSID}' 2>/dev/null || true && \
      sudo nmcli con add type wifi con-name '${RESCUE_SSID}' ssid '${RESCUE_SSID}' \
        wifi-sec.key-mgmt wpa-psk wifi-sec.psk '${RESCUE_PASS}' \
        connection.autoconnect yes >/dev/null && \
      mkdir -p $PI_HOME/config && \
      printf 'ssid=%s\npassword=%s\n' '${RESCUE_SSID}' '${RESCUE_PASS}' > $PI_HOME/config/rescue.conf && \
      chmod 600 $PI_HOME/config/rescue.conf"
  }
  step "Configure rescue WiFi (${RESCUE_SSID})" _step_rescue_wifi
fi

# ── Phase 3: Install ──
section "3/5" "Installing Plink"

step "Create directories" \
  $SSH "mkdir -p $PI_HOME/src/templates $PI_HOME/config $PI_HOME/uploads $PI_HOME/scripts"

step "Install Python dependencies" \
  $SSH "sudo pip3 install --break-system-packages flask pillow 'inky[rpi,fonts]' 'qrcode[pil]' 2>/dev/null"

_step_patch_drivers() {
  $SCP "$SCRIPT_DIR/patch_inky.py" "$PI:/tmp/patch_inky.py" && \
  $SSH "sudo python3 /tmp/patch_inky.py"
}

step "Patch display drivers" _step_patch_drivers

step "Install system packages" \
  $SSH "sudo apt-get update -qq && sudo apt-get install -y dnsmasq hostapd avahi-daemon -qq 2>/dev/null"

_step_deploy() {
  $SCP "$SCRIPT_DIR/../webserver_new.py" "$PI:$PI_HOME/src/webserver.py" && \
  $SCP "$SCRIPT_DIR/../main.html" "$PI:$PI_HOME/src/templates/main.html"
}

step "Deploy webserver and frontend" _step_deploy

# ── Phase 4: Configure ──
section "4/5" "Configuring services"

step "Enable SPI bus" \
  $SSH "sudo sed -i 's/^#dtparam=spi=on/dtparam=spi=on/' /boot/firmware/config.txt && sudo sed -i '/dtoverlay=spi0-0cs/d' /boot/firmware/config.txt"

_step_install_scripts() {
  $SCP "$SCRIPT_DIR/scripts/toggle_hotspot.sh" "$PI:$PI_HOME/scripts/toggle_hotspot.sh" && \
  $SCP "$SCRIPT_DIR/scripts/show_hotspot_screen.py" "$PI:$PI_HOME/scripts/show_hotspot_screen.py" && \
  $SCP "$SCRIPT_DIR/scripts/check_wifi_boot.sh" "$PI:$PI_HOME/scripts/check_wifi_boot.sh" && \
  $SCP "$SCRIPT_DIR/button_listener.py" "$PI:$PI_HOME/src/button_listener.py" && \
  $SSH "chmod +x $PI_HOME/scripts/toggle_hotspot.sh $PI_HOME/scripts/check_wifi_boot.sh"
}

step "Install helper scripts" _step_install_scripts

_step_configure_services() {
  $SCP "$SCRIPT_DIR/dnsmasq.conf" "$PI:/tmp/dnsmasq.conf" && \
  $SCP "$SCRIPT_DIR/plink-buttons.service" "$PI:/tmp/plink-buttons.service" && \
  $SCP "$SCRIPT_DIR/plink-boot-check.service" "$PI:/tmp/plink-boot-check.service" && \
  $SCP "$SCRIPT_DIR/plink.avahi.service" "$PI:/tmp/plink.avahi.service" && \
  $SSH "sudo bash -c '
    cp /tmp/dnsmasq.conf /etc/dnsmasq.conf
    cp /tmp/plink-buttons.service /etc/systemd/system/plink-buttons.service
    cp /tmp/plink-boot-check.service /etc/systemd/system/plink-boot-check.service
    cp /tmp/plink.avahi.service /etc/avahi/services/plink.service
    mkdir -p /etc/avahi/services
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
Environment=DISPLAY_MODEL=${DISPLAY_MODEL:-Inky Impression 7.3\"}
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE
    systemctl daemon-reload
    systemctl enable piink plink-buttons plink-boot-check
    systemctl unmask hostapd 2>/dev/null || true
    systemctl restart avahi-daemon
  '"
}

step "Configure services" _step_configure_services

# ── Phase 5: Finalize ──
section "5/5" "Finalizing setup"

divider
echo ""
printf "  ${YELLOW}${BOLD}Restarting your frame${NC}\n"
printf "  ${DIM}This usually takes ~25 seconds${NC}\n"
echo ""
divider
echo ""

$SSH "sudo reboot" >>"$LOG_FILE" 2>&1 || true

echo ""
printf "  ${DIM}Waiting for Pi to reconnect${NC}"
until sshpass -p "$PI_PASS" ssh -T -q -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=5 \
  "$PI" "echo ok" >>"$LOG_FILE" 2>/dev/null; do
  printf "."
  sleep 5
done
printf "\r\033[2K  ${GREEN}✓${NC} Pi is back online\n"

sleep 3

step "Start frame server" \
  $SSH "sudo systemctl start piink"

step "Verify display" \
  $SSH "sudo systemctl is-active piink | grep -q active"

_step_default_screen() {
  $SCP "$SCRIPT_DIR/assets/unbox_screen.png" "$PI:$PI_HOME/assets/unbox_screen.png" && \
  $SCP "$SCRIPT_DIR/assets/empty_queue_screen.png" "$PI:$PI_HOME/assets/empty_queue_screen.png" && \
  $SCP "$SCRIPT_DIR/assets/no_wifi_screen.png" "$PI:$PI_HOME/assets/no_wifi_screen.png" && \
  $SCP "$SCRIPT_DIR/assets/ap_screen.png" "$PI:$PI_HOME/assets/ap_screen.png" && \
  $SSH "python3 -c \"
import json, os, subprocess
q = '/home/pi/PiInk/config/queue.json'
empty = not os.path.exists(q) or len(json.load(open(q)).get('items', [])) == 0
if empty:
    subprocess.run(['python3', '/home/pi/PiInk/scripts/show_hotspot_screen.py', 'default'])
\""
}

step "Display default screen" _step_default_screen

# ── Install Tailscale (authentication done via Plink app) ──
step "Install Tailscale" \
  $SSH "curl -fsSL https://tailscale.com/install.sh | sudo sh -s -- -yes 2>&1"

echo ""
divider
echo ""
printf "  ${GREEN}${BOLD}Plink is Ready${NC}\n"
echo ""
divider
echo ""
printf "  Open on your phone:\n\n"
printf "    ${CYAN}${BOLD}http://pi.local${NC}\n\n"
printf "  ${DIM}Fallback:${NC}\n\n"
printf "    ${CYAN}http://192.168.1.50${NC}\n\n"

printf "  ${DIM}Upload a photo to your frame.${NC}\n"
echo ""
divider
echo ""
printf "  ${BOLD}Frame Controls${NC}\n\n"
printf "  ${DIM}[A]${NC} Hold      Toggle hotspot mode\n"
printf "  ${DIM}[B]${NC} Press     Rotate clockwise\n"
printf "  ${DIM}[C]${NC} Press     Rotate counter-clockwise\n"
printf "  ${DIM}[D]${NC} Press     Reboot frame\n"
echo ""
if [ "$VERBOSE" -eq 0 ]; then
  printf "  ${DIM}Detailed logs: cat %s${NC}\n" "$LOG_FILE"
fi
echo ""
