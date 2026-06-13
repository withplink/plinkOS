#include <Arduino.h>
#include <SPI.h>
#include <SD.h>
#include <FS.h>
#include <esp_heap_caps.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Preferences.h>
#include <esp_gap_ble_api.h>

#include "Display_EPD_W21.h"
#include "Display_EPD_W21_spi.h"
#include "frame_config.h"

static const char *kImageName = "/image0.bmp";

SPIClass sdSpi(HSPI);

static uint8_t *gFrameBuffer  = nullptr;
static BLECharacteristic *gStatusChar = nullptr;
static Preferences gPrefs;
static std::string gFrameName;   // canonical frame name, persisted in NVS
static volatile bool gBleConnected   = false;
static volatile bool gBleReceiving   = false;
static volatile bool gRendering      = false;
static volatile bool gCommitPending  = false;

// PSRAM receive buffer — avoids any SD I/O inside BLE callbacks
static uint8_t *gBleBuffer    = nullptr;
static size_t   gBleBufferLen = 0;
static const size_t kBleBufferMax = 1300000; // 1.3 MB (BMP ≈ 1.15 MB)

static void epd_reinit();
bool renderBmpFromSd(const char *path);
static void applyAdvertising();

// ── BLE helpers ──────────────────────────────────────────────────────────────

static void notifyStatus(uint8_t s) {
  if (gStatusChar && gBleConnected) {
    gStatusChar->setValue(&s, 1);
    gStatusChar->notify();
  }
  Serial.printf("BLE status: 0x%02X\n", s);
}

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *) override {
    gBleConnected = true;
    Serial.println("BLE: connected");
    notifyStatus(kBleStatusReady);
  }
  void onDisconnect(BLEServer *pServer) override {
    gBleConnected = false;
    Serial.println("BLE: disconnected — restarting advertising");
    if (gBleReceiving) {
      // Mid-transfer disconnect: discard PSRAM buffer
      if (gBleBuffer) { heap_caps_free(gBleBuffer); gBleBuffer = nullptr; }
      gBleBufferLen = 0;
      gBleReceiving = false;
    }
    gCommitPending = false;
    pServer->startAdvertising();
  }
};

class ImageDataCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {
    if (gRendering || gCommitPending) return;
    uint8_t *data = pChar->getData();
    size_t   len  = pChar->getLength();
    if (!len) return;

    if (!gBleReceiving) {
      // First chunk: allocate PSRAM receive buffer
      if (gBleBuffer) { heap_caps_free(gBleBuffer); gBleBuffer = nullptr; }
      gBleBuffer = (uint8_t *)heap_caps_malloc(kBleBufferMax, MALLOC_CAP_SPIRAM);
      if (!gBleBuffer) {
        Serial.println("BLE: PSRAM alloc failed");
        notifyStatus(kBleStatusError);
        return;
      }
      gBleBufferLen = 0;
      gBleReceiving = true;
      notifyStatus(kBleStatusReceiving);
      Serial.println("BLE: receiving into PSRAM...");
    }

    if (gBleBufferLen + len > kBleBufferMax) {
      Serial.printf("BLE: overflow (%zu + %zu > %zu)\n", gBleBufferLen, len, kBleBufferMax);
      notifyStatus(kBleStatusError);
      return;
    }
    memcpy(gBleBuffer + gBleBufferLen, data, len);
    gBleBufferLen += len;
  }
};

class ControlCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {
    if (!pChar->getLength()) return;
    uint8_t cmd = pChar->getData()[0];

    if (cmd == kBleCommit) {
      if (!gBleReceiving || !gBleBuffer) {
        Serial.println("BLE: COMMIT with no pending data");
        notifyStatus(kBleStatusError);
        return;
      }
      gBleReceiving = false;
      Serial.printf("BLE: COMMIT — %zu bytes in PSRAM — handing to main loop\n", gBleBufferLen);
      // Hand off to loop() — no SD I/O in BLE callback
      gCommitPending = true;

    } else if (cmd == kBleAbort) {
      if (gBleBuffer) { heap_caps_free(gBleBuffer); gBleBuffer = nullptr; }
      gBleBufferLen = 0;
      gBleReceiving = false;
      Serial.println("BLE: ABORT — buffer discarded");
      notifyStatus(kBleStatusReady);
    }
  }
};

// Frame name — canonical on the device, persisted in NVS, set by the app over BLE.
class NameCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {
    size_t n = pChar->getLength();
    if (n == 0) return;
    std::string name((const char *)pChar->getData(), n);
    gFrameName = name;
    gPrefs.begin("frame", false);
    gPrefs.putString("name", gFrameName.c_str());
    gPrefs.end();
    pChar->setValue(gFrameName);
    // Update the connected-device GAP name…
    esp_ble_gap_set_device_name(gFrameName.c_str());
    // …and rebuild the advertising/scan-response payload so the new name actually
    // broadcasts. The app disconnects right after this write; onDisconnect →
    // startAdvertising() then sends the rebuilt scan-response — no reboot needed (#2).
    // (Without this, BLEAdvertising replays the name bytes cached at init.)
    applyAdvertising();
    Serial.printf("BLE: frame renamed to '%s' (advertising rebuilt)\n", gFrameName.c_str());
  }
};

