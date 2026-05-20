#!/bin/bash
# Full Plink install — runs ON the Pi.
# Usage: sshpass -p '5409' ssh pi@pi.local 'bash -s' < pi-scripts/install.sh
# Or copy to Pi and run: bash install.sh

set -e

PI_HOME=/home/pi/PiInk
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Enable passwordless sudo ==="
echo "pi ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/pi >/dev/null
sudo chmod 440 /etc/sudoers.d/pi

echo ""
echo "=== Create directory structure ==="
mkdir -p "$PI_HOME/src/templates" "$PI_HOME/config" "$PI_HOME/uploads" "$PI_HOME/scripts"

echo ""
echo "=== Install system deps ==="
sudo apt-get update -qq
sudo apt-get install -y dnsmasq hostapd avahi-daemon

echo ""
echo "=== Install Python deps ==="
pip3 install --break-system-packages \
  flask pillow 'inky[rpi,fonts]' 'qrcode[pil]' zeroconf RPi.GPIO 2>/dev/null || \
pip3 install flask pillow 'inky[rpi,fonts]' 'qrcode[pil]' zeroconf RPi.GPIO

echo ""
echo "=== Deploy webserver + frontend ==="
cp "$SCRIPT_DIR/../webserver_new.py" "$PI_HOME/src/webserver.py"
cp "$SCRIPT_DIR/../main.html"          "$PI_HOME/src/templates/main.html"

echo ""
echo "=== Install scripts ==="
cp "$SCRIPT_DIR/button_listener.py"              "$PI_HOME/src/button_listener.py"
cp "$SCRIPT_DIR/scripts/toggle_hotspot.sh"       "$PI_HOME/scripts/toggle_hotspot.sh"
cp "$SCRIPT_DIR/scripts/show_hotspot_screen.py"  "$PI_HOME/scripts/show_hotspot_screen.py"
cp "$SCRIPT_DIR/scripts/check_wifi_boot.sh"      "$PI_HOME/scripts/check_wifi_boot.sh"
chmod +x "$PI_HOME/scripts/toggle_hotspot.sh" "$PI_HOME/scripts/check_wifi_boot.sh"

echo ""
echo "=== Install dnsmasq config ==="
sudo cp "$SCRIPT_DIR/dnsmasq.conf" /etc/dnsmasq.conf

echo ""
echo "=== Unmask + enable hostapd ==="
sudo systemctl unmask hostapd || true
sudo systemctl enable hostapd || true

echo ""
echo "=== Install systemd services ==="
sudo cp "$SCRIPT_DIR/plink-buttons.service"  /etc/systemd/system/plink-buttons.service
sudo cp "$SCRIPT_DIR/plink-boot-check.service" /etc/systemd/system/plink-boot-check.service

cat > /tmp/piink.service <<'SERVICE'
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
SERVICE
sudo cp /tmp/piink.service /etc/systemd/system/piink.service

sudo systemctl daemon-reload
sudo systemctl enable piink plink-buttons plink-boot-check

echo ""
echo "=== Install Avahi service ==="
sudo mkdir -p /etc/avahi/services
sudo cp "$SCRIPT_DIR/plink.avahi.service" /etc/avahi/services/plink.service
sudo systemctl restart avahi-daemon

echo ""
echo "=== Disable WiFi power save ==="
sudo mkdir -p /etc/NetworkManager/conf.d
cat > /tmp/wifi-powersave.conf <<'CONF'
[connection]
wifi.powersave=2
CONF
sudo cp /tmp/wifi-powersave.conf /etc/NetworkManager/conf.d/wifi-powersave.conf
sudo systemctl restart NetworkManager
sleep 3

echo ""
echo "=== Set static IP + IPv6 link-local ==="
CON=$(nmcli -t -f NAME connection show --active | grep wlan | head -1)
if [ -n "$CON" ]; then
  sudo nmcli connection modify "$CON" \
    ipv4.addresses 192.168.1.50/24 \
    ipv4.gateway 192.168.1.1 \
    ipv4.dns "8.8.8.8 1.1.1.1" \
    ipv4.method manual \
    ipv6.method link-local
  sudo nmcli connection up "$CON"
  sleep 3
else
  echo "WARNING: No active wlan0 connection found — skipping static IP."
  echo "Set it manually with: nmcli connection modify <SSID> ipv4.method manual ..."
fi

echo ""
echo "=== Start piink ==="
sudo systemctl start piink
sleep 3

echo ""
echo "=== Status ==="
sudo systemctl status piink --no-pager | head -10

echo ""
echo "=== Done ==="
echo "Frame is live at:"
echo "  http://pi.local"
echo "  http://192.168.1.50"
echo ""
echo "Hold Button A on the frame for 1.5s to toggle hotspot mode."
