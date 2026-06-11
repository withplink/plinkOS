#pragma once

// Frame v0.1 prototype pin map.
//
// Keep the mapping in one file so the first hardware flash can be adjusted quickly if the board
// wants a different DC/BUSY/CS assignment.

// Spectra 6 / GDEP073E01 — confirmed from schematic net labels
// GDEP073E01 is 3-wire SPI — no DC pin. DC = -1 in constructor.
// POWER_CTRL routes through SI2301 P-FET (active LOW = ON)
constexpr int kEpdBusyPin      = 5;   // IO5  = HOST_HRDY
constexpr int kEpdResetPin     = 6;   // IO6  = RESET
constexpr int kEpdCsPin        = 7;   // IO7  = SPI2_CS
constexpr int kEpdSckPin       = 15;  // IO15 = SPI2_CLK
constexpr int kEpdMosiPin      = 16;  // IO16 = SPI2_SI
constexpr int kEpdMisoPin      = 17;  // IO17 = SPI2_SO
constexpr int kEpdPowerCtrlPin = 19;  // IO19 = SI2301 P-FET gate (active LOW = ON)

// SD card
constexpr int kSdCsPin = 48;
constexpr int kSdMosiPin = 47;
constexpr int kSdMisoPin = 13;
constexpr int kSdSckPin = 21;

// Canvas
constexpr int kFrameWidth = 800;
constexpr int kFrameHeight = 480;