// Build the advertising payload from the current gFrameName. The frame name rides in the
// scan-response packet; the 128-bit service UUID is the primary-adv capability gate. Setting
// the name explicitly (vs relying on BLEAdvertising's default device-name include) lets a
// rename rebuild it live — the default caches the init-time name and startAdvertising()
// replays stale bytes, so the old name kept broadcasting until reboot (#2). Does not start
// advertising; callers start (initBle) or rely on onDisconnect → startAdvertising() (rename).
static void applyAdvertising() {
  BLEAdvertising *pAdv = BLEDevice::getAdvertising();
  pAdv->stop();

  BLEAdvertisementData advData;
  advData.setFlags(0x06);  // LE General Discoverable, BR/EDR not supported
  advData.setCompleteServices(BLEUUID(BLE_SERVICE_UUID));
  pAdv->setAdvertisementData(advData);

  BLEAdvertisementData scanResp;
  scanResp.setName(gFrameName);
  pAdv->setScanResponseData(scanResp);

  pAdv->setMinPreferred(0x06);
}

static void initBle() {
  // Load the persisted name (default to the build-time name on first boot).
  gPrefs.begin("frame", true);
  gFrameName = std::string(gPrefs.getString("name", BLE_DEVICE_NAME).c_str());
  gPrefs.end();

  BLEDevice::init(gFrameName);
  BLEDevice::setMTU(512);

  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService *pService = pServer->createService(BLE_SERVICE_UUID);

  // Image data — WRITE_NR for max throughput (no per-packet ACK)
  BLECharacteristic *pImgChar = pService->createCharacteristic(
    BLE_IMG_DATA_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE_NR
  );
  pImgChar->setCallbacks(new ImageDataCallbacks());

  // Control — WRITE (with response so sender knows COMMIT was received)
  BLECharacteristic *pCtrlChar = pService->createCharacteristic(
    BLE_CONTROL_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pCtrlChar->setCallbacks(new ControlCallbacks());

  // Status — NOTIFY + READ (read on connect; notify on state change)
  gStatusChar = pService->createCharacteristic(
    BLE_STATUS_CHAR_UUID,
    BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ
  );
  gStatusChar->addDescriptor(new BLE2902());
  uint8_t initStatus = kBleStatusReady;
  gStatusChar->setValue(&initStatus, 1);

  // Name — READ (app syncs canonical name) + WRITE (app renames, persisted to NVS)
  BLECharacteristic *pNameChar = pService->createCharacteristic(
    BLE_NAME_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE
  );
  pNameChar->setValue(gFrameName);
  pNameChar->setCallbacks(new NameCallbacks());

  pService->start();

  applyAdvertising();
  BLEDevice::startAdvertising();
  Serial.printf("BLE advertising as '%s'\n", gFrameName.c_str());
}

// ── BMP / display (unchanged from 01-sd-display) ─────────────────────────────

struct BmpHeader {
  uint32_t pixelOffset = 0;
  int32_t  width       = 0;
  int32_t  height      = 0;
  uint16_t bpp         = 0;
  uint32_t compression = 0;
  bool     topDown     = false;
};

static uint32_t readU32LE(File &f) {
  uint8_t b[4];
  if (f.read(b, 4) != 4) return 0;
  return (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
}

static int32_t readS32LE(File &f) { return (int32_t)readU32LE(f); }

static uint16_t readU16LE(File &f) {
  uint8_t b[2];
  if (f.read(b, 2) != 2) return 0;
  return (uint16_t)b[0] | ((uint16_t)b[1] << 8);
}

static bool parseBmpHeader(File &f, BmpHeader &hdr) {
  if (f.size() < 54) { Serial.println("BMP too small"); return false; }
  uint8_t sig[2];
  if (f.read(sig, 2) != 2 || sig[0] != 'B' || sig[1] != 'M') {
    Serial.println("Not a BMP file"); return false;
  }
  (void)readU32LE(f); (void)readU16LE(f); (void)readU16LE(f);
  hdr.pixelOffset = readU32LE(f);
  uint32_t dibSize = readU32LE(f);
  if (dibSize < 40) { Serial.printf("Unsupported DIB header: %u\n", dibSize); return false; }
  hdr.width    = readS32LE(f);
  hdr.height   = readS32LE(f);
  hdr.topDown  = hdr.height < 0;
  if (hdr.topDown) hdr.height = -hdr.height;
  uint16_t planes = readU16LE(f);
  hdr.bpp         = readU16LE(f);
  hdr.compression = readU32LE(f);
  if (planes != 1)         { Serial.printf("Unsupported planes: %u\n", planes);       return false; }
  if (hdr.bpp != 24)       { Serial.printf("Unsupported BMP bpp: %u\n", hdr.bpp);     return false; }
  if (hdr.compression != 0){ Serial.printf("Unsupported compression: %u\n", hdr.compression); return false; }
  return true;
}

// Maps 24-bit RGB → GooDisplay token. Tokens: 0x00=black 0xFF=white 0xFC=yellow 0xE0=red 0x03=blue 0x1C=green
static uint8_t nearestSpectra6Color(uint8_t r, uint8_t g, uint8_t b) {
  struct PaletteEntry { uint8_t r, g, b, token; };
  static const PaletteEntry palette[] = {
    {0,   0,   0,   0x00},
    {255, 255, 255, 0xFF},
    {255, 255, 0,   0xFC},
    {255, 0,   0,   0xE0},
    {0,   0,   255, 0x03},
    {0,   128, 0,   0x1C},
  };
  uint32_t bestDist = UINT32_MAX;
  uint8_t  bestToken = 0xFF;
  for (const auto &e : palette) {
    int dr = (int)r - (int)e.r, dg = (int)g - (int)e.g, db = (int)b - (int)e.b;
    uint32_t dist = (uint32_t)(dr*dr + dg*dg + db*db);
    if (dist < bestDist) { bestDist = dist; bestToken = e.token; }
  }
  return bestToken;
}

bool renderBmpFromSd(const char *path) {
  // Free previous framebuffer so repeated renders don't leak PSRAM.
  if (gFrameBuffer) {
    heap_caps_free(gFrameBuffer);
    gFrameBuffer = nullptr;
  }

  uint32_t tDecodeStart = millis();
  File f = SD.open(path, FILE_READ);
  if (!f) { Serial.printf("Failed to open: %s\n", path); return false; }

  BmpHeader hdr;
  if (!parseBmpHeader(f, hdr)) { f.close(); return false; }
  Serial.printf("BMP: %ldx%ld, %ubpp\n", (long)hdr.width, (long)hdr.height, hdr.bpp);

  // Orientation is inferred from the BMP dimensions the app sends — no extra protocol.
  // Portrait (e.g. 480×800, height > width) is rotated 90°CW onto the native 800×480
  // panel; landscape (800×480) renders directly. See kFrameRotation note in frame_config.h.
  const bool rotate = (hdr.height > hdr.width);

  const int dw     = rotate ? EPD_HEIGHT : EPD_WIDTH;
  const int dh     = rotate ? EPD_WIDTH  : EPD_HEIGHT;
  const int xOff   = (dw - hdr.width)  / 2;
  const int yOff   = (dh - hdr.height) / 2;
  const int rowSize = ((hdr.width * 3 + 3) / 4) * 4;

  size_t fbBytes = (size_t)EPD_WIDTH * EPD_HEIGHT;
  uint8_t *fb = (uint8_t *)heap_caps_malloc(fbBytes, MALLOC_CAP_SPIRAM);
  if (!fb) { Serial.println("PSRAM alloc failed"); f.close(); return false; }
  memset(fb, 0xFF, fbBytes);

  uint8_t *row = (uint8_t *)heap_caps_malloc(rowSize, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
  if (!row) { Serial.println("Row buffer alloc failed"); heap_caps_free(fb); f.close(); return false; }

  for (int y = 0; y < hdr.height; ++y) {
    int srcRow = hdr.topDown ? y : (hdr.height - 1 - y);
    if (!f.seek(hdr.pixelOffset + (uint32_t)srcRow * rowSize)) {
      Serial.printf("Seek failed row %d\n", srcRow);
      heap_caps_free(row); heap_caps_free(fb); f.close(); return false;
    }
    if (f.read(row, rowSize) != rowSize) {
      Serial.printf("Short read row %d\n", srcRow);
      heap_caps_free(row); heap_caps_free(fb); f.close(); return false;
    }
    for (int x = 0; x < hdr.width; ++x) {
      int dx = x + xOff, dy = y + yOff;
      if (dx >= 0 && dy >= 0 && dx < dw && dy < dh)
        fb[dy * dw + dx] = nearestSpectra6Color(row[x*3+2], row[x*3+1], row[x*3+0]);
    }
  }
  heap_caps_free(row);
  f.close();

  if (rotate) {
    uint8_t *physFb = (uint8_t *)heap_caps_malloc(fbBytes, MALLOC_CAP_SPIRAM);
    if (!physFb) { Serial.println("Rotation buffer alloc failed"); heap_caps_free(fb); return false; }
    for (int lx = 0; lx < EPD_WIDTH; lx++)
      for (int ly = 0; ly < EPD_HEIGHT; ly++)
        physFb[ly * EPD_WIDTH + lx] = fb[(EPD_WIDTH - 1 - lx) * EPD_HEIGHT + ly];
    heap_caps_free(fb);
    gFrameBuffer = physFb;
    Serial.println("BMP decoded + rotated 90°CW — rendering...");
  } else {
    gFrameBuffer = fb;
    Serial.println("BMP decoded — rendering...");
  }

  Serial.printf("BMP decode: %u ms\n", millis() - tDecodeStart);

  uint32_t tWaveStart = millis();
  PIC_display(gFrameBuffer);
  EPD_sleep();
  Serial.printf("EPD waveform: %u ms\n", millis() - tWaveStart);
  Serial.println("Render complete");
  return true;
}

// ── SD helpers ────────────────────────────────────────────────────────────────

static bool initSdCard() {
  sdSpi.begin(kSdSckPin, kSdMisoPin, kSdMosiPin, kSdCsPin);
  if (!SD.begin(kSdCsPin, sdSpi, 4000000)) {
    Serial.println("SD init failed"); return false;
  }
  Serial.println("SD init OK");
  return true;
}

static void listRootFiles() {
  File root = SD.open("/");
  if (!root) { Serial.println("SD root open failed"); return; }
  Serial.println("SD root:");
  while (true) {
    File entry = root.openNextFile();
    if (!entry) break;
    Serial.printf("  %s  %lu bytes\n", entry.name(), (unsigned long)entry.size());
    entry.close();
  }
  root.close();
}

// ── Display helpers ───────────────────────────────────────────────────────────

static void epd_reinit() {
  delay(200);
#if EPD_USE_FAST_INIT
  EPD_init_fast();
#else
  EPD_init();
#endif
}

static void initDisplay() {
  pinMode(kEpdPowerCtrlPin, OUTPUT);
  digitalWrite(kEpdPowerCtrlPin, LOW);
  delay(100);
  Serial.printf("EPD power ON (GPIO %d)\n", kEpdPowerCtrlPin);

  pinMode(kEpdBusyPin, INPUT);
  pinMode(kEpdResetPin, OUTPUT);
  pinMode(kEpdDcPin, OUTPUT);
  pinMode(kEpdCsPin, OUTPUT);

  SPI.begin(12, 13, 11, -1);
  SPI.beginTransaction(SPISettings(10000000, MSBFIRST, SPI_MODE0));

#if EPD_USE_FAST_INIT
  Serial.println("EPD init: fast");
#else
  Serial.println("EPD init: slow (~31s)");
#endif
  epd_reinit();
  Serial.printf("Display: %d x %d\n", EPD_WIDTH, EPD_HEIGHT);
}

// ── Entry points ──────────────────────────────────────────────────────────────

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.println("Plink Frame v0.1 — BLE+SD");

  initDisplay();

  if (!initSdCard()) {
    Serial.println("SD failed — continuing to BLE init");
  } else {
    listRootFiles();
    if (SD.exists(kImageName)) {
      Serial.printf("Found %s — rendering on boot\n", kImageName);
      renderBmpFromSd(kImageName);
    } else {
      Serial.printf("No image at %s\n", kImageName);
    }
  }

  initBle();
}

void loop() {
  if (gCommitPending) {
    gCommitPending = false;
    gRendering = true;

    Serial.printf("loop: writing %zu bytes to SD...\n", gBleBufferLen);
    uint32_t tSdStart = millis();
    SD.remove(kImageName);
    File f = SD.open(kImageName, FILE_WRITE);
    bool sdOk = false;
    if (f) {
      size_t written = f.write(gBleBuffer, gBleBufferLen);
      f.flush();
      f.close();
      sdOk = (written == gBleBufferLen);
      Serial.printf("SD write: %zu/%zu bytes %s [%u ms]\n",
                    written, gBleBufferLen, sdOk ? "OK" : "INCOMPLETE", millis() - tSdStart);
    } else {
      Serial.println("loop: SD open for write failed");
    }

    heap_caps_free(gBleBuffer);
    gBleBuffer = nullptr;
    gBleBufferLen = 0;

    if (!sdOk) {
      gRendering = false;
      notifyStatus(kBleStatusError);
    } else {
      notifyStatus(kBleStatusRendering);
      uint32_t tInitStart = millis();
      epd_reinit();
      Serial.printf("EPD init: %u ms\n", millis() - tInitStart);
      bool ok = renderBmpFromSd(kImageName);
      gRendering = false;
      notifyStatus(ok ? kBleStatusReady : kBleStatusError);
    }
  }
  delay(10);
}
