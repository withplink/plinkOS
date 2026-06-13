#!/usr/bin/env bash
# Build the working firmware (top-level src/) and sync the fresh artifacts + source
# snapshot into staging/dev/ so `frame.sh` flashes what you just edited.
#
# WHY THIS EXISTS: `pio run` writes .pio/build/, but frame.sh flashes staging/dev/bins/.
# Editing src/ and flashing without this step silently flashes STALE bins. Always run
# `./build-dev.sh` before flashing staging/dev with frame.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIO="${PIO:-$HOME/.local/bin/pio}"
BUILD_DIR="$SCRIPT_DIR/.pio/build/esp32-s3-devkitc-1"
STAGING="$SCRIPT_DIR/staging/dev"

echo "▸ Building firmware (top-level src/)…"
"$PIO" run -d "$SCRIPT_DIR"

echo "▸ Syncing artifacts → staging/dev/bins"
mkdir -p "$STAGING/bins"
for f in firmware.bin bootloader.bin partitions.bin; do
  cp "$BUILD_DIR/$f" "$STAGING/bins/$f"
done

echo "▸ Syncing source snapshot → staging/dev (for a clean promote to releases/)"
rsync -a --delete "$SCRIPT_DIR/src/"     "$STAGING/src/"
rsync -a --delete "$SCRIPT_DIR/include/" "$STAGING/include/"
cp "$SCRIPT_DIR/platformio.ini" "$STAGING/platformio.ini"

echo "✓ staging/dev is fresh. Now run ./frame.sh → Flash → dev"
