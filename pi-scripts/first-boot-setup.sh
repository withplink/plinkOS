#!/bin/bash

set -e

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

SSH="sshpass -p $PI_PASS ssh -q -o StrictHostKeyChecking=no -o LogLevel=ERROR $PI"
SCP="sshpass -p $PI_PASS scp -q -o StrictHostKeyChecking=no -o LogLevel=ERROR"

echo "=== Waiting for Pi to come online ==="

until sshpass -p "$PI_PASS" ssh -q -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=5 \
  "$PI" "echo ok" 2>/dev/null; do

  echo "not reachable yet, retrying in 5s..."
  sleep 5
done

echo "Pi is up."

echo ""
echo "=== Enable passwordless sudo ==="

$SSH "echo '$PI_PASS' | sudo -S bash -c '
echo \"pi ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/pi
chmod 440 /etc/sudoers.d/pi
'"

echo ""
echo "=== Static IP + IPv6 link-local ==="

$SSH <<'REMOTE'
sudo bash <<'EOF'
CON=$(nmcli -t -f NAME connection show --active | grep wlan | head -1)

nmcli connection modify "$CON" \
  ipv4.addresses 192.168.1.50/24 \
  ipv4.gateway 192.168.1.1 \
  ipv4.dns "8.8.8.8 1.1.1.1" \
  ipv4.method manual \
  ipv6.method link-local

echo "Static IP profile saved — will apply after reboot"
EOF
REMOTE

echo ""
echo "=== Disable WiFi power save ==="

$SSH <<'REMOTE'
sudo bash <<'EOF'
mkdir -p /etc/NetworkManager/conf.d

cat > /etc/NetworkManager/conf.d/wifi-powersave.conf <<CONF
[connection]
wifi.powersave=2
CONF

systemctl restart NetworkManager
sleep 3
EOF
REMOTE

echo ""
echo "=== Create directory structure ==="

$SSH "
mkdir -p \
  $PI_HOME/src/templates \
  $PI_HOME/config \
  $PI_HOME/uploads \
  $PI_HOME/scripts
"

echo ""
echo "=== Install Python deps ==="

$SSH "
sudo pip3 install --break-system-packages \
  flask \
  pillow \
  'inky[rpi,fonts]' \
  'qrcode[pil]'
"

echo ""
echo "=== Patch Inky library for GPIO/SPI compatibility ==="

$SCP pi-scripts/patch_inky.py "$PI:/tmp/patch_inky.py"
$SSH "sudo python3 /tmp/patch_inky.py"

echo ""
echo "=== Install system deps ==="

$SSH "
sudo apt-get update -qq
sudo apt-get install -y dnsmasq hostapd avahi-daemon
"

echo ""
echo "=== Deploy webserver + frontend ==="

$SCP webserver_new.py \
  "$PI:$PI_HOME/src/webserver.py"

$SCP main.html \
  "$PI:$PI_HOME/src/templates/main.html"

echo ""
echo "=== Enable SPI + disable CS conflict in boot config ==="

$SSH "
sudo sed -i 's/^#dtparam=spi=on/dtparam=spi=on/' /boot/firmware/config.txt
grep -q 'dtoverlay=spi0-0cs' /boot/firmware/config.txt || sudo sh -c \"echo 'dtoverlay=spi0-0cs' >> /boot/firmware/config.txt\"
echo 'Boot config updated — reboot required for changes to take effect'
"

echo ""
echo "=== Install scripts ==="

$SCP pi-scripts/scripts/toggle_hotspot.sh \
  "$PI:$PI_HOME/scripts/toggle_hotspot.sh"

$SCP pi-scripts/scripts/show_hotspot_screen.py \
  "$PI:$PI_HOME/scripts/show_hotspot_screen.py"

$SCP pi-scripts/scripts/check_wifi_boot.sh \
  "$PI:$PI_HOME/scripts/check_wifi_boot.sh"

$SCP pi-scripts/button_listener.py \
  "$PI:$PI_HOME/src/button_listener.py"

$SSH "
chmod +x \
  $PI_HOME/scripts/toggle_hotspot.sh \
  $PI_HOME/scripts/check_wifi_boot.sh
"

echo ""
echo "=== Install dnsmasq config ==="

$SCP pi-scripts/dnsmasq.conf \
  "$PI:/tmp/dnsmasq.conf"

$SSH "
sudo cp /tmp/dnsmasq.conf /etc/dnsmasq.conf
"

echo ""
echo "=== Install systemd services ==="

$SCP pi-scripts/plink-buttons.service \
  "$PI:/tmp/plink-buttons.service"

$SCP pi-scripts/plink-boot-check.service \
  "$PI:/tmp/plink-boot-check.service"

$SSH <<'REMOTE'
sudo bash <<'EOF'
cp /tmp/plink-buttons.service \
  /etc/systemd/system/plink-buttons.service

cp /tmp/plink-boot-check.service \
  /etc/systemd/system/plink-boot-check.service

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

systemctl enable \
  piink \
  plink-buttons \
  plink-boot-check

systemctl unmask hostapd || true
EOF
REMOTE

echo ""
echo "=== Install Avahi service ==="

$SCP pi-scripts/plink.avahi.service \
  "$PI:/tmp/plink.avahi.service"

$SSH <<'REMOTE'
sudo bash <<'EOF'
mkdir -p /etc/avahi/services

cp /tmp/plink.avahi.service \
  /etc/avahi/services/plink.service

systemctl restart avahi-daemon
EOF
REMOTE

echo ""
echo "=== Start piink ==="

$SSH "
sudo reboot
"

echo "Pi is rebooting (boot config changes require reboot)..."
echo "Waiting for Pi to come back online..."

until sshpass -p "$PI_PASS" ssh -q -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=5 \
  "$PI" "echo ok" 2>/dev/null; do

  echo "not reachable yet, retrying in 5s..."
  sleep 5
done

echo "Pi is back online."

sleep 3

$SSH "
sudo systemctl start piink
sleep 3
sudo systemctl status piink --no-pager | head -10
"

echo ""
echo "=== Done ==="
echo "http://pi.local"
echo "http://192.168.1.50"