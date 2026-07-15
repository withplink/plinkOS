#pragma once
#include <stdint.h>

// Frame v0.1 prototype pin map.
//
// Keep the mapping in one file so the first hardware flash can be adjusted quickly if the board
// wants a different DC/BUSY/CS assignment.

// Spectra 6 / GDEP073E01 — pins confirmed from GxEPD2 library example (tested on actual hardware, Jan 2025)
// SPI uses default ESP32-S3 pins (SCK=12, MOSI=11, MISO=13) — do NOT override with SPI.begin().
// POWER_CTRL routes through SI2301 P-FET (active LOW = ON)
constexpr int kEpdBusyPin      = 5;   // IO5  = HOST_HRDY
constexpr int kEpdResetPin     = 4;   // IO4  = RESET
constexpr int kEpdCsPin        = 2;   // IO2  = SPI2_CS
constexpr int kEpdDcPin        = 3;   // IO3  = DC (Data/Command select)
constexpr int kEpdPowerCtrlPin = 19;  // IO19 = SI2301 P-FET gate (active LOW = ON, unconfirmed GPIO)

// SD card
constexpr int kSdCsPin = 48;
constexpr int kSdMosiPin = 47;
constexpr int kSdMisoPin = 13;
constexpr int kSdSckPin = 21;

// Canvas
constexpr int kFrameWidth = 800;
constexpr int kFrameHeight = 480;

// EPD init variant. 0 = EPD_init (PLL=0x08), 1 = EPD_init_fast (PLL=0x02).
// Despite the name, EPD_init produces faster waveform on this panel (~31s vs ~36s hot).
// "Fast" refers to power-on sequence, not waveform speed. Default 0.
#define EPD_USE_FAST_INIT 0

// Display rotation. SUPERSEDED (twice): rotation is now done entirely in the app, which
// always sends a panel-native 800×480 BMP already rotated for the mount. The firmware
// renders it directly — no rotation here, no orientation protocol. Constant kept for
// reference only; not used by renderBmpFromSd.
constexpr int kFrameRotation = 0;

// BLE GATT UUIDs
#define BLE_DEVICE_NAME       "Plink Frame"
#define BLE_SERVICE_UUID      "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define BLE_IMG_DATA_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define BLE_CONTROL_CHAR_UUID  "cba1d466-344c-4be3-ab3f-189f80dd7518"
#define BLE_STATUS_CHAR_UUID   "f4b8ef7d-1e3a-4b9c-8d2f-6a7c5e9f0b1d"
#define BLE_NAME_CHAR_UUID     "f4b8ef7d-1e3a-4b9c-8d2f-6a7c5e9f0c2e"  // READ+WRITE, frame name (NVS-backed)
#define BLE_QUEUE_CHAR_UUID    "f4b8ef7d-1e3a-4b9c-8d2f-6a7c5e9f0d3f"  // READ, frame-canonical queue.json
#define BLE_ASSET_OUT_CHAR_UUID "f4b8ef7d-1e3a-4b9c-8d2f-6a7c5e9f0e40" // READ, asset bytes streamed frame→app (long read)
#define BLE_BATTERY_CHAR_UUID  "f4b8ef7d-1e3a-4b9c-8d2f-6a7c5e9f0f51"  // READ+NOTIFY, {percent:1, flags:1} (flags bit0=charging)
#define BLE_INFO_CHAR_UUID     "f4b8ef7d-1e3a-4b9c-8d2f-6a7c5e9f0f52"  // READ+NOTIFY, [uptimeSec:4 LE][modelLen:1][model][featureFlags:1] (featureFlags added plinkOS#45 — bit0: accepts 4bpp indexed BMP)

// Static hardware identity string, reported over BLE_INFO_CHAR_UUID — mirrors the Pi's
// get_display_model() equivalent, since BLE frames have no HTTP status endpoint to report this.
constexpr const char *kFrameModel = "ESP32-S3 / GDEP073E01";

