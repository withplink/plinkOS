#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASES_DIR="$SCRIPT_DIR/releases"
STAGING_DIR="$SCRIPT_DIR/staging"   # unvalidated builds; promote to releases/ once confirmed
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
echo "  3) Clear ghosting (panel refresh cycle)"
echo "  4) Factory reset (delete ALL photos, thumbnails, queue)"
echo ""
read -rp "Select [1-4]: " action
echo ""

case "$action" in
  1)
    # ── Firmware selection ────────────────────────────────────────────────────
    releases=()
    for d in "$RELEASES_DIR"/*/; do
      [[ -d "$d" ]] && releases+=("${d%/}")
    done
    # Staging builds: flashable but unvalidated. Tagged [TEMP]; promote to releases/ once confirmed.
    if [[ -d "$STAGING_DIR" ]]; then
      for d in "$STAGING_DIR"/*/; do
        [[ -d "$d" ]] && releases+=("${d%/}")
      done
    fi

    if [[ ${#releases[@]} -eq 0 ]]; then
      echo "No firmware found in $RELEASES_DIR or $STAGING_DIR"
      exit 1
    fi

    echo "Select firmware:"
    for i in "${!releases[@]}"; do
      name="$(basename "${releases[$i]}")"
      if [[ "${releases[$i]}" == "$STAGING_DIR"/* ]]; then
        echo "  $((i+1))) $name  [TEMP — unvalidated]"
      else
        echo "  $((i+1))) $name"
      fi
    done
    echo ""
    # Staging (dev) is always appended last when present, so the last entry is always the
    # newest build available (dev if it exists, else the highest-numbered release) — default
    # to it on a bare Enter.
    read -rp "Select [1-${#releases[@]}] (Enter = latest): " choice

    if [[ -z "$choice" ]]; then
      choice="${#releases[@]}"
    elif ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#releases[@]} )); then
      echo "Invalid selection."
      exit 1
    fi

    selected="${releases[$((choice-1))]}"
    bins_dir="$selected/bins"

    # Staging (dev) is built from the live src/ — always rebuild before flashing so we never
    # flash stale bins (the .pio/build → staging/bins sync gap). Releases are frozen; skip.
    if [[ "$selected" == "$STAGING_DIR"/* ]]; then
      echo "Rebuilding dev firmware from src/ before flash…"
      if ! "$SCRIPT_DIR/build-dev.sh"; then
        echo "Build failed — aborting flash."
        exit 1
      fi
      echo ""
    fi

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
      echo "Opening monitor on $PORT @ $BAUD (also logging to platformio-device-monitor-*.log)"
      echo "Quit: Ctrl-C"
      read -rp "Press Enter to open: "
      pio device monitor -p "$PORT" -b "$BAUD" --filter log2file --filter time
    fi
    ;;

  2)
    echo "Opening monitor on $PORT @ $BAUD (also logging to platformio-device-monitor-*.log)"
    echo "Quit: Ctrl-C"
    read -rp "Press Enter to open: "
    pio device monitor -p "$PORT" -b "$BAUD" --filter log2file --filter time
    ;;

  3)
    # Send the "clear" serial command to the running firmware and stream its progress. Opens the
    # port with DTR/RTS deasserted so the ESP is NOT reset on open — the live firmware receives the
    # command. Runs ~4 full panel refreshes (~2 min), then re-renders the current image.
    echo "Clearing ghosting on $PORT — ~2 min (4 panel passes). Frame must be powered + idle."
    read -rp "Press Enter to start: "
    # Prefer PlatformIO's bundled python (pyserial guaranteed); fall back to system python3.
    PYBIN="$(command -v python3 || true)"
    [[ -x "$HOME/.platformio/penv/bin/python" ]] && PYBIN="$HOME/.platformio/penv/bin/python"
    if [[ -z "$PYBIN" ]]; then echo "python3 not found."; exit 1; fi
    "$PYBIN" - "$PORT" "$BAUD" <<'PYEOF'
import sys, time, serial
port, baud = sys.argv[1], int(sys.argv[2])
s = serial.Serial()
s.port = port; s.baudrate = baud
s.dtr = False; s.rts = False          # try to avoid an auto-reset on open
s.timeout = 1
s.open()
# Most USB-serial adapters reset the ESP when the port opens, so a command sent immediately is
# lost during boot. Wait until the firmware finishes setup (it prints "BLE advertising as ...")
# before sending. If no banner appears within the window (board didn't reset), send anyway.
print("Waiting for frame to be ready (boots in ~45s if it reset on connect)...")
boot_deadline = time.time() + 60
while time.time() < boot_deadline:
    line = s.readline()
    if line:
        sys.stdout.write(line.decode(errors="replace")); sys.stdout.flush()
        if b"BLE advertising as" in line:
            break
time.sleep(0.5); s.reset_input_buffer()
s.write(b"clear\n")
print("\nSent 'clear'. Streaming firmware output (Ctrl-C to stop)...\n")
deadline = time.time() + 220
seen = False
try:
    while time.time() < deadline:
        line = s.readline()
        if line:
            sys.stdout.write(line.decode(errors="replace")); sys.stdout.flush()
            if b"Clearing ghosting" in line:
                seen = True
            if b"Ghost clear complete" in line:
                deadline = min(deadline, time.time() + 50)   # let the restore-render finish
    if not seen:
        print("\n(!) Never saw 'Clearing ghosting' — firmware may not have the clear handler. "
              "Reflash dev (option 1), then retry.")
except KeyboardInterrupt:
    pass
finally:
    s.close()
PYEOF
    echo ""
    echo "Done."
    ;;

  4)
    # Sends "wipe" over serial — same handleClear() the BLE kBleClear op (0x2A) runs: empties
    # queue.json, resets current/interval, and deletes every file under /img, /orig, /thumb.
    # Irreversible — no undo, and the frame will show nothing until a new photo is sent.
    echo "!! This deletes ALL photos, thumbnails, and the queue from $PORT's SD card, and forgets"
    echo "!! every paired phone (re-pairing needs the pairing window). No undo."
    read -rp "Type 'wipe' to confirm: " confirm
    if [[ "$confirm" != "wipe" ]]; then
      echo "Cancelled."
      exit 0
    fi
    PYBIN="$(command -v python3 || true)"
    [[ -x "$HOME/.platformio/penv/bin/python" ]] && PYBIN="$HOME/.platformio/penv/bin/python"
    if [[ -z "$PYBIN" ]]; then echo "python3 not found."; exit 1; fi
    "$PYBIN" - "$PORT" "$BAUD" <<'PYEOF'
import sys, time, serial
port, baud = sys.argv[1], int(sys.argv[2])
s = serial.Serial()
s.port = port; s.baudrate = baud
s.dtr = False; s.rts = False          # try to avoid an auto-reset on open
s.timeout = 1
s.open()
print("Waiting for frame to be ready (boots in ~45s if it reset on connect)...")
boot_deadline = time.time() + 60
while time.time() < boot_deadline:
    line = s.readline()
    if line:
        sys.stdout.write(line.decode(errors="replace")); sys.stdout.flush()
        if b"BLE advertising as" in line:
            break
time.sleep(0.5); s.reset_input_buffer()
s.write(b"wipe\n")
print("\nSent 'wipe'. Streaming firmware output (Ctrl-C to stop)...\n")
deadline = time.time() + 15
seen = False
try:
    while time.time() < deadline:
        line = s.readline()
        if line:
            sys.stdout.write(line.decode(errors="replace")); sys.stdout.flush()
            if b"Queue cleared" in line:
                seen = True
                # plinkOS#48: bond/paired-device clearing prints a couple more lines right after
                # this — give them a moment to arrive instead of closing the port immediately.
                deadline = min(deadline, time.time() + 1.0)
    if not seen:
        print("\n(!) Never saw 'Queue cleared' — firmware may not have the wipe handler. "
              "Reflash dev (option 1), then retry.")
except KeyboardInterrupt:
    pass
finally:
    s.close()
PYEOF
    echo ""
    echo "Done."
    ;;

  *)
    echo "Invalid selection."
    exit 1
    ;;
esac
