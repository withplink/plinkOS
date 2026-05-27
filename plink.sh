#!/bin/bash
# Plink — e-ink frame manager
# curl -sL https://raw.githubusercontent.com/PixeledCode/plinkOS/main/plink.sh | bash

set -e

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
DIM='\033[2m'
WHITE='\033[1;37m'
DIM_WHITE='\033[2;37m'
NC='\033[0m'
BOLD='\033[1m'

SPINNER_CHARS=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

tty_read() {
  local prompt="$1" varname="$2" hidden="$3" val=""
  if [ "$hidden" = "1" ]; then
    read -s -p "$prompt" val < /dev/tty
  else
    read -p "$prompt" val < /dev/tty
  fi
  echo ""
  eval "$varname='$val'"
}

print_header() {
  echo ""
  printf "${DIM}╭────────────────────────────────╮${NC}\n"
  printf "${DIM}│${NC}  ${CYAN}░ ░░ ░ ░░ ░ ░░ ░ ░░ ░ ░░${NC}  ${DIM}│${NC}\n"
  printf "${DIM}│${NC}                                ${DIM}│${NC}\n"
  printf "${DIM}│${NC}        ${DIM}┌──────────────┐${NC}        ${DIM}│${NC}\n"
  printf "${DIM}│${NC}        ${DIM}│${NC}    ${WHITE}Plink${NC}     ${DIM}│${NC}        ${DIM}│${NC}\n"
  printf "${DIM}│${NC}        ${DIM}│${NC} ${DIM_WHITE}e-ink frame${NC}  ${DIM}│${NC}        ${DIM}│${NC}\n"
  printf "${DIM}│${NC}        ${DIM}└──────────────┘${NC}        ${DIM}│${NC}\n"
  printf "${DIM}│${NC}                                ${DIM}│${NC}\n"
  printf "${DIM}│${NC}  ${CYAN}░ ░░ ░ ░░ ░ ░░ ░ ░░ ░ ░░${NC}  ${DIM}│${NC}\n"
  printf "${DIM}╰────────────────────────────────╯${NC}\n"
  echo ""
}

divider() {
  printf "${DIM}%s${NC}\n" "────────────────────────────────────────"
}

is_pi() {
  [ -f /proc/device-tree/model ] && grep -qi "raspberry pi" /proc/device-tree/model 2>/dev/null
}

# SCRIPT_DIR: real path when run from file; pwd fallback when piped via curl
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || pwd)"

in_repo() {
  [ -f "$SCRIPT_DIR/pi-scripts/setup-remote.sh" ]
}

load_env() {
  if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a; source "$SCRIPT_DIR/.env"; set +a
  fi
}

clone_repo() {
  TMP_DIR=$(mktemp -d)
  printf "  ${YELLOW}⋯${NC} Fetching Plink"
  git clone https://github.com/PixeledCode/plinkOS.git "$TMP_DIR" >/dev/null 2>&1 &
  local pid=$! i=0
  while kill -0 $pid 2>/dev/null; do
    printf "\r  ${YELLOW}%s${NC} Fetching Plink" "${SPINNER_CHARS[$((i++ % ${#SPINNER_CHARS[@]}))]}"
    sleep 0.1
  done
  wait $pid || {
    printf "\r  ${RED}✗${NC} Fetch failed (check internet connection)\n"
    exit 1
  }
  printf "\r  ${GREEN}✓${NC} Fetching Plink\n"
  SCRIPT_DIR="$TMP_DIR"
}

ensure_sshpass() {
  if ! command -v sshpass &>/dev/null; then
    printf "  ${DIM}Installing sshpass...${NC}\n"
    if command -v brew &>/dev/null; then
      brew install sshpass >/dev/null 2>&1
    elif command -v apt-get &>/dev/null; then
      sudo apt-get install -y sshpass >/dev/null 2>&1
    else
      echo "Error: sshpass not found. Install it: brew install sshpass"
      exit 1
    fi
  fi
}

