#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASES_DIR="$SCRIPT_DIR/releases"
CHIP="esp32s3"
BAUD=115200

# ── Port detection ────────────────────────────────────────────────────────────
ports=()
for p in /dev/cu.usbserial-*; do
  [[ -e "$p" ]] && ports+=("$p")
done

if [[ ${#ports[@]} -eq 0 ]]; then
  echo "No /dev/cu.usbserial-* found. Connect the UART port and retry."
  exit 1
elif [[ ${#ports[@]} -eq 1 ]]; then
  PORT="${ports[0]}"
else
  echo ""
  echo "Multiple serial ports found:"
  for i in "${!ports[@]}"; do
    echo "  $((i+1))) ${ports[$i]}"
  done
  read -rp "Select port [1-${#ports[@]}]: " pchoice
  if ! [[ "$pchoice" =~ ^[0-9]+$ ]] || (( pchoice < 1 || pchoice > ${#ports[@]} )); then
    echo "Invalid port selection."
    exit 1
  fi
  PORT="${ports[$((pchoice-1))]}"
fi

# ── Action menu ───────────────────────────────────────────────────────────────
echo ""
echo "Plink Frame v0.1  •  $PORT"
echo "────────────────────────────────"
echo "  1) Flash firmware"
echo "  2) Open serial monitor"
echo ""
read -rp "Select [1-2]: " action
echo ""

case "$action" in
  1)
    # ── Firmware selection ────────────────────────────────────────────────────
    releases=()
    for d in "$RELEASES_DIR"/*/; do
      [[ -d "$d" ]] && releases+=("${d%/}")
    done

    if [[ ${#releases[@]} -eq 0 ]]; then
      echo "No releases found in $RELEASES_DIR"
      exit 1
    fi

    echo "Select firmware:"
    for i in "${!releases[@]}"; do
      echo "  $((i+1))) $(basename "${releases[$i]}")"
    done
    echo ""
    read -rp "Select [1-${#releases[@]}]: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#releases[@]} )); then
      echo "Invalid selection."
      exit 1
    fi

    selected="${releases[$((choice-1))]}"
    bins_dir="$selected/bins"

    for f in bootloader.bin partitions.bin firmware.bin; do
      if [[ ! -f "$bins_dir/$f" ]]; then
        echo "Missing bin: $bins_dir/$f"
        exit 1
      fi
    done

    echo ""
    echo "  Firmware : $(basename "$selected")"
    echo "  Port     : $PORT"
    echo "  Baud     : $BAUD"
    echo ""
    read -rp "Open serial monitor after flash? [y/N]: " open_monitor
    echo ""
    echo "Enter download mode:"
    echo "  Hold SW2 throughout — keep it held until flashing starts."
    echo ""
    read -rp "Ready? Press Enter to flash: "
    echo ""

    python3 -m esptool \
      --chip "$CHIP" \
      --port "$PORT" \
      --baud "$BAUD" \
      write_flash \
      0x0     "$bins_dir/bootloader.bin" \
      0x8000  "$bins_dir/partitions.bin" \
      0x10000 "$bins_dir/firmware.bin"

    echo ""
    echo "Flash complete."
    echo ""

    if [[ "$open_monitor" == "y" || "$open_monitor" == "Y" ]]; then
      echo "Monitor on $PORT @ $BAUD — Ctrl-A Ctrl-\\ to quit."
      screen "$PORT" "$BAUD"
    fi
    ;;

  2)
    echo "Monitor on $PORT @ $BAUD — Ctrl-A Ctrl-\\ to quit."
    screen "$PORT" "$BAUD"
    ;;

  *)
    echo "Invalid selection."
    exit 1
    ;;
esac
