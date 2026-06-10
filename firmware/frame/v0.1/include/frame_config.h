#pragma once

// Frame v0.1 prototype pin map.
//
// Keep the mapping in one file so the first hardware flash can be adjusted quickly if the board
// wants a different DC/BUSY/CS assignment.

// Spectra 6 / GDEP073E01
constexpr int kEpdBusyPin = 4;
constexpr int kEpdDcPin = 5;
constexpr int kEpdResetPin = 6;
constexpr int kEpdCsPin = 7;
constexpr int kEpdPowerCtrlPin = 18;
constexpr int kEpdSckPin = 15;
constexpr int kEpdMosiPin = 16;
constexpr int kEpdMisoPin = 17;

// SD card
constexpr int kSdCsPin = 48;
constexpr int kSdMosiPin = 47;
constexpr int kSdMisoPin = 13;
constexpr int kSdSckPin = 21;

// Canvas
constexpr int kFrameWidth = 800;
constexpr int kFrameHeight = 480;
