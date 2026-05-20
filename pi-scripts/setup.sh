#!/bin/bash
# Plink one-line setup
# Recommended: download first, then run
#   curl -sL https://raw.githubusercontent.com/PixeledCode/pi-ink/main/pi-scripts/setup.sh -o setup.sh
#   bash setup.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CORAL='\033[38;2;255;127;80m'
NC='\033[0m'

echo -e "${CORAL}"
echo "▗▄▄▖ ▗▄▖    █       ▗▖   "
echo "▐▛▀▜▖▝▜▌    ▀       ▐▌   "
echo "▐▌ ▐▌ ▐▌   ██  ▐▙██▖▐▌▟▛ "
echo "▐██▛  ▐▌    █  ▐▛ ▐▌▐▙█  "
echo "▐▌    ▐▌    █  ▐▌ ▐▌▐▛█▖ "
echo "▐▌    ▐▙▄ ▗▄█▄▖▐▌ ▐▌▐▌▝▙ "
echo "▝▘     ▀▀ ▝▀▀▀▘▝▘ ▝▘▝▘ ▀▘"
echo -e "${NC}"
echo "e-ink photo frame setup"
echo ""

# Check sshpass
if ! command -v sshpass &> /dev/null; then
  echo -e "${YELLOW}sshpass not found. Installing...${NC}"
  if command -v brew &> /dev/null; then
    brew install sshpass
  elif command -v apt-get &> /dev/null; then
    sudo apt-get install -y sshpass
  else
    echo -e "${RED}Cannot install sshpass automatically. Install it: brew install sshpass${NC}"
    exit 1
  fi
fi

# Prompt for Pi details (from /dev/tty so it works with curl | bash)
tty_read "Pi hostname or IP [pi.local]: " PI_HOST
PI_HOST="${PI_HOST:-pi.local}"

tty_read "Pi username [pi]: " PI_USER
PI_USER="${PI_USER:-pi}"

tty_read "Pi password: " PI_PASS 1

if [ -z "$PI_PASS" ]; then
  echo -e "${RED}Error: password is required. You must set a password during Raspberry Pi Imager setup.${NC}"
  exit 1
fi

# Clear stale SSH host keys (common after reflashing)
ssh-keygen -R "$PI_HOST" 2>/dev/null || true
ssh-keygen -R "pi.local" 2>/dev/null || true

# Test SSH connection
try_connect() {
  local host="$1"
  sshpass -p "$PI_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$PI_USER@$host" "echo ok" 2>/dev/null
}

echo -e "${YELLOW}Testing SSH connection to $PI_USER@$PI_HOST...${NC}"

if try_connect "$PI_HOST"; then
  echo -e "${GREEN}Connected via $PI_HOST!${NC}"
else
  echo -e "${YELLOW}Could not reach $PI_HOST. Scanning local network for Raspberry Pi...${NC}"
  
  # Get local subnet
  LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
  if [ -z "$LOCAL_IP" ]; then
    echo -e "${RED}Could not determine local network. Please enter Pi IP manually:${NC}"
    tty_read "Pi IP address: " PI_HOST
  else
    SUBNET=$(echo "$LOCAL_IP" | cut -d. -f1-3)
    echo -e "${YELLOW}Scanning $SUBNET.0/24...${NC}"
    
    # Quick ARP scan - ping all hosts then check arp table
    for i in $(seq 1 254); do
      ping -c 1 -t 1 "$SUBNET.$i" >/dev/null 2>&1 &
    done
    wait
    
    # Find Raspberry Pi MACs in arp table
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
      echo -e "${GREEN}Found Raspberry Pi at $PI_HOST${NC}"
    elif [ ${#FOUND_PIS[@]} -gt 1 ]; then
      echo -e "${YELLOW}Found multiple Raspberry Pi devices:${NC}"
      for i in "${!FOUND_PIS[@]}"; do
        echo "  $((i+1)). ${FOUND_PIS[$i]}"
      done
      tty_read "Select Pi number [1]: " SELECT
      SELECT="${SELECT:-1}"
      PI_HOST="${FOUND_PIS[$((SELECT-1))]}"
    else
      echo -e "${YELLOW}No Raspberry Pi found via MAC scan.${NC}"
      echo "Look for a device in your router's DHCP client list, or try:"
      echo "  - pinging $SUBNET.1 through $SUBNET.254"
      echo "  - checking your router admin page for connected devices"
      tty_read "Enter Pi IP address: " PI_HOST
    fi
  fi
  
  # Retry connection with discovered IP
  if [ -n "$PI_HOST" ]; then
    ssh-keygen -R "$PI_HOST" 2>/dev/null || true
    echo -e "${YELLOW}Trying $PI_USER@$PI_HOST...${NC}"
    if ! try_connect "$PI_HOST"; then
      echo -e "${RED}Still cannot connect. Please verify:${NC}"
      echo "  1. The Pi is powered on and on the same network"
      echo "  2. SSH was enabled during Raspberry Pi Imager setup"
      echo "  3. The password matches what you set during flashing"
      echo ""
      echo -e "${RED}Note: Raspberry Pi OS requires a password to be set during imaging.${NC}"
      echo -e "${RED}If you left it blank, reflash the SD card and set a password.${NC}"
      exit 1
    fi
    echo -e "${GREEN}Connected!${NC}"
  fi
fi

# Clone repo
echo -e "${YELLOW}Cloning Plink repo...${NC}"
TMP_DIR=$(mktemp -d)
git clone https://github.com/PixeledCode/pi-ink.git "$TMP_DIR" 2>/dev/null || {
  echo -e "${RED}Failed to clone repo. Check your internet connection.${NC}"
  exit 1
}

# Create .env
echo -e "${YELLOW}Configuring credentials...${NC}"
printf 'PI_USER=%s\nPI_HOST=%s\nPI_PASS=%s\n' "$PI_USER" "$PI_HOST" "$PI_PASS" > "$TMP_DIR/.env"

# Run first-boot setup
echo -e "${YELLOW}Setting up your Pi...${NC}"
echo -e "${CORAL}This will take a few minutes. The Pi will reboot automatically.${NC}"
echo ""

cd "$TMP_DIR"
export PI_HOST
bash pi-scripts/first-boot-setup.sh

# Cleanup
rm -rf "$TMP_DIR"

# Success message
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Your Plink frame is ready!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Open one of these URLs on your phone:"
echo -e "  ${CORAL}http://pi.local${NC}"
echo -e "  ${CORAL}http://192.168.1.50${NC}"
echo ""
echo "Upload a photo and watch it appear on the e-ink display!"
echo ""
echo -e "${YELLOW}Optional: Plink iOS App${NC}"
echo "For a native experience with more features, download the Plink app:"
echo "  https://apps.apple.com/app/plink"
echo ""
echo -e "${YELLOW}Frame Buttons${NC}"
echo "  Button A (hold 1.5s): Toggle hotspot mode — shows QR code for phone setup"
echo "  Button B: Rotate image clockwise"
echo "  Button C: Rotate image counter-clockwise"
echo "  Button D: Reboot the Pi"