// ── Battery (resistor-divider ADC) — plinkOS#34 ──────────────────────────────
// IP5306 (eSOP8 package) has no I2C, no STAT/PG pin — confirmed via the Injoinic datasheet itself:
// the part is 8 pins total (VIN/LED1/LED2/LED3/KEY/BAT/SW/VOUT), physically incapable of I2C. Only
// larger sibling parts (IP5108/5109/5209/5219, different package) support I2C. So this reads the
// raw analog nodes directly instead of I2C.
//
// GoodDisplay (vendor) confirmed 2026-07-14: the ESP32E6-E01 board already has a battery-voltage
// divider built in, routed to IO1 — no soldering needed for battery %. Vendor gave the resistor
// values (47k battery-side, 10k GND-side) on a follow-up after our multimeter reading (~0.7V,
// flat regardless of battery state) initially looked like IO1 wasn't the sense line at all — turned
// out our first guessed ratio (10k/22k) was simply wrong, not the pin: 47k/10k against a ~4.1V
// resting LiPo predicts ~0.72V on IO1, matching the multimeter exactly. IO1 is confirmed correct.
// Charging/VBUS-present has NO onboard circuit — vendor confirmed "no USB inspection has been
// performed" on this board, so `kVbusAdcWired` stays false until our own divider is soldered onto VIN.
constexpr bool kBatteryAdcWired = true;   // IO1 confirmed board-routed by vendor — no soldering needed
constexpr bool kVbusAdcWired    = false;  // TODO(#34): flip true once our own VIN divider is soldered
constexpr int  kBatteryAdcPin = 1;   // BAT divider — vendor-confirmed, ADC1 (avoids ADC2/WiFi-BT contention)
constexpr int  kVbusAdcPin    = 8;   // VIN divider — our own, ADC1 channel
// Divider ratios (measured node / true node). R1 = node-side resistor, R2 = GND-side resistor.
// kBatteryDividerFactor is calibrated from a real measurement (2026-07-14), not the nominal 47k/10k
// resistor math (0.175) — actual resistors have tolerance. Data point: IO1 raw=821 (0.6616V) against
// a multimeter reading of 3.92V directly on the battery connector -> factor = 0.6616 / 3.92 = 0.1688.
// STALE as of 2026-07-15: main.cpp's readBatterySense() switched from raw analogRead()/4095*3.3
// math to analogReadMilliVolts() (eFuse-calibrated) after a multimeter cross-check at IO1 (0.74V)
// caught the raw math under-reading the pin by ~9.5% (0.6696V computed for the same instant). This
// factor was derived against the OLD raw math's pin-voltage output, not the new one — needs a fresh
// multimeter-at-battery reading + IO1 mv= log line to re-derive, same procedure as the original.
constexpr float kBatteryDividerFactor = 0.1688f;  // calibrated against pre-2026-07-15 raw ADC math — needs redo
constexpr float kVbusDividerFactor    = 12.0f / (10.0f + 12.0f);  // R1=10k, R2=12k → 5.5V→~3.0V (guess)
constexpr float kVbusPresentThresholdV = 1.5f;  // divided VIN reads ~0V unplugged, ~2.7V on USB
// Prints raw ADC counts + computed voltage to Serial on every battery poll (~30s) — turn on while
// calibrating kBatteryDividerFactor against a multimeter reading of the real battery voltage, off
// once the factor is confirmed (this is chatty).
constexpr bool kBatteryDebugLog = true;

// ── BLE control opcodes ──────────────────────────────────────────────────────
// The control characteristic (WRITE w/ response) carries a 1-byte opcode + payload.
// Stream framing:
constexpr uint8_t kBleAbort       = 0x00;  // discard the in-flight stream buffer
constexpr uint8_t kBleCommit      = 0x01;  // finalize the streamed asset → SD (routed by kind)
constexpr uint8_t kBleBeginAsset  = 0x10;  // [kind:1][id:4 LE] — start a tagged asset stream
// Queue ops (port the Pi /api/queue/* set; frame owns queue.json):
constexpr uint8_t kBleAdd         = 0x20;  // [show_now:1][id:4 LE][labelLen:1][label][assetId]
constexpr uint8_t kBleRemove      = 0x21;  // [idx:1]
constexpr uint8_t kBleReorder     = 0x22;  // [n:1][order bytes…]
constexpr uint8_t kBleShow        = 0x23;  // [idx:1]
constexpr uint8_t kBleNext        = 0x24;  // (no payload)
constexpr uint8_t kBleInterval    = 0x25;  // [seconds:4 LE]  (0 = auto-rotate off)
constexpr uint8_t kBleRename      = 0x26;  // [idx:1][label…]
constexpr uint8_t kBleList        = 0x27;  // refresh queue char + dirty-notify
constexpr uint8_t kBleGetAsset    = 0x28;  // [kind:1][id:4 LE] → asset-out char = 4-byte LE length
constexpr uint8_t kBleGetChunk    = 0x29;  // [offset:4 LE][len:2 LE] → asset-out char = that slice
constexpr uint8_t kBleClear       = 0x2A;  // wipe the whole queue + all assets on SD
constexpr uint8_t kBleGetQueue    = 0x2B;  // (no payload) → asset-out char = 4-byte LE length, then
                                           //   GetChunk-served queue JSON. Bypasses the queue char's
                                           //   ~600 B GATT value cap so the gallery scales past ~6 items.
constexpr uint8_t kBleClearGhost  = 0x2C;  // (no payload) run the ghosting-clear cycle, then restore
constexpr uint8_t kBleReboot      = 0x2D;  // (no payload) esp_restart() (no OS shutdown on ESP32)

// Asset kinds (kBleBeginAsset / kBleGetAsset payload)
constexpr uint8_t kAssetBmp   = 0x00;  // 800×480 panel-native display BMP → /img/<id>.bmp
constexpr uint8_t kAssetJpeg  = 0x01;  // ~1600×960 recrop master JPEG    → /orig/<id>.jpg
constexpr uint8_t kAssetThumb = 0x02;  // ~200px list thumbnail JPEG       → /thumb/<id>.jpg
constexpr uint8_t kAssetCrop  = 0x03;  // crop transformation JSON → stored in queue.json item["crop"]
                                       //   (not an SD file; persisted opaque so recrop can re-seed Mantis)

// BLE status values (sent via NOTIFY)
constexpr uint8_t kBleStatusReady        = 0x00;
constexpr uint8_t kBleStatusReceiving    = 0x01;
constexpr uint8_t kBleStatusRendering    = 0x02;
constexpr uint8_t kBleStatusQueueDirty   = 0x10;  // queue.json changed → app re-reads queue char
constexpr uint8_t kBleStatusAssetReady   = 0x11;  // requested asset loaded → app reads asset-out char
constexpr uint8_t kBleStatusAssetMissing = 0x12;  // requested asset not on SD
constexpr uint8_t kBleStatusError        = 0xFF;

// Queue limits (v0.1)
constexpr int kMaxQueueItems = 64;  // reorder order[] cap; realistic v0.1 gallery is far smaller
