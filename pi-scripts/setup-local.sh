#!/bin/bash
# Full Plink setup — runs ON the Pi.
# Usage: sshpass -p '<PI_PASS>' ssh pi@pi.local 'bash -s' < pi-scripts/setup-local.sh
# Or copy to Pi and run: bash setup-local.sh

set -e

PI_HOME=/home/pi/PiInk
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  printf "${CYAN}${BOLD}[%s] %s${NC}\n" "$1" "$2"
  echo ""
}

step() {
  local label="$1"
  shift
  local i=0
  while true; do
    printf "\r  ${YELLOW}%s${NC} %s" "${SPINNER_CHARS[$((i % ${#SPINNER_CHARS[@]}))]}" "$label"
    i=$((i + 1))
    sleep 0.1
    if kill -0 $! 2>/dev/null; then true; else break; fi
  done &
  local pid=$!
  if eval "$@" >/dev/null 2>&1; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    printf "\r  ${GREEN}✓${NC} %s\n" "$label"
  else
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    printf "\r  ${RED}✗${NC} %s\n" "$label"
    exit 1
  fi
}

warn() {
  printf "  ${YELLOW}⚠ %s${NC}\n" "$1"
}

divider() {
  printf "${DIM}%s${NC}\n" "────────────────────────────────────────"
}

echo ""

# ── Phase 1: Prepare ──
section "1/6" "Preparing system"

step "Enable passwordless sudo" \
  "echo 'pi ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/pi >/dev/null && sudo chmod 440 /etc/sudoers.d/pi"

step "Create directory structure" \
  "mkdir -p '$PI_HOME/src/templates' '$PI_HOME/config' '$PI_HOME/uploads' '$PI_HOME/scripts'"

# ── Phase 2: Dependencies ──
section "2/6" "Installing dependencies"

step "Install system packages" \
  "sudo apt-get update -qq && sudo apt-get install -y dnsmasq hostapd avahi-daemon -qq 2>/dev/null"

step "Install Python packages" \
  "sudo pip3 install --break-system-packages flask pillow 'inky[rpi,fonts]' 'qrcode[pil]' zeroconf RPi.GPIO 2>/dev/null || pip3 install flask pillow 'inky[rpi,fonts]' 'qrcode[pil]' zeroconf RPi.GPIO"

# ── Phase 3: Deploy ──
section "3/6" "Deploying app"

if [ -f "$SCRIPT_DIR/../webserver_new.py" ]; then
  step "Deploy webserver" \
    "cp '$SCRIPT_DIR/../webserver_new.py' '$PI_HOME/src/webserver.py'"
  step "Deploy frontend" \
    "cp '$SCRIPT_DIR/../main.html' '$PI_HOME/src/templates/main.html'"
else
  warn "Webserver/frontend skipped — run deploy.sh from repo root"
fi

step "Install helper scripts" \
  "cp '$SCRIPT_DIR/button_listener.py' '$PI_HOME/src/button_listener.py' && \
   cp '$SCRIPT_DIR/scripts/toggle_hotspot.sh' '$PI_HOME/scripts/toggle_hotspot.sh' && \
   cp '$SCRIPT_DIR/scripts/show_hotspot_screen.py' '$PI_HOME/scripts/show_hotspot_screen.py' && \
   cp '$SCRIPT_DIR/scripts/check_wifi_boot.sh' '$PI_HOME/scripts/check_wifi_boot.sh' && \
   chmod +x '$PI_HOME/scripts/toggle_hotspot.sh' '$PI_HOME/scripts/check_wifi_boot.sh'"

# ── Phase 4: Services ──
section "4/6" "Configuring services"

step "Install dnsmasq config" \
  "sudo cp '$SCRIPT_DIR/dnsmasq.conf' /etc/dnsmasq.conf"

step "Install Avahi service" \
  "sudo mkdir -p /etc/avahi/services && sudo cp '$SCRIPT_DIR/plink.avahi.service' /etc/avahi/services/plink.service && sudo systemctl restart avahi-daemon"

step "Install systemd services" \
  "sudo cp '$SCRIPT_DIR/plink-buttons.service' /etc/systemd/system/plink-buttons.service && \
   sudo cp '$SCRIPT_DIR/plink-boot-check.service' /etc/systemd/system/plink-boot-check.service && \
   sudo bash -c 'cat > /etc/systemd/system/piink.service <<SERVICE
[Unit]
Description=Plink e-ink frame server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 /home/pi/PiInk/src/webserver.py
WorkingDirectory=/home/pi/PiInk/src
User=pi
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE' && \
   sudo systemctl daemon-reload && \
   sudo systemctl enable piink plink-buttons plink-boot-check && \
   sudo systemctl unmask hostapd 2>/dev/null || true"

