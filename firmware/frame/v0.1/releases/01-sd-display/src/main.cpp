#include <Arduino.h>
#include <SPI.h>
#include <SD.h>
#include <FS.h>
#include <esp_heap_caps.h>

#include "Display_EPD_W21.h"
#include "Display_EPD_W21_spi.h"
#include "frame_config.h"

static const char *kImageName = "/image0.bmp";

SPIClass sdSpi(HSPI);

static uint8_t *gFrameBuffer = nullptr;

struct BmpHeader {
  uint32_t pixelOffset = 0;
  int32_t width = 0;
  int32_t height = 0;
  uint16_t bpp = 0;
  uint32_t compression = 0;
  bool topDown = false;
};

static uint32_t readU32LE(File &f) {
  uint8_t b[4];
  if (f.read(b, 4) != 4) return 0;
  return (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
}

static int32_t readS32LE(File &f) {
  return (int32_t)readU32LE(f);
}

static uint16_t readU16LE(File &f) {
  uint8_t b[2];
  if (f.read(b, 2) != 2) return 0;
  return (uint16_t)b[0] | ((uint16_t)b[1] << 8);
}

static bool parseBmpHeader(File &f, BmpHeader &hdr) {
  if (f.size() < 54) {
    Serial.println("BMP too small");
    return false;
  }
  uint8_t sig[2];
  if (f.read(sig, 2) != 2 || sig[0] != 'B' || sig[1] != 'M') {
    Serial.println("Not a BMP file");
    return false;
  }
  (void)readU32LE(f); // file size
  (void)readU16LE(f); // reserved1
  (void)readU16LE(f); // reserved2
  hdr.pixelOffset = readU32LE(f);
  uint32_t dibSize = readU32LE(f);
  if (dibSize < 40) {
    Serial.printf("Unsupported DIB header: %u\n", dibSize);
    return false;
  }
  hdr.width = readS32LE(f);
  hdr.height = readS32LE(f);
  hdr.topDown = hdr.height < 0;
  if (hdr.topDown) hdr.height = -hdr.height;
  uint16_t planes = readU16LE(f);
  hdr.bpp = readU16LE(f);
  hdr.compression = readU32LE(f);
  if (planes != 1) {
    Serial.printf("Unsupported planes: %u\n", planes);
    return false;
  }
  if (hdr.bpp != 24) {
    Serial.printf("Unsupported BMP bit depth: %u\n", hdr.bpp);
    return false;
  }
  if (hdr.compression != 0) {
    Serial.printf("Unsupported BMP compression: %u\n", hdr.compression);
    return false;
  }
  return true;
}

// Maps 24-bit RGB to GooDisplay raw framebuffer token (input to Color_get).
// Tokens: 0x00=black 0xff=white 0xfc=yellow 0xE0=red 0x03=blue 0x1c=green
static uint8_t nearestSpectra6Color(uint8_t r, uint8_t g, uint8_t b) {
  struct PaletteEntry { uint8_t r, g, b, token; };
  static const PaletteEntry palette[] = {
    {0,   0,   0,   0x00},  // Black
    {255, 255, 255, 0xff},  // White
    {255, 255, 0,   0xfc},  // Yellow
    {255, 0,   0,   0xE0},  // Red
    {0,   0,   255, 0x03},  // Blue
    {0,   128, 0,   0x1c},  // Green
  };
  uint32_t bestDist = UINT32_MAX;
  uint8_t bestToken = 0xff;
  for (const auto &e : palette) {
    int dr = (int)r - (int)e.r;
    int dg = (int)g - (int)e.g;
    int db = (int)b - (int)e.b;
    uint32_t dist = (uint32_t)(dr*dr + dg*dg + db*db);
    if (dist < bestDist) {
      bestDist = dist;
      bestToken = e.token;
    }
  }
  return bestToken;
}

static bool renderBmpFromSd(const char *path) {
  File f = SD.open(path, FILE_READ);
  if (!f) {
    Serial.printf("Failed to open: %s\n", path);
    return false;
  }

  BmpHeader hdr;
  if (!parseBmpHeader(f, hdr)) {
    f.close();
    return false;
  }
  Serial.printf("BMP: %ldx%ld, %ubpp\n", (long)hdr.width, (long)hdr.height, hdr.bpp);

  // Logical canvas: portrait (480×800) when kFrameRotation=1, landscape (800×480) otherwise.
  const int dw = (kFrameRotation != 0) ? EPD_HEIGHT : EPD_WIDTH;
  const int dh = (kFrameRotation != 0) ? EPD_WIDTH  : EPD_HEIGHT;
  const int xOff = (dw - hdr.width) / 2;
  const int yOff = (dh - hdr.height) / 2;
  const int rowSize = ((hdr.width * 3 + 3) / 4) * 4;

  // 1 byte/pixel GooDisplay token — always 800×480 = 384 KB regardless of rotation
  size_t fbBytes = (size_t)EPD_WIDTH * EPD_HEIGHT;
  uint8_t *fb = (uint8_t *)heap_caps_malloc(fbBytes, MALLOC_CAP_SPIRAM);
  if (!fb) {
    Serial.println("PSRAM alloc failed");
    f.close();
    return false;
  }
  memset(fb, 0xff, fbBytes);  // 0xff = white token

  uint8_t *row = (uint8_t *)heap_caps_malloc(rowSize, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
  if (!row) {
    Serial.println("Row buffer alloc failed");
    heap_caps_free(fb);
    f.close();
    return false;
  }

  for (int y = 0; y < hdr.height; ++y) {
    int srcRow = hdr.topDown ? y : (hdr.height - 1 - y);
    if (!f.seek(hdr.pixelOffset + (uint32_t)srcRow * rowSize)) {
      Serial.printf("Seek failed row %d\n", srcRow);
      heap_caps_free(row);
      heap_caps_free(fb);
      f.close();
      return false;
    }
    if (f.read(row, rowSize) != rowSize) {
      Serial.printf("Short read row %d\n", srcRow);
      heap_caps_free(row);
      heap_caps_free(fb);
      f.close();
      return false;
    }
    for (int x = 0; x < hdr.width; ++x) {
      int dx = x + xOff;
      int dy = y + yOff;
      if (dx >= 0 && dy >= 0 && dx < dw && dy < dh) {
        fb[dy * dw + dx] = nearestSpectra6Color(row[x*3+2], row[x*3+1], row[x*3+0]);
      }
    }
  }
  heap_caps_free(row);
  f.close();

  if (kFrameRotation != 0) {
    // Rotate 90° CW: logical portrait (EPD_HEIGHT × EPD_WIDTH) → physical landscape (EPD_WIDTH × EPD_HEIGHT)
    uint8_t *physFb = (uint8_t *)heap_caps_malloc(fbBytes, MALLOC_CAP_SPIRAM);
    if (!physFb) {
      Serial.println("Rotation buffer alloc failed");
      heap_caps_free(fb);
      return false;
    }
    for (int lx = 0; lx < EPD_WIDTH; lx++) {
      for (int ly = 0; ly < EPD_HEIGHT; ly++) {
        physFb[ly * EPD_WIDTH + lx] = fb[(EPD_WIDTH - 1 - lx) * EPD_HEIGHT + ly];
      }
    }
    heap_caps_free(fb);
    gFrameBuffer = physFb;
    Serial.println("BMP decoded + rotated 90°CW, sending to display...");
    PIC_display(gFrameBuffer);
    EPD_sleep();
  } else {
    gFrameBuffer = fb;
    Serial.println("BMP decoded, sending to display...");
    PIC_display(gFrameBuffer);
    EPD_sleep();
  }

  Serial.println("BMP render complete");
  return true;
}

static bool initSdCard() {
  sdSpi.begin(kSdSckPin, kSdMisoPin, kSdMosiPin, kSdCsPin);
  if (!SD.begin(kSdCsPin, sdSpi, 4000000)) {
    Serial.println("SD init failed");
    return false;
  }
  Serial.println("SD init OK");
  return true;
}

static void listRootFiles() {
  File root = SD.open("/");
  if (!root) {
    Serial.println("SD root open failed");
    return;
  }
  Serial.println("SD root:");
  while (true) {
    File entry = root.openNextFile();
    if (!entry) break;
    Serial.printf("  %s  %lu bytes\n", entry.name(), (unsigned long)entry.size());
    entry.close();
  }
  root.close();
}

static void epd_reinit() {
  delay(200);  // allow panel to settle after EPD_sleep POF
#if EPD_USE_FAST_INIT
  EPD_init_fast();
#else
  EPD_init();
#endif
}

static void initDisplay() {
  // Power control — P-FET SI2301: active LOW = ON
  pinMode(kEpdPowerCtrlPin, OUTPUT);
  digitalWrite(kEpdPowerCtrlPin, LOW);
  delay(100);
  Serial.printf("EPD power ON (GPIO %d)\n", kEpdPowerCtrlPin);

  // EPD control pins
  pinMode(kEpdBusyPin, INPUT);
  pinMode(kEpdResetPin, OUTPUT);
  pinMode(kEpdDcPin, OUTPUT);
  pinMode(kEpdCsPin, OUTPUT);

  // VSPI — SCK=IO12, MOSI=IO11, MISO=IO13 (default ESP32-S3, confirmed working)
  SPI.begin(12, 13, 11, -1);
  SPI.beginTransaction(SPISettings(10000000, MSBFIRST, SPI_MODE0));

#if EPD_USE_FAST_INIT
  Serial.println("EPD init: fast (~19s)");
#else
  Serial.println("EPD init: slow (~30s)");
#endif
  epd_reinit();
  Serial.printf("Display: %d x %d\n", EPD_WIDTH, EPD_HEIGHT);
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.println("Plink Frame v0.1");

  initDisplay();

  if (!initSdCard()) return;

  listRootFiles();

  if (SD.exists(kImageName)) {
    Serial.printf("Found: %s\n", kImageName);
    renderBmpFromSd(kImageName);
  } else {
    Serial.printf("Missing: %s\n", kImageName);
  }
}

void loop() {
  delay(1000);
}
