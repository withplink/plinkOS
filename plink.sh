#!/bin/bash
# Plink — e-ink frame manager
# curl -sL https://raw.githubusercontent.com/PixeledCode/pi-ink/main/plink.sh | bash

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
  git clone https://github.com/PixeledCode/pi-ink.git "$TMP_DIR" >/dev/null 2>&1 &
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

prompt_pi_creds() {
  load_env
  PI_USER="${PI_USER:-pi}"
  PI_HOST="${PI_HOST:-pi.local}"
  if [ -z "${PI_PASS:-}" ]; then
    echo "Where should Plink connect?"
    echo ""
    tty_read "  Hostname or IP [pi.local]: " PI_HOST
    PI_HOST="${PI_HOST:-pi.local}"
    tty_read "  Username [pi]: " PI_USER
    PI_USER="${PI_USER:-pi}"
    tty_read "  Password: " PI_PASS 1
    [ -z "$PI_PASS" ] && { echo "Error: password required."; exit 1; }
  else
    printf "  ${DIM}Connecting to %s@%s${NC}\n" "$PI_USER" "$PI_HOST"
  fi
  export PI_USER PI_HOST PI_PASS
}

prompt_tailscale() {
  echo ""
  echo "Optional: Tailscale VPN lets you reach your frame from anywhere."
  echo ""
  tty_read "  Set up Tailscale VPN? [y/N]: " SETUP_TAILSCALE
  SETUP_TAILSCALE="${SETUP_TAILSCALE:-n}"
  if [ "$SETUP_TAILSCALE" = "y" ] || [ "$SETUP_TAILSCALE" = "Y" ]; then
    echo ""
    echo "  Auth key lets setup complete without a browser — get one at:"
    echo "  https://login.tailscale.com/admin/settings/keys"
    echo ""
    tty_read "  Tailscale auth key [skip — use browser]: " TAILSCALE_AUTH_KEY 1
    export TAILSCALE_AUTH_KEY
  fi
  export SETUP_TAILSCALE
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
      prompt_tailscale
      ssh-keygen -R "$PI_HOST" >/dev/null 2>&1 || true
      ssh-keygen -R "pi.local" >/dev/null 2>&1 || true
      echo ""
      clone_repo
      printf 'PI_USER=%s\nPI_HOST=%s\nPI_PASS=%s\n' "$PI_USER" "$PI_HOST" "$PI_PASS" > "$SCRIPT_DIR/.env"
    else
      prompt_pi_creds
      prompt_tailscale
      ssh-keygen -R "$PI_HOST" >/dev/null 2>&1 || true
    fi
    bash "$SCRIPT_DIR/pi-scripts/setup-remote.sh" "$@"
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
  fi
}

do_reset() {
  if ! in_repo; then
    echo "Error: run from repo root."
    exit 1
  fi
  prompt_pi_creds
  bash "$SCRIPT_DIR/pi-scripts/reset.sh" "$@"
}

do_push() {
  if ! in_repo; then
    echo "Error: run from repo root."
    exit 1
  fi
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
