#!/bin/bash
# Toggles Pi between WiFi client mode and plink-setup AP mode.
# State tracked via /tmp/plink_ap_mode flag file.

set -e

FLAG="/tmp/plink_ap_mode"
SETTINGS="/home/pi/PiInk/config/settings.json"
SHOW_SCREEN="/home/pi/PiInk/scripts/show_hotspot_screen.py"

# Read AP password from settings.json; fall back to a default
AP_PASS=$(python3 -c "
import json, sys
try:
    d = json.load(open('$SETTINGS'))
    print(d.get('ap_password', 'plink123'))
except Exception:
    print('plink123')
" 2>/dev/null || echo "plink123")

if [ -f "$FLAG" ]; then
    echo "AP mode active — switching back to WiFi client"

    systemctl stop hostapd dnsmasq || true
    ip addr flush dev wlan0 || true
    systemctl start wpa_supplicant || true
    systemctl start dhcpcd || true

    rm -f "$FLAG"

    python3 "$SHOW_SCREEN" client
    systemctl restart avahi-daemon
else
    echo "WiFi client mode — switching to AP mode"

    systemctl stop wpa_supplicant dhcpcd || true

    ip link set wlan0 up
    ip addr add 192.168.4.1/24 dev wlan0 || true

    # Write hostapd config with current password
    cat > /etc/hostapd/plink.conf <<EOF
interface=wlan0
driver=nl80211
ssid=plink-setup
hw_mode=g
channel=6
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$AP_PASS
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

    HOSTAPD_CONF=/etc/hostapd/plink.conf hostapd -B /etc/hostapd/plink.conf

    # Restart dnsmasq with DHCP range
    systemctl restart dnsmasq

    touch "$FLAG"

    python3 "$SHOW_SCREEN" ap "$AP_PASS"
    systemctl restart avahi-daemon
fi
