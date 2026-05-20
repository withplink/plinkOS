#!/bin/bash
# Plink one-line setup — curl -sL https://raw.githubusercontent.com/PixeledCode/pi-ink/main/pi-scripts/setup.sh | bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "  ___  _        _  _        "
echo " | _ \| |_  ___| || |  ___  "
echo " |  _/| ' \(_-< __ | / -_) "
echo " |_|  |_||_/__/_||_| \___| "
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
    echo -e "${RED}Cannot install sshpass automatically. Please install it manually.${NC}"
    exit 1
  fi
fi

# Prompt for Pi details
read -p "Pi hostname or IP [pi.local]: " PI_HOST
PI_HOST="${PI_HOST:-pi.local}"

read -p "Pi username [pi]: " PI_USER
PI_USER="${PI_USER:-pi}"

# Password input (hidden)
read -s -p "Pi password: " PI_PASS
echo ""

if [ -z "$PI_PASS" ]; then
  echo -e "${RED}Error: password is required. You must set a password during Raspberry Pi Imager setup.${NC}"
  exit 1
fi

# Test SSH connection
echo -e "${YELLOW}Testing SSH connection to $PI_USER@$PI_HOST...${NC}"

ATTEMPTS=0
MAX_ATTEMPTS=3
while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  if sshpass -p "$PI_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$PI_USER@$PI_HOST" "echo ok" 2>/dev/null; then
    echo -e "${GREEN}Connected!${NC}"
    break
  fi
  ATTEMPTS=$((ATTEMPTS + 1))
  if [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; then
    echo -e "${YELLOW}Connection failed. Retrying ($ATTEMPTS/$MAX_ATTEMPTS)...${NC}"
    sleep 3
  fi
done

if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
  echo ""
  echo -e "${RED}Could not connect to the Pi. Please check:${NC}"
  echo "  1. The Pi is powered on and connected to the same network"
  echo "  2. SSH was enabled during Raspberry Pi Imager setup"
  echo "  3. The password matches what you set during flashing"
  echo ""
  echo -e "${RED}Note: Raspberry Pi OS requires a password to be set during imaging.${NC}"
  echo -e "${RED}If you left it blank, reflash the SD card and set a password.${NC}"
  exit 1
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
cat > "$TMP_DIR/.env" << EOF
PI_USER=$PI_USER
PI_HOST=$PI_HOST
PI_PASS=$PI_PASS
EOF

# Run first-boot setup
echo -e "${YELLOW}Setting up your Pi...${NC}"
echo -e "${BLUE}This will take a few minutes. The Pi will reboot automatically.${NC}"
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
echo -e "  ${BLUE}http://pi.local${NC}"
echo -e "  ${BLUE}http://192.168.1.50${NC}"
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
