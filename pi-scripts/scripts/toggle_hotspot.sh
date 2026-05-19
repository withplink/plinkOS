#!/bin/bash
# Toggles Pi between WiFi client mode and plink-setup AP mode.
# Uses NetworkManager (nmcli) — NM manages hostapd + DHCP internally.
# State tracked via /tmp/plink_ap_mode flag file.

FLAG="/tmp/plink_ap_mode"
SETTINGS="/home/pi/PiInk/config/settings.json"
QUEUE="/home/pi/PiInk/config/queue.json"
SHOW_SCREEN="/home/pi/PiInk/scripts/show_hotspot_screen.py"
HOTSPOT_CON="plink-ap"

AP_PASS=$(python3 -c "
import json
try:
    d = json.load(open('$SETTINGS'))
    print(d.get('ap_password', 'plink123'))
except Exception:
    print('plink123')
" 2>/dev/null || echo "plink123")

if [ -f "$FLAG" ]; then
    echo "AP mode active — switching back to WiFi client"

    nmcli con down "$HOTSPOT_CON" 2>/dev/null || true
    nmcli con delete "$HOTSPOT_CON" 2>/dev/null || true

    # Reconnect to saved WiFi
    nmcli device connect wlan0 || true

    rm -f "$FLAG"

    python3 "$SHOW_SCREEN" client

    # Once WiFi reconnects, announce via mDNS and restore current image on display.
    # If internet never comes up (wrong network saved), revert to AP mode.
    (
        CONNECTED=0
        for i in $(seq 1 30); do
            sleep 5
            if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
                CONNECTED=1
                systemctl restart avahi-daemon
                CURRENT=$(python3 -c "
import json
try:
    q = json.load(open('$QUEUE'))
    print(q.get('current', 0))
except Exception:
    print(0)
" 2>/dev/null || echo 0)
                curl -s -X POST http://localhost/api/queue/show \
                    -H "Content-Type: application/json" \
                    -d "{\"index\": $CURRENT}" >/dev/null 2>&1
                break
            fi
        done
        if [ "$CONNECTED" -eq 0 ]; then
            echo "No internet after 150s — reverting to AP mode."
            bash "$0"
        fi
    ) &
else
    echo "WiFi client mode — switching to AP mode"

    nmcli device wifi hotspot ifname wlan0 ssid plink-setup password "$AP_PASS" con-name "$HOTSPOT_CON"

    touch "$FLAG"

    python3 "$SHOW_SCREEN" ap "$AP_PASS"
    systemctl restart avahi-daemon
fi
