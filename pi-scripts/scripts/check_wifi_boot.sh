#!/bin/bash
# On boot: if no WiFi profiles saved (NM), or wlan0 fails to get an IP, start AP mode.
# Runs once via plink-boot-check.service before piink.service starts.

TOGGLE="/home/pi/PiInk/scripts/toggle_hotspot.sh"
FLAG="/tmp/plink_ap_mode"

if [ -f "$FLAG" ]; then
    echo "Already in AP mode, skipping boot check."
    exit 0
fi

# Check if any wifi profiles exist in NetworkManager
WIFI_PROFILES=$(nmcli -t -f TYPE connection show | grep -c '^802-11-wireless$' 2>/dev/null || echo 0)
if [ "$WIFI_PROFILES" -eq 0 ]; then
    echo "No WiFi profiles configured — starting AP mode."
    bash "$TOGGLE"
    exit 0
fi

# Wait up to 30s for wlan0 to get an IP
for i in $(seq 1 6); do
    sleep 5
    IP=$(ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [ -n "$IP" ]; then
        echo "WiFi connected: $IP — checking internet..."
        break
    fi
done

if [ -z "$IP" ]; then
    echo "wlan0 got no IP after 30s — starting AP mode."
    bash "$TOGGLE"
    exit 0
fi

# Got an IP — verify internet reachability (wrong WiFi has DHCP but no route to us)
for i in $(seq 1 6); do
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        echo "Internet reachable."
        exit 0
    fi
    sleep 5
done

echo "Got IP but no internet after 30s — starting AP mode."
bash "$TOGGLE"