# ── Phase 5: Hardware ──
section "5/6" "Configuring hardware"

step "Enable persistent journal" \
  "sudo mkdir -p /var/log/journal && \
   MACHINE_ID=\$(sudo cat /etc/machine-id) && \
   sudo mkdir -p /var/log/journal/\$MACHINE_ID && \
   sudo chown root:systemd-journal /var/log/journal/\$MACHINE_ID && \
   sudo chmod 2755 /var/log/journal/\$MACHINE_ID && \
   sudo systemctl restart systemd-journald"

step "Enable SPI bus" \
  "sudo sed -i 's/^#dtparam=spi=on/dtparam=spi=on/' /boot/firmware/config.txt && \
   grep -q 'dtoverlay=spi0-0cs' /boot/firmware/config.txt || sudo sh -c \"echo 'dtoverlay=spi0-0cs' >> /boot/firmware/config.txt\""

step "Patch Inky display driver" \
  "sudo python3 '$SCRIPT_DIR/patch_inky.py'"

# ── Phase 6: Network ──
section "6/6" "Configuring network"

step "Disable WiFi power save" \
  "sudo mkdir -p /etc/NetworkManager/conf.d && \
   printf '[connection]\nwifi.powersave=2\n' | sudo tee /etc/NetworkManager/conf.d/wifi-powersave.conf >/dev/null && \
   sudo systemctl restart NetworkManager"

sleep 3

CON=$(nmcli -t -f NAME connection show --active 2>/dev/null | grep wlan | head -1 || true)
if [ -n "$CON" ]; then
  step "Set static IP" \
    "sudo nmcli connection modify '$CON' \
       ipv4.addresses 192.168.1.50/24 \
       ipv4.gateway 192.168.1.1 \
       ipv4.dns '8.8.8.8 1.1.1.1' \
       ipv4.method manual \
       ipv6.method link-local"
else
  warn "No active wlan0 connection — skipping static IP. Set manually with nmcli."
fi

step "Start frame server" \
  "sudo systemctl start piink"

# ── Optional: Tailscale ──
if [ "${SETUP_TAILSCALE:-n}" = "y" ] || [ "${SETUP_TAILSCALE:-n}" = "Y" ]; then
  echo ""
  printf "${CYAN}${BOLD}[+] Installing Tailscale${NC}\n"
  echo ""

  step "Install Tailscale" \
    "curl -fsSL https://tailscale.com/install.sh | sudo sh -s -- -yes 2>&1"

  if [ -n "${TAILSCALE_AUTH_KEY:-}" ]; then
    step "Connect to Tailscale" \
      "sudo tailscale up --auth-key='$TAILSCALE_AUTH_KEY' --accept-routes"
    TS_IP=$(sudo tailscale ip 2>/dev/null | head -1 || true)
    [ -n "$TS_IP" ] && printf "  ${DIM}Tailscale IP: %s${NC}\n" "$TS_IP"
  else
    sudo tailscale up > /tmp/tailscale-auth.log 2>&1 &
    sleep 4
    AUTH_URL=$(grep -o 'https://login\.tailscale\.com[^ ]*' /tmp/tailscale-auth.log 2>/dev/null | head -1 || true)
    if [ -n "$AUTH_URL" ]; then
      printf "  ${YELLOW}${BOLD}Authenticate Tailscale:${NC}\n"
      printf "  Open in your browser:\n\n"
      printf "    ${CYAN}${BOLD}%s${NC}\n\n" "$AUTH_URL"
      printf "  ${DIM}Waiting for authentication${NC}"
      until sudo tailscale ip 2>/dev/null | grep -q '100\.'; do
        printf "."
        sleep 3
      done
      printf "\r  ${GREEN}✓${NC} Tailscale authenticated                  \n"
      TS_IP=$(sudo tailscale ip 2>/dev/null | head -1 || true)
      [ -n "$TS_IP" ] && printf "  ${DIM}Tailscale IP: %s${NC}\n" "$TS_IP"
    else
      warn "Run 'sudo tailscale up' manually to authenticate."
    fi
  fi
fi

echo ""
divider
echo ""
printf "  ${GREEN}${BOLD}Plink installed${NC}\n"
echo ""
divider
echo ""
printf "  Frame is live at:\n\n"
printf "    ${CYAN}${BOLD}http://pi.local${NC}\n"
printf "    ${CYAN}http://192.168.1.50${NC}\n"
echo ""
printf "  ${DIM}Hold Button A for 1.5s to toggle hotspot mode.${NC}\n"
echo ""
