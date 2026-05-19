#!/bin/bash
# Run from repo root on your Mac after flashing Pi OS and first boot.
# Usage: bash pi-scripts/first-boot-setup.sh
#
# Prerequisites:
#   - Pi flashed with Pi OS Lite (Bookworm 64-bit)
#   - Hostname: pi, user: pi, password: 5409, SSH enabled, home WiFi configured
#   - sshpass installed on Mac: brew install sshpass

set -e

PI="pi@pi.local"
PASS="5409"
PI_HOME="/home/pi/PiInk"
SSH="sshpass -p $PASS ssh -o StrictHostKeyChecking=no $PI"
SCP="sshpass -p $PASS scp -o StrictHostKeyChecking=no"

echo "=== Waiting for Pi to come online ==="
until sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$PI" "echo ok" 2>/dev/null; do
    echo "  not reachable yet, retrying in 5s..."
    sleep 5
done
echo "  Pi is up."

echo ""
echo "=== Static IP + IPv6 link-local ==="
$SSH "bash -s" <<'REMOTE'
CON=$(nmcli -t -f NAME connection show --active | grep wlan | head -1)
sudo nmcli connection modify "$CON" \
    ipv4.addresses 192.168.1.50/24 \
    ipv4.gateway 192.168.1.1 \
    ipv4.dns "8.8.8.8 1.1.1.1" \
    ipv4.method manual \
    ipv6.method link-local
sudo nmcli connection up "$CON"
REMOTE

echo ""
echo "=== Disable WiFi power save ==="
$SSH "bash -s" <<'REMOTE'
sudo mkdir -p /etc/NetworkManager/conf.d
sudo tee /etc/NetworkManager/conf.d/wifi-powersave.conf > /dev/null <<EOF
[connection]
wifi.powersave=2
EOF
sudo systemctl restart NetworkManager
sleep 3
REMOTE

echo ""
echo "=== Create directory structure ==="
$SSH "mkdir -p $PI_HOME/src/templates $PI_HOME/config $PI_HOME/uploads $PI_HOME/scripts"

echo ""
echo "=== Install Python deps ==="
$SSH "pip3 install --break-system-packages flask pillow 'inky[rpi,fonts]' qrcode[pil] RPi.GPIO 2>/dev/null || pip3 install flask pillow 'inky[rpi,fonts]' 'qrcode[pil]' RPi.GPIO"

echo ""
echo "=== Install system deps ==="
$SSH "sudo apt-get update -qq && sudo apt-get install -y dnsmasq hostapd"

echo ""
echo "=== Deploy webserver + frontend ==="
$SCP webserver_new.py "$PI:$PI_HOME/src/webserver.py"
$SCP main.html "$PI:$PI_HOME/src/templates/main.html"

echo ""
echo "=== Install pi-scripts ==="
$SCP pi-scripts/scripts/toggle_hotspot.sh       "$PI:$PI_HOME/scripts/toggle_hotspot.sh"
$SCP pi-scripts/scripts/show_hotspot_screen.py  "$PI:$PI_HOME/scripts/show_hotspot_screen.py"
$SCP pi-scripts/scripts/check_wifi_boot.sh      "$PI:$PI_HOME/scripts/check_wifi_boot.sh"
$SCP pi-scripts/button_listener.py              "$PI:$PI_HOME/src/button_listener.py"
$SSH "chmod +x $PI_HOME/scripts/toggle_hotspot.sh $PI_HOME/scripts/check_wifi_boot.sh"

echo ""
echo "=== Install dnsmasq config ==="
$SCP pi-scripts/dnsmasq.conf "$PI:/tmp/dnsmasq.conf"
$SSH "sudo cp /tmp/dnsmasq.conf /etc/dnsmasq.conf"

echo ""
echo "=== Install systemd services ==="
$SCP pi-scripts/plink-buttons.service      "$PI:/tmp/plink-buttons.service"
$SCP pi-scripts/plink-boot-check.service   "$PI:/tmp/plink-boot-check.service"
$SSH "bash -s" <<'REMOTE'
sudo cp /tmp/plink-buttons.service      /etc/systemd/system/plink-buttons.service
sudo cp /tmp/plink-boot-check.service   /etc/systemd/system/plink-boot-check.service

sudo tee /etc/systemd/system/piink.service > /dev/null <<EOF
[Unit]
Description=Plink e-ink frame server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 /home/pi/PiInk/src/webserver.py
WorkingDirectory=/home/pi/PiInk/src
User=root
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable piink plink-buttons plink-boot-check
sudo systemctl unmask hostapd || true
REMOTE

echo ""
echo "=== Install Avahi service ==="
$SCP pi-scripts/plink.avahi.service "$PI:/tmp/plink.avahi.service"
$SSH "sudo cp /tmp/plink.avahi.service /etc/avahi/services/plink.service && sudo systemctl restart avahi-daemon"

echo ""
echo "=== Start piink ==="
$SSH "echo '$PASS' | sudo -S systemctl start piink"
sleep 3
$SSH "sudo systemctl status piink --no-pager | head -20"

echo ""
echo "=== Done ==="
echo "Frame should be live at http://pi.local"
echo "If display shows nothing, wait 30s for first render."
