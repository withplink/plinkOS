#!/bin/bash
# Push webserver + frontend to Pi and restart the frame service.
# Usage: bash push.sh [--verbose]

set -e

VERBOSE=0
for arg in "$@"; do
  if [ "$arg" = "--verbose" ] || [ "$arg" = "-v" ]; then
    VERBOSE=1
  fi
done

# Load .env
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  source "$SCRIPT_DIR/.env"
  set +a
fi

PI_USER="${PI_USER:-pi}"
PI_HOST="${PI_HOST:-pi.local}"
if [ -z "${PI_PASS:-}" ]; then
  echo "Error: PI_PASS not set. Copy .env.example to .env and fill in your Pi password."
  exit 1
fi

HOST="$PI_USER@$PI_HOST"
SSH="sshpass -p $PI_PASS ssh -T -q -o StrictHostKeyChecking=no -o LogLevel=ERROR $HOST"
SCP="sshpass -p $PI_PASS scp -q -o StrictHostKeyChecking=no -o LogLevel=ERROR"
LOG_FILE="/tmp/plink-deploy.log"

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
  if [ "$VERBOSE" -eq 1 ]; then
    printf "  ${DIM}→${NC} %s\n" "$label"
    eval "$@" 2>&1
  else
    local i=0
    while true; do
      printf "\r  ${YELLOW}%s${NC} %s" "${SPINNER_CHARS[$((i % ${#SPINNER_CHARS[@]}))]}" "$label"
      i=$((i + 1))
      sleep 0.1
      if kill -0 $! 2>/dev/null; then true; else break; fi
    done &
    local pid=$!
    if eval "$@" >>"$LOG_FILE" 2>&1; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      printf "\r  ${GREEN}✓${NC} %s\n" "$label"
    else
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      printf "\r  ${RED}✗${NC} %s (run with -v to see logs)\n" "$label"
      exit 1
    fi
  fi
}

divider() {
  printf "${DIM}%s${NC}\n" "────────────────────────────────────────"
}

echo "" > "$LOG_FILE"
echo ""

# ── Phase 1: Deploy ──
section "1/2" "Deploying files"

step "Upload webserver" \
  "$SCP webserver_new.py '$HOST:/home/pi/PiInk/src/webserver.py'"

step "Upload frontend" \
  "$SCP main.html '$HOST:/home/pi/PiInk/src/templates/main.html'"

step "Upload hotspot screen" \
  "$SCP pi-scripts/scripts/show_hotspot_screen.py '$HOST:/home/pi/PiInk/scripts/show_hotspot_screen.py'"

step "Upload hotspot toggle" \
  "$SCP pi-scripts/scripts/toggle_hotspot.sh '$HOST:/home/pi/PiInk/scripts/toggle_hotspot.sh'"

step "Upload resize script" \
  "$SCP pi-scripts/resize_images.py '$HOST:/home/pi/PiInk/scripts/resize_images.py'"

step "Create assets dir on Pi" \
  "$SSH 'mkdir -p /home/pi/PiInk/assets'"

step "Upload unbox screen asset" \
  "$SCP pi-scripts/assets/unbox_screen.png '$HOST:/home/pi/PiInk/assets/unbox_screen.png'"

step "Upload empty queue screen asset" \
  "$SCP pi-scripts/assets/empty_queue_screen.png '$HOST:/home/pi/PiInk/assets/empty_queue_screen.png'"

step "Upload no wifi screen asset" \
  "$SCP pi-scripts/assets/no_wifi_screen.png '$HOST:/home/pi/PiInk/assets/no_wifi_screen.png'"

step "Upload AP screen asset" \
  "$SCP pi-scripts/assets/ap_screen.png '$HOST:/home/pi/PiInk/assets/ap_screen.png'"

# ── Phase 2: Restart ──
section "2/2" "Restarting frame"

DISPLAY_MODEL="${DISPLAY_MODEL:-Inky Impression 7.3\"}"
_step_display_model() {
  # Pipe printf output through SSH stdin into cat — sudo must not intercept stdin via echo|sudo -S
  printf '[Service]\nEnvironment=DISPLAY_MODEL=%s\n' "$DISPLAY_MODEL" | \
    sshpass -p "$PI_PASS" ssh -T -q -o StrictHostKeyChecking=no -o LogLevel=ERROR "$PI_USER@$PI_HOST" \
      "sudo bash -c 'mkdir -p /etc/systemd/system/piink.service.d && cat > /etc/systemd/system/piink.service.d/display.conf && systemctl daemon-reload'"
}
step "Set display model ($DISPLAY_MODEL)" _step_display_model

step "Restart piink service" \
  "$SSH \"echo '$PI_PASS' | sudo -S systemctl restart piink\""

step "Verify frame is running" \
  "$SSH 'sudo systemctl is-active piink | grep -q active'"

echo ""
divider
echo ""
printf "  ${GREEN}${BOLD}Deploy complete${NC}\n"
echo ""
divider
echo ""
printf "  ${CYAN}${BOLD}http://%s${NC}\n" "$PI_HOST"
echo ""
if [ "$VERBOSE" -eq 0 ]; then
  printf "  ${DIM}Detailed logs: cat %s${NC}\n" "$LOG_FILE"
  echo ""
fi
