#include <Arduino.h>
#include <SPI.h>
#include <SD.h>
#include <FS.h>
#include <esp_heap_caps.h>

#include <GxEPD2_7C.h>
#include <Adafruit_GFX.h>

#include "frame_config.h"

using DisplayType = GxEPD2_7C<GxEPD2_730c_GDEP073E01, GxEPD2_730c_GDEP073E01::HEIGHT / 4>;

static const char *kImageName = "/image0.bmp";

SPIClass sdSpi(HSPI);
DisplayType display(GxEPD2_730c_GDEP073E01(kEpdCsPin, kEpdDcPin, kEpdResetPin, kEpdBusyPin));

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

static uint16_t nearestSpectra6Color(uint8_t r, uint8_t g, uint8_t b) {
  struct PaletteColor {
    uint8_t r, g, b;
    uint16_t color;
  };

  static const PaletteColor palette[] = {
      {0, 0, 0, GxEPD_BLACK},
      {255, 255, 255, GxEPD_WHITE},
      {255, 0, 0, GxEPD_RED},
      {255, 255, 0, GxEPD_YELLOW},
      {0, 255, 0, GxEPD_GREEN},
      {0, 0, 255, GxEPD_BLUE},
  };

  uint32_t bestDistance = UINT32_MAX;
  uint16_t bestColor = GxEPD_WHITE;
  for (const auto &entry : palette) {
    int dr = (int)r - (int)entry.r;
    int dg = (int)g - (int)entry.g;
    int db = (int)b - (int)entry.b;
    uint32_t distance = (uint32_t)(dr * dr + dg * dg + db * db);
    if (distance < bestDistance) {
      bestDistance = distance;
      bestColor = entry.color;
    }
  }
  return bestColor;
}

static bool renderBmpFromSd(const char *path) {
  File f = SD.open(path, FILE_READ);
  if (!f) {
    Serial.printf("Failed to open file: %s\n", path);
    return false;
  }

  BmpHeader hdr;
  if (!parseBmpHeader(f, hdr)) {
    f.close();
    return false;
  }

  Serial.printf("BMP Width: %ld, Height: %ld, Bits per Pixel: %u\n",
                (long)hdr.width, (long)hdr.height, hdr.bpp);
  Serial.printf("BMP Offset: %lu, Top-down: %s\n",
                (unsigned long)hdr.pixelOffset, hdr.topDown ? "yes" : "no");

  const int displayWidth = display.width();
  const int displayHeight = display.height();
  const int xOffset = (displayWidth - hdr.width) / 2;
  const int yOffset = (displayHeight - hdr.height) / 2;
  const int rowSize = ((hdr.width * 3 + 3) / 4) * 4;

  uint8_t *row = (uint8_t *)heap_caps_malloc(rowSize, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
  if (!row) {
    Serial.println("Failed to allocate BMP row buffer");
    f.close();
    return false;
  }

  display.setFullWindow();
  display.firstPage();
  do {
    display.fillScreen(GxEPD_WHITE);

    for (int y = 0; y < hdr.height; ++y) {
      int sourceRow = hdr.topDown ? y : (hdr.height - 1 - y);
      uint32_t rowStart = hdr.pixelOffset + (uint32_t)sourceRow * (uint32_t)rowSize;
      if (!f.seek(rowStart)) {
        Serial.printf("Failed to seek row %d\n", sourceRow);
        heap_caps_free(row);
        f.close();
        return false;
      }

      if (f.read(row, rowSize) != rowSize) {
        Serial.printf("Short read on row %d\n", sourceRow);
        heap_caps_free(row);
        f.close();
        return false;
      }

      for (int x = 0; x < hdr.width; ++x) {
        const int src = x * 3;
        uint8_t b = row[src + 0];
        uint8_t g = row[src + 1];
        uint8_t r = row[src + 2];
        int dx = x + xOffset;
        int dy = y + yOffset;
        if (dx < 0 || dy < 0 || dx >= displayWidth || dy >= displayHeight) {
          continue;
        }
        display.drawPixel(dx, dy, nearestSpectra6Color(r, g, b));
      }
    }
  } while (display.nextPage());

  heap_caps_free(row);
  f.close();
  Serial.println("BMP render complete");
  return true;
}

static bool initSdCard() {
  sdSpi.begin(kSdSckPin, kSdMisoPin, kSdMosiPin, kSdCsPin);
  if (!SD.begin(kSdCsPin, sdSpi, 4000000)) {
    Serial.println("SD card initialization failed!");
    return false;
  }
  Serial.println("SD card initialization successful");
  return true;
}

static void listRootFiles() {
  File root = SD.open("/");
  if (!root) {
    Serial.println("Failed to open SD root directory");
    return;
  }

  Serial.println("SD card root directory file list:");
  while (true) {
    File entry = root.openNextFile();
    if (!entry) break;
    Serial.printf("File: %s, Size: %lu\n", entry.name(), (unsigned long)entry.size());
    entry.close();
  }
  root.close();
}

static void initDisplay() {
  SPI.begin(kEpdSckPin, kEpdMisoPin, kEpdMosiPin, kEpdCsPin);
  display.init(115200);
  display.setRotation(0);
  display.setFullWindow();
  Serial.printf("Display dimensions: %d x %d\n", display.width(), display.height());
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.println("Plink Frame v0.1 starting...");

  initDisplay();

  if (!initSdCard()) {
    return;
  }

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
