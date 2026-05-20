#!/bin/bash
# Plink one-line setup
# Recommended: download first, then run
#   curl -sL https://raw.githubusercontent.com/PixeledCode/pi-ink/main/pi-scripts/setup.sh -o setup.sh
#   bash setup.sh

set -e

# Colors
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
WHITE='\033[1;37m'
DIM_WHITE='\033[2;37m'
NC='\033[0m'

# Read from terminal
tty_read() {
  local prompt="$1"
  local varname="$2"
  local hidden="$3"
  local val=""
  if [ "$hidden" = "1" ]; then
    read -s -p "$prompt" val
  else
    read -p "$prompt" val
  fi
  echo ""
  eval "$varname='$val'"
}

# Header — stylized e-ink display frame
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

print_header

# Check sshpass
if ! command -v sshpass &> /dev/null; then
  echo "Installing sshpass..."
  if command -v brew &> /dev/null; then
    brew install sshpass
  elif command -v apt-get &> /dev/null; then
    sudo apt-get install -y sshpass
  else
    echo "Cannot install sshpass automatically. Install it: brew install sshpass"
    exit 1
  fi
fi

# Prompt for Pi details
echo "Where should Plink connect?"
echo ""
tty_read "  Hostname or IP [pi.local]: " PI_HOST
PI_HOST="${PI_HOST:-pi.local}"

tty_read "  Username [pi]: " PI_USER
PI_USER="${PI_USER:-pi}"

tty_read "  Password: " PI_PASS 1

if [ -z "$PI_PASS" ]; then
  echo "Error: password is required. You must set a password during Raspberry Pi Imager setup."
  exit 1
fi

echo ""

# Clear stale SSH host keys (common after reflashing)
ssh-keygen -R "$PI_HOST" >/dev/null 2>&1 || true
ssh-keygen -R "pi.local" >/dev/null 2>&1 || true

# Test SSH connection
try_connect() {
  local host="$1"
  sshpass -p "$PI_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$PI_USER@$host" "echo ok" >/dev/null 2>&1
}

if ! try_connect "$PI_HOST"; then
  echo "Could not reach $PI_HOST. Scanning local network..."
  
  # Get local subnet
  LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
  if [ -z "$LOCAL_IP" ]; then
    echo "Could not determine local network."
    tty_read "  Enter Pi IP address: " PI_HOST
  else
    SUBNET=$(echo "$LOCAL_IP" | cut -d. -f1-3)
    echo "Scanning $SUBNET.0/24..."
    
    # Quick ARP scan
    for i in $(seq 1 254); do
      ping -c 1 -t 1 "$SUBNET.$i" >/dev/null 2>&1 &
    done
    wait
    
    # Find Raspberry Pi MACs
    FOUND_PIS=()
    while IFS= read -r line; do
      IP=$(echo "$line" | awk '{print $1}')
      MAC=$(echo "$line" | awk '{print $4}')
      if echo "$MAC" | grep -qi "^88:a2:9e"; then
        FOUND_PIS+=("$IP")
      fi
    done < <(arp -a | grep -i "88:a2:9e")
    
    if [ ${#FOUND_PIS[@]} -eq 1 ]; then
      PI_HOST="${FOUND_PIS[0]}"
    elif [ ${#FOUND_PIS[@]} -gt 1 ]; then
      echo "Found multiple Raspberry Pi devices:"
      for i in "${!FOUND_PIS[@]}"; do
        echo "  $((i+1)). ${FOUND_PIS[$i]}"
      done
      tty_read "  Select Pi number [1]: " SELECT
      SELECT="${SELECT:-1}"
      PI_HOST="${FOUND_PIS[$((SELECT-1))]}"
    else
      echo "No Raspberry Pi found."
      echo "Check your router's DHCP client list for connected devices."
      tty_read "  Enter Pi IP address: " PI_HOST
    fi
  fi
  
  # Retry connection
  if [ -n "$PI_HOST" ]; then
    ssh-keygen -R "$PI_HOST" >/dev/null 2>&1 || true
    if ! try_connect "$PI_HOST"; then
      echo ""
      echo "Still cannot connect. Please verify:"
      echo "  1. The Pi is powered on and on the same network"
      echo "  2. SSH was enabled during Raspberry Pi Imager setup"
      echo "  3. The password matches what you set during flashing"
      echo ""
      echo "Note: Raspberry Pi OS requires a password to be set during imaging."
      echo "If you left it blank, reflash the SD card and set a password."
      exit 1
    fi
  fi
fi

# Clone repo
echo ""
echo "Cloning Plink repo..."
TMP_DIR=$(mktemp -d)
git clone https://github.com/PixeledCode/pi-ink.git "$TMP_DIR" >/dev/null 2>&1 || {
  echo "Failed to clone repo. Check your internet connection."
  exit 1
}

# Create .env
printf 'PI_USER=%s\nPI_HOST=%s\nPI_PASS=%s\n' "$PI_USER" "$PI_HOST" "$PI_PASS" > "$TMP_DIR/.env"

# Run first-boot setup
echo ""
echo "Setting up your Pi..."
echo ""

cd "$TMP_DIR"
export PI_HOST
bash pi-scripts/first-boot-setup.sh "$@"

# Cleanup
rm -rf "$TMP_DIR"
