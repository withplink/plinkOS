#pragma once

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

// Display rotation. 0 = landscape native (800×480). 1 = portrait, 90° CW (480w × 800h logical).
// For 90° CCW swap the rotation formula sign in renderBmpFromSd if needed.
constexpr int kFrameRotation = 1;