test_ssh() {
  sshpass -p "$PI_PASS" ssh -T -q \
    -o StrictHostKeyChecking=no \
    -o LogLevel=ERROR \
    -o ConnectTimeout=5 \
    "$PI_USER@$PI_HOST" echo ok >/dev/null 2>&1
}

prompt_pi_creds() {
  load_env
  PI_USER="${PI_USER:-pi}"
  PI_HOST="${PI_HOST:-pi.local}"

  if [ -n "${PI_PASS:-}" ]; then
    printf "  ${DIM}Trying saved credentials (%s@%s)...${NC}" "$PI_USER" "$PI_HOST"
    if test_ssh; then
      printf "\r  ${GREEN}✓${NC} Connected to %s@%s              \n" "$PI_USER" "$PI_HOST"
      export PI_USER PI_HOST PI_PASS
      return
    else
      printf "\r  ${RED}✗${NC} Saved credentials failed (%s@%s)\n\n" "$PI_USER" "$PI_HOST"
      PI_PASS=""
    fi
  fi

  _cred_attempts=0
  while [ $_cred_attempts -lt 3 ]; do
    echo "Where should Plink connect?"
    echo ""
    tty_read "  Hostname or IP [${PI_HOST}]: " _host
    PI_HOST="${_host:-$PI_HOST}"
    tty_read "  Username [${PI_USER}]: " _user
    PI_USER="${_user:-$PI_USER}"
    tty_read "  Password: " PI_PASS 1
    if [ -z "$PI_PASS" ]; then
      echo ""
      printf "  ${RED}Password required.${NC}\n\n"
      _cred_attempts=$((_cred_attempts + 1))
      continue
    fi
    printf "  ${DIM}Testing connection...${NC}"
    if test_ssh; then
      printf "\r  ${GREEN}✓${NC} Connected                    \n"
      break
    else
      printf "\r  ${RED}✗${NC} Connection failed — check host, username, and password.\n\n"
      PI_PASS=""
      _cred_attempts=$((_cred_attempts + 1))
    fi
  done
  if [ $_cred_attempts -ge 3 ] && [ -z "$PI_PASS" ]; then
    printf "  ${RED}Too many failed attempts. Exiting.${NC}\n"
    exit 1
  fi

  export PI_USER PI_HOST PI_PASS
}

prompt_display_model() {
  local conf="$SCRIPT_DIR/displays.conf"
  local displays=()
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^#|^[[:space:]]*$ ]] && continue
    displays+=("$line")
  done < "$conf"

  echo "Which display is installed on your frame?"
  echo ""
  local i=1
  for display in "${displays[@]}"; do
    if [ $i -eq 1 ]; then
      printf "  ${BOLD}%d.${NC} %s  ${DIM}(default)${NC}\n" $i "$display"
    else
      printf "  ${BOLD}%d.${NC} %s\n" $i "$display"
    fi
    i=$((i + 1))
  done
  echo ""
  tty_read "  Choice [1]: " _display_choice
  _display_choice="${_display_choice:-1}"
  local idx=$((_display_choice - 1))
  DISPLAY_MODEL="${displays[$idx]:-${displays[0]}}"
  export DISPLAY_MODEL
  echo ""
}

