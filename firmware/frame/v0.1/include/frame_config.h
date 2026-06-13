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

// Display rotation. SUPERSEDED: renderBmpFromSd now infers rotation from the BMP
// dimensions the app sends (portrait height>width → rotate 90°CW; landscape → native),
// so orientation is controlled per-image by the app with no extra protocol. Kept for
// reference / 90° CCW formula tweaks. 0 = landscape native, 1 = portrait 90°CW.
constexpr int kFrameRotation = 1;

// BLE GATT UUIDs
#define BLE_DEVICE_NAME       "Plink Frame"
#define BLE_SERVICE_UUID      "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define BLE_IMG_DATA_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define BLE_CONTROL_CHAR_UUID  "cba1d466-344c-4be3-ab3f-189f80dd7518"
#define BLE_STATUS_CHAR_UUID   "f4b8ef7d-1e3a-4b9c-8d2f-6a7c5e9f0b1d"
#define BLE_NAME_CHAR_UUID     "f4b8ef7d-1e3a-4b9c-8d2f-6a7c5e9f0c2e"  // READ+WRITE, frame name (NVS-backed)

// BLE control opcodes
constexpr uint8_t kBleCommit = 0x01;
constexpr uint8_t kBleAbort  = 0x00;

// BLE status values (sent via NOTIFY)
constexpr uint8_t kBleStatusReady     = 0x00;
constexpr uint8_t kBleStatusReceiving = 0x01;
constexpr uint8_t kBleStatusRendering = 0x02;
constexpr uint8_t kBleStatusError     = 0xFF;
