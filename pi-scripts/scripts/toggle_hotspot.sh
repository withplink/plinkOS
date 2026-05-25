#!/bin/bash
# Toggles Pi between WiFi client mode and plink-setup AP mode.
# Uses NetworkManager (nmcli) — NM manages hostapd + DHCP internally.
# State tracked via /tmp/plink_ap_mode flag file.
# Screen rendering done via webserver API (localhost) — webserver owns the display.

FLAG="/tmp/plink_ap_mode"
HOME_CON_FILE="/tmp/plink_home_con"
SETTINGS="/home/pi/PiInk/config/settings.json"
QUEUE="/home/pi/PiInk/config/queue.json"
HOTSPOT_CON="plink-ap"
LOG_TAG="plink-hotspot"

log() { logger -t "$LOG_TAG" "$*"; echo "$*"; }

AP_PASS=$(python3 -c "
import json
try:
    d = json.load(open('$SETTINGS'))
    print(d.get('ap_password', 'plink123'))
except Exception:
    print('plink123')
" 2>/dev/null || echo "plink123")

render_screen() {
    log "render_screen: mode=$1"
    local RESP=""
    for i in 1 2 3 4 5; do
        RESP=$(curl -s -w '\nHTTP:%{http_code}' --max-time 5 -X POST http://localhost/api/hotspot/screen \
            -H "Content-Type: application/json" \
            -d "{\"mode\": \"$1\", \"password\": \"$AP_PASS\"}" 2>&1)
        if echo "$RESP" | grep -q "HTTP:2"; then
            break
        fi
        log "render_screen attempt $i failed (${RESP}), retrying in 2s..."
        sleep 2
    done
    log "render_screen response: $RESP"
}

if [ -f "$FLAG" ]; then
    log "AP mode active — switching back to WiFi client"

    OUT=$(sudo nmcli con down "$HOTSPOT_CON" 2>&1); log "nmcli con down: $OUT"
    OUT=$(sudo nmcli con delete "$HOTSPOT_CON" 2>&1); log "nmcli con delete: $OUT"
    OUT=$(sudo systemctl start dnsmasq 2>&1); log "systemctl start dnsmasq: $OUT"

    # Re-enable autoconnect on home WiFi and reconnect
    HOME_CON=""
    if [ -f "$HOME_CON_FILE" ]; then
        HOME_CON=$(cat "$HOME_CON_FILE")
        rm -f "$HOME_CON_FILE"
    fi

    # Re-enable autoconnect on home WiFi (so NM doesn't ignore it)
    if [ -n "$HOME_CON" ]; then
        OUT=$(sudo nmcli con modify "$HOME_CON" connection.autoconnect yes 2>&1)
        log "re-enable autoconnect on '$HOME_CON': $OUT"
    fi
    # Let NM auto-pick the best autoconnect profile (may be a new one submitted via /api/wifi)
    OUT=$(sudo nmcli device connect wlan0 2>&1); RET=$?
    log "nmcli device connect wlan0: ret=$RET out=$OUT"

    rm -f "$FLAG"

    (
        CONNECTED=0
        for i in $(seq 1 30); do
            sleep 5
            if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
                CONNECTED=1
                log "Internet connected after ${i} attempts — restoring display"
                sudo systemctl restart avahi-daemon
                QUEUE_LEN=$(python3 -c "
import json
try:
    q = json.load(open('$QUEUE'))
    print(len(q.get('items', [])))
except Exception:
    print(0)
" 2>/dev/null || echo 0)
                if [ "$QUEUE_LEN" -gt 0 ]; then
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
                else
                    render_screen default
                fi
                break
            else
                log "Ping attempt $i failed — waiting for WiFi"
            fi
        done
        if [ "$CONNECTED" -eq 0 ]; then
            log "No internet after 150s — reverting to AP mode"
            bash "$0"
        fi
    ) &
else
    log "WiFi client mode — switching to AP mode"

    OUT=$(sudo nmcli con delete "$HOTSPOT_CON" 2>&1); log "nmcli con delete (pre-clean): $OUT"

    # Save current home WiFi connection name so we can restore it later
    HOME_CON=$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | grep ":wlan0$" | cut -d: -f1 | head -1)
    log "current home connection: '$HOME_CON'"
    echo "$HOME_CON" > "$HOME_CON_FILE"

    # Disable autoconnect on home WiFi so NM doesn't kick hotspot off wlan0
    if [ -n "$HOME_CON" ]; then
        OUT=$(sudo nmcli con modify "$HOME_CON" connection.autoconnect no 2>&1)
        log "disable autoconnect on '$HOME_CON': $OUT"
    fi

    # Stop dnsmasq so NM can start its own instance for DHCP on the hotspot
    OUT=$(sudo systemctl stop dnsmasq 2>&1); log "systemctl stop dnsmasq: $OUT"

    # Disconnect wlan0 from home WiFi
    OUT=$(sudo nmcli device disconnect wlan0 2>&1); log "nmcli device disconnect wlan0: $OUT"

    OUT=$(sudo nmcli device wifi hotspot ifname wlan0 ssid plink-setup password "$AP_PASS" con-name "$HOTSPOT_CON" 2>&1)
    RET=$?
    log "nmcli device wifi hotspot: ret=$RET out=$(echo "$OUT" | cat -v)"

    # Log full device state immediately after hotspot command returns
    DEV_STATE=$(nmcli device status 2>&1)
    log "device status immediately after hotspot: $DEV_STATE"

    if [ $RET -ne 0 ]; then
        log "Hotspot creation failed — trying explicit connection add"
        OUT=$(sudo nmcli con add type wifi ifname wlan0 con-name "$HOTSPOT_CON" ssid plink-setup \
            wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$AP_PASS" \
            802-11-wireless.mode ap \
            ipv4.method shared \
            connection.autoconnect no 2>&1)
        log "nmcli con add: $OUT"
        OUT=$(sudo nmcli con up "$HOTSPOT_CON" 2>&1); RET=$?
        log "nmcli con up fallback: ret=$RET out=$OUT"
    fi

    # Wait for connection to stabilize
    sleep 3
    DEV_STATE=$(nmcli device status 2>&1)
    log "device status after 3s: $DEV_STATE"
    WLAN_CON=$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | grep ":wlan0$" | cut -d: -f1 | head -1)
    log "wlan0 active connection after hotspot: '$WLAN_CON'"

    if [ "$WLAN_CON" = "$HOTSPOT_CON" ]; then
        log "Hotspot active — setting flag and rendering QR screen"
        touch "$FLAG"
        render_screen ap
        sudo systemctl restart avahi-daemon
    else
        log "Hotspot FAILED — wlan0 is on '$WLAN_CON', not '$HOTSPOT_CON'. Re-enabling home WiFi."
        if [ -n "$HOME_CON" ]; then
            sudo nmcli con modify "$HOME_CON" connection.autoconnect yes 2>/dev/null
            sudo nmcli con up "$HOME_CON" ifname wlan0 2>/dev/null
        fi
        rm -f "$HOME_CON_FILE"
    fi
fi
