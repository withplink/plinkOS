#!/bin/bash
set -e

HOST="pi@pi.local"
PASS="5409"

sshpass -p "$PASS" scp webserver_new.py "$HOST":/home/pi/PiInk/src/webserver.py
sshpass -p "$PASS" scp main.html "$HOST":/home/pi/PiInk/src/templates/main.html
sshpass -p "$PASS" ssh "$HOST" "echo '$PASS' | sudo -S systemctl restart piink && echo done"

# Uncomment to also deploy pi-scripts (hotspot + button listener):
# cd pi-scripts && sshpass -p "$PASS" scp -r . "$HOST":/tmp/plink-scripts
# sshpass -p "$PASS" ssh "$HOST" "cd /tmp/plink-scripts && bash install.sh"
