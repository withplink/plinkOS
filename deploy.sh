#!/bin/bash
set -e

# Load .env if present
if [ -f "$(dirname "$0")/.env" ]; then
  set -a
  source "$(dirname "$0")/.env"
  set +a
fi

PI_USER="${PI_USER:-pi}"
PI_PASS="${PI_PASS:-5409}"
HOST="$PI_USER@pi.local"

sshpass -p "$PI_PASS" scp webserver_new.py "$HOST":/home/pi/PiInk/src/webserver.py
sshpass -p "$PI_PASS" scp main.html "$HOST":/home/pi/PiInk/src/templates/main.html
sshpass -p "$PI_PASS" ssh "$HOST" "echo '$PI_PASS' | sudo -S systemctl restart piink && echo done"

# Deploy pi-scripts (hotspot + button listener)
sshpass -p "$PI_PASS" scp -r pi-scripts/. "$HOST":/tmp/plink-scripts
sshpass -p "$PI_PASS" ssh "$HOST" "cd /tmp/plink-scripts && bash install.sh"