prompt_rescue_wifi() {
  _DEFAULT_RESCUE_PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 8 || \
    python3 -c "import secrets; print(secrets.token_urlsafe(6)[:8])")

  echo "Frame label — used to identify this frame (e.g. customer name, location)."
  echo ""
  tty_read "  Frame label: " FRAME_LABEL
  # Slugify: lowercase, spaces→hyphens, strip non-alphanumeric-hyphen
  FRAME_LABEL=$(echo "$FRAME_LABEL" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
  FRAME_LABEL="${FRAME_LABEL:-frame}"
  echo ""

  _DEFAULT_RESCUE_SSID="plink-rescue-${FRAME_LABEL}"

  echo "Rescue WiFi — for emergency SSH access if the frame gets stuck."
  printf "  ${DIM}Create a hotspot with these credentials on your phone or router.\n"
  printf "  Pi connects silently; setup screen still shows.\n"
  printf "  Press Enter to accept defaults.${NC}\n"
  echo ""
  tty_read "  Rescue SSID [${_DEFAULT_RESCUE_SSID}]: " _rescue_ssid
  RESCUE_SSID="${_rescue_ssid:-$_DEFAULT_RESCUE_SSID}"
  echo ""
  tty_read "  Rescue password [${_DEFAULT_RESCUE_PASS}]: " _rescue_pass
  RESCUE_PASS="${_rescue_pass:-$_DEFAULT_RESCUE_PASS}"
  echo ""
  printf "  ${GREEN}✓${NC} Rescue network: ${BOLD}${RESCUE_SSID}${NC}  password: ${BOLD}${RESCUE_PASS}${NC}\n"
  echo ""

  CUSTOMERS_DIR="$SCRIPT_DIR/../plink-private/customers"
  if [ -d "$CUSTOMERS_DIR" ]; then
    tty_read "  Save to customers log? [Y/n]: " _save_log
    if [ "${_save_log:-Y}" != "n" ] && [ "${_save_log:-Y}" != "N" ]; then
      _log_file="$CUSTOMERS_DIR/${FRAME_LABEL}.md"
      cat > "$_log_file" <<LOG
# ${FRAME_LABEL}

- **Install date:** $(date '+%Y-%m-%d')
- **Pi host:** ${PI_HOST}
- **Display:** ${DISPLAY_MODEL:-unknown}
- **Rescue SSID:** ${RESCUE_SSID}
- **Rescue password:** ${RESCUE_PASS}
LOG
      printf "  ${GREEN}✓${NC} Saved to plink-private/customers/${FRAME_LABEL}.md\n"
    fi
  fi

  export RESCUE_SSID RESCUE_PASS FRAME_LABEL
  echo ""
}

do_install() {
  if is_pi; then
    # ── On Pi ──
    if ! in_repo; then
      clone_repo
    fi
    bash "$SCRIPT_DIR/pi-scripts/setup-local.sh" "$@"
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
  else
    # ── On Mac → remote install ──
    ensure_sshpass
    if ! in_repo; then
      prompt_pi_creds
      ssh-keygen -R "$PI_HOST" >/dev/null 2>&1 || true
      ssh-keygen -R "pi.local" >/dev/null 2>&1 || true
      echo ""
      clone_repo
      printf 'PI_USER=%s\nPI_HOST=%s\nPI_PASS=%s\n' "$PI_USER" "$PI_HOST" "$PI_PASS" > "$SCRIPT_DIR/.env"
    else
      prompt_pi_creds
      ssh-keygen -R "$PI_HOST" >/dev/null 2>&1 || true
    fi
    prompt_display_model
    prompt_rescue_wifi
    bash "$SCRIPT_DIR/pi-scripts/setup-remote.sh" "$@"
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
  fi
}

do_reset() {
  if ! in_repo; then
    echo "Error: run from repo root."
    exit 1
  fi
  ensure_sshpass
  prompt_pi_creds
  bash "$SCRIPT_DIR/pi-scripts/reset.sh" "$@"
}

do_push() {
  if ! in_repo; then
    echo "Error: run from repo root."
    exit 1
  fi
  ensure_sshpass
  prompt_pi_creds
  bash "$SCRIPT_DIR/push.sh" "$@"
}

# ── Entry point ──
print_header

# Piped via curl — skip menu, go straight to install
if [ ! -t 0 ]; then
  do_install "$@"
  exit 0
fi

# Interactive — show menu
printf "  ${BOLD}1.${NC} Install   — set up Plink on your frame\n"
if in_repo; then
  printf "  ${BOLD}2.${NC} Reset     — wipe frame back to clean state\n"
  printf "  ${BOLD}3.${NC} Push      — deploy latest code to frame\n"
fi
echo ""
tty_read "  Choice [1]: " CHOICE
CHOICE="${CHOICE:-1}"
echo ""

case "$CHOICE" in
  1|[iI]*)  do_install "$@" ;;
  2|[rR]*)  do_reset "$@" ;;
  3|[pP]*)  do_push "$@" ;;
  *)
    printf "${RED}Invalid choice.${NC}\n"
    exit 1
    ;;
esac
