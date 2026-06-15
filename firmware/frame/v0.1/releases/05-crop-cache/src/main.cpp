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
#include <ArduinoJson.h>
#include <vector>
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "freertos/semphr.h"

#include "Display_EPD_W21.h"
#include "Display_EPD_W21_spi.h"
#include "frame_config.h"

// Legacy single-image path (pre-queue firmware). Kept as a boot fallback so a frame that
// only ever received the old "send one image" flow still shows its last image.
static const char *kLegacyImage = "/image0.bmp";

// Frame-canonical gallery storage (v0.1 gallery model). See docs/products/frame/v0.1/gallery-model.md
static const char *kQueueFile = "/queue.json";
static const char *kImgDir    = "/img";    // panel-native display BMPs   (/img/<id>.bmp)
static const char *kOrigDir   = "/orig";   // ~1600×960 recrop masters    (/orig/<id>.jpg)
static const char *kThumbDir  = "/thumb";  // ~200px list thumbnails       (/thumb/<id>.jpg)

SPIClass sdSpi(HSPI);

static uint8_t *gFrameBuffer  = nullptr;
static BLECharacteristic *gStatusChar   = nullptr;
static BLECharacteristic *gQueueChar    = nullptr;
static BLECharacteristic *gAssetOutChar = nullptr;
static Preferences gPrefs;
static std::string gFrameName;   // canonical frame name, persisted in NVS
static volatile bool gBleConnected   = false;
static volatile bool gRendering      = false;

// ── Asset streaming state ────────────────────────────────────────────────────
// A single PSRAM buffer holds the in-flight asset. On COMMIT, ownership is handed to
// loop() (the buffer pointer is moved into the command) and gBleBuffer is nulled, so the
// NEXT BeginAsset allocates a fresh buffer. This lets the master JPEG stream while loop()
// is busy rendering the display BMP — BLE writes land on the BLE task into a buffer the
// renderer no longer owns. No SD I/O ever happens inside a BLE callback.
enum StreamKind : uint8_t { STREAM_NONE = 0, STREAM_LEGACY = 1, STREAM_BMP = 2, STREAM_JPEG = 3, STREAM_THUMB = 4, STREAM_CROP = 5 };
static uint8_t   *gBleBuffer    = nullptr;
static size_t     gBleBufferLen = 0;
static StreamKind gStreamKind   = STREAM_NONE;
static uint32_t   gStreamId     = 0;
static const size_t kBleBufferMax = 1300000; // 1.3 MB (display BMP ≈ 1.15 MB; master JPEG ≈ 0.3 MB)

// ── Command queue (BLE task → loop) ──────────────────────────────────────────
struct FrameCmd {
  uint8_t   op;
  uint8_t   kind;            // StreamKind, for COMMIT
  uint32_t  id;              // asset / item id
  uint8_t   idx;            // index param (remove/show/rename)
  uint8_t   showNow;         // add
  uint32_t  interval;        // seconds (interval op)
  uint32_t  offset;          // GetChunk: byte offset into the requested asset
  uint16_t  length;          // GetChunk: bytes to read
  uint8_t  *buf;             // owned PSRAM buffer (COMMIT) — loop() frees it
  size_t    bufLen;
  uint8_t   orderN;          // reorder length
  uint8_t   order[kMaxQueueItems];
  char      label[80];       // add / rename label
  char      asset[80];       // add: phone PHAsset.localIdentifier
};
static QueueHandle_t gCmdQueue = nullptr;

// ── In-memory queue (frame-canonical, persisted to /queue.json) ──────────────
static JsonDocument gQueue;
static uint32_t gNextRotateMs = 0;
static bool     gRotateArmed  = false;

// Pending asset read-back (GetAsset → GetChunk). The frame keeps the path/size between the
// length request and the chunk reads so it never holds the whole file in RAM at once.
static char   gReqPath[48] = {0};
static size_t gReqLen      = 0;

// Chunked queue read-back (GetQueue → GetChunk). When the published queue JSON exceeds the queue
// char's ~600 B GATT value cap, the app pulls it through the asset-out chunk path instead. The full
// JSON is staged in this PSRAM buffer for the duration of the read; gServingQueue routes GetChunk
// to it instead of an SD file. Mutually exclusive with a GetAsset read (each clears the other).
static bool   gServingQueue = false;
static char  *gQueueOutBuf  = nullptr;

// ── Async render + concurrency ───────────────────────────────────────────────
// The e-ink waveform blocks ~31 s. Running it in loop() stalled gCmdQueue draining, so commands
// tapped during a render (e.g. a Skip) piled up and replayed afterwards (bugs S, U). The render now
// runs on its own FreeRTOS task; loop() keeps draining commands throughout. EPD uses the global SPI
// bus (render task only); SD uses sdSpi/HSPI (loop only) — different buses, no SPI contention. SD
// calls are still serialized by gSdMutex (recursive) since both tasks touch the card, and BLE
// status notifies are serialized by gBleMutex (both tasks call notifyStatus).
static SemaphoreHandle_t gSdMutex   = nullptr;
static SemaphoreHandle_t gBleMutex  = nullptr;
static TaskHandle_t      gRenderTask = nullptr;
static char              gRenderPath[40] = {0};   // requested BMP path (single slot, latest-wins)
static uint32_t          gRenderReqId  = 0;        // item id for the request (0 = legacy/unknown)
static volatile bool     gRenderReqPending = false;
static portMUX_TYPE      gRenderReqMux = portMUX_INITIALIZER_UNLOCKED;
// Last item id actually painted to the panel, persisted to NVS. E-ink retains the image with no
// power, so on boot we skip re-rendering when the resolved current item already equals this (avoids
// the redundant ~31s flash every plug-in); we still render when it differs (queue edited while off).
static const char       *kLastRenderKey = "last_render";

// RAII lock for every SD access — serializes the render task's decode against loop()'s SD writes.
// Recursive so nested SD helpers (e.g. handleClear → deleteAllInDir) don't self-deadlock.
struct SdGuard {
  SdGuard()  { if (gSdMutex) xSemaphoreTakeRecursive(gSdMutex, portMAX_DELAY); }
  ~SdGuard() { if (gSdMutex) xSemaphoreGiveRecursive(gSdMutex); }
};

static void epd_reinit();
bool renderBmpFromSd(const char *path);
static void applyAdvertising();
static void resetRotate();
static void armRotateIfNeeded();
static long rotateSecondsRemaining();
static bool renderItem(int idx);
static void requestRenderPath(const char *path, uint32_t id = 0);
static JsonArray queueItems();
static int currentIdx();

static uint32_t rdU32LE(const uint8_t *p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static uint16_t rdU16LE(const uint8_t *p) { return (uint16_t)p[0] | ((uint16_t)p[1] << 8); }

static void bmpPathForId(uint32_t id, char *out, size_t n)   { snprintf(out, n, "%s/%08lX.bmp", kImgDir,   (unsigned long)id); }
static void origPathForId(uint32_t id, char *out, size_t n)  { snprintf(out, n, "%s/%08lX.jpg", kOrigDir,  (unsigned long)id); }
static void thumbPathForId(uint32_t id, char *out, size_t n) { snprintf(out, n, "%s/%08lX.jpg", kThumbDir, (unsigned long)id); }

// ── BLE helpers ──────────────────────────────────────────────────────────────

static void notifyStatus(uint8_t s) {
  // setValue+notify must be atomic as a pair — the render task and loop both call this, and an
  // interleave would notify the wrong byte. gBleMutex guards the pair.
  if (gBleMutex) xSemaphoreTake(gBleMutex, portMAX_DELAY);
  if (gStatusChar && gBleConnected) {
    gStatusChar->setValue(&s, 1);
    gStatusChar->notify();
  }
  if (gBleMutex) xSemaphoreGive(gBleMutex);
  Serial.printf("BLE status: 0x%02X\n", s);
}

// Serialize the in-memory queue into the queue characteristic (long READ) and ping the app
// via a dirty-notify on the status char. The app re-reads the queue char on 0x10.
// Serialize the queue for the app, adding the transient `next_in` countdown (seconds until the next
// auto-rotate, or absent if off). Added to the published value only — stripped before saveQueue() so
// it never persists. Shared by publishQueue() (fast char) and handleGetQueue() (chunked path).
static void buildPublishJson(std::string &out) {
  long rem = rotateSecondsRemaining();
  if (rem >= 0) gQueue["next_in"] = rem; else gQueue.remove("next_in");
  serializeJson(gQueue, out);
}

static void publishQueue() {
  if (!gQueueChar) return;
  std::string out;
  buildPublishJson(out);
  // The Bluedroid char value caps at ~600 B. Set it for small queues (legacy/fast path), but the
  // app always reads the queue via the chunked GetQueue path, so skip the oversized setValue that
  // would only log an error. Either way the dirty-notify tells the app to re-read.
  if (out.size() <= 512) gQueueChar->setValue(out);
  Serial.printf("Queue published (%zu bytes)%s\n", out.size(), out.size() > 512 ? " [chunked]" : "");
  notifyStatus(kBleStatusQueueDirty);
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
    // Mid-transfer disconnect: discard the in-flight buffer. A committed-but-unprocessed
    // buffer is already owned by loop() (gBleBuffer == nullptr) and is unaffected.
    if (gBleBuffer) { heap_caps_free(gBleBuffer); gBleBuffer = nullptr; }
    gBleBufferLen = 0;
    gStreamKind   = STREAM_NONE;
    pServer->startAdvertising();
  }
};

class ImageDataCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {
    uint8_t *data = pChar->getData();
    size_t   len  = pChar->getLength();
    if (!len) return;

    if (!gBleBuffer) {
      // Allocate the receive buffer. Normally BeginAsset already did this and set the kind;
      // a bare first chunk (no BeginAsset) is the legacy single-image flow.
      gBleBuffer = (uint8_t *)heap_caps_malloc(kBleBufferMax, MALLOC_CAP_SPIRAM);
      if (!gBleBuffer) {
        Serial.println("BLE: PSRAM alloc failed");
        notifyStatus(kBleStatusError);
        return;
      }
      gBleBufferLen = 0;
      if (gStreamKind == STREAM_NONE) gStreamKind = STREAM_LEGACY;
      notifyStatus(kBleStatusReceiving);
      Serial.printf("BLE: receiving (kind=%u) into PSRAM...\n", gStreamKind);
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

// Control characteristic: opcode + payload. Stream-framing opcodes mutate buffer state
// directly (PSRAM only, no SD I/O); queue ops are copied into a FreeRTOS command and
// drained in loop() so all SD/render work stays off the BLE task.
class ControlCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {
    size_t n = pChar->getLength();
    if (!n) return;
    const uint8_t *d = pChar->getData();
    uint8_t op = d[0];

    if (op == kBleAbort) {
      if (gBleBuffer) { heap_caps_free(gBleBuffer); gBleBuffer = nullptr; }
      gBleBufferLen = 0;
      gStreamKind   = STREAM_NONE;
      Serial.println("BLE: ABORT — buffer discarded");
      notifyStatus(kBleStatusReady);
      return;
    }

    if (op == kBleBeginAsset) {
      if (n < 6) { notifyStatus(kBleStatusError); return; }
      uint8_t kind = d[1];
      // Fresh buffer for the new asset; any prior in-flight buffer is discarded (the
      // committed one is already owned by loop()).
      if (gBleBuffer) { heap_caps_free(gBleBuffer); gBleBuffer = nullptr; }
      gBleBuffer = (uint8_t *)heap_caps_malloc(kBleBufferMax, MALLOC_CAP_SPIRAM);
      if (!gBleBuffer) { Serial.println("BLE: PSRAM alloc failed"); notifyStatus(kBleStatusError); return; }
      gBleBufferLen = 0;
      gStreamKind   = (kind == kAssetJpeg) ? STREAM_JPEG
                    : (kind == kAssetThumb) ? STREAM_THUMB
                    : (kind == kAssetCrop)  ? STREAM_CROP : STREAM_BMP;
      gStreamId     = rdU32LE(d + 2);
      Serial.printf("BLE: BEGIN_ASSET kind=%u id=%08lX\n", gStreamKind, (unsigned long)gStreamId);
      notifyStatus(kBleStatusReceiving);
      return;
    }

    FrameCmd c;
    memset(&c, 0, sizeof(c));
    c.op = op;

    if (op == kBleCommit) {
      if (!gBleBuffer) { Serial.println("BLE: COMMIT with no pending data"); notifyStatus(kBleStatusError); return; }
      // Hand buffer ownership to loop(); next BeginAsset allocates afresh.
      c.kind   = gStreamKind;
      c.id     = gStreamId;
      c.buf    = gBleBuffer;
      c.bufLen = gBleBufferLen;
      gBleBuffer    = nullptr;
      gBleBufferLen = 0;
      gStreamKind   = STREAM_NONE;
      Serial.printf("BLE: COMMIT kind=%u id=%08lX (%zu bytes) → loop\n", c.kind, (unsigned long)c.id, c.bufLen);
    } else if (op == kBleAdd) {
      if (n < 7) { notifyStatus(kBleStatusError); return; }
      c.showNow = d[1];
      c.id      = rdU32LE(d + 2);
      uint8_t ll = d[6];
      const uint8_t *p = d + 7;
      size_t rem = n - 7;
      size_t labLen = (ll < rem) ? ll : rem;
      if (labLen > sizeof(c.label) - 1) labLen = sizeof(c.label) - 1;
      memcpy(c.label, p, labLen); c.label[labLen] = 0;
      size_t assetOff = 7 + ll;
      if (assetOff < n) {
        size_t aLen = n - assetOff;
        if (aLen > sizeof(c.asset) - 1) aLen = sizeof(c.asset) - 1;
        memcpy(c.asset, d + assetOff, aLen); c.asset[aLen] = 0;
      }
    } else if (op == kBleRemove || op == kBleShow) {
      if (n < 2) { notifyStatus(kBleStatusError); return; }
      c.idx = d[1];
    } else if (op == kBleReorder) {
      if (n < 2) { notifyStatus(kBleStatusError); return; }
      uint8_t cnt = d[1];
      if (cnt > kMaxQueueItems || (size_t)(2 + cnt) > n) { notifyStatus(kBleStatusError); return; }
      c.orderN = cnt;
      memcpy(c.order, d + 2, cnt);
    } else if (op == kBleInterval) {
      if (n < 5) { notifyStatus(kBleStatusError); return; }
      c.interval = rdU32LE(d + 1);   // seconds (UInt32 LE — 24 h won't fit in UInt16)
    } else if (op == kBleRename) {
      if (n < 2) { notifyStatus(kBleStatusError); return; }
      c.idx = d[1];
      size_t labLen = n - 2;
      if (labLen > sizeof(c.label) - 1) labLen = sizeof(c.label) - 1;
      memcpy(c.label, d + 2, labLen); c.label[labLen] = 0;
    } else if (op == kBleGetAsset) {
      if (n < 6) { notifyStatus(kBleStatusError); return; }
      c.kind = d[1];               // asset kind (bmp/jpeg/thumb)
      c.id   = rdU32LE(d + 2);
    } else if (op == kBleGetChunk) {
      if (n < 7) { notifyStatus(kBleStatusError); return; }
      c.offset = rdU32LE(d + 1);
      c.length = rdU16LE(d + 5);
    } else if (op == kBleNext || op == kBleList || op == kBleClear || op == kBleGetQueue) {
      // no payload
    } else {
      Serial.printf("BLE: unknown control opcode 0x%02X\n", op);
      notifyStatus(kBleStatusError);
      return;
    }

    if (gCmdQueue && xQueueSend(gCmdQueue, &c, 0) != pdTRUE) {
      // Queue full (frame is mid-render, ~31 s, not draining). Drop the OLDEST queued command to
      // make room for the newest — for rapid interval/show spamming the latest intent is what
      // should win. Free any heap buffer the dropped command owned (e.g. a COMMIT) so it can't leak.
      // `old` is static, NOT a stack local: FrameCmd is ~260 B and a second one in this BLE-task
      // callback frame overflows the small BTC_TASK stack (canary trip on BEGIN_ASSET). The BLE
      // write callback is single-threaded, so a shared static is safe here.
      static FrameCmd old;
      if (xQueueReceive(gCmdQueue, &old, 0) == pdTRUE && old.buf) heap_caps_free(old.buf);
      if (xQueueSend(gCmdQueue, &c, 0) != pdTRUE) {   // still full → give up on this one
        if (c.buf) heap_caps_free(c.buf);
        notifyStatus(kBleStatusError);
        Serial.println("BLE: cmd queue full — dropped newest");
      } else {
        Serial.println("BLE: cmd queue full — dropped oldest to keep newest");
      }
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

  BLEService *pService = pServer->createService(BLEUUID(BLE_SERVICE_UUID), 30);

  // Image data — WRITE_NR for max throughput (no per-packet ACK)
  BLECharacteristic *pImgChar = pService->createCharacteristic(
    BLE_IMG_DATA_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE_NR
  );
  pImgChar->setCallbacks(new ImageDataCallbacks());

  // Control — WRITE (with response so sender knows the command was received)
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

  // Queue — READ (frame-canonical queue.json; ATT long-read for values > MTU)
  gQueueChar = pService->createCharacteristic(
    BLE_QUEUE_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ
  );
  {
    std::string out;
    serializeJson(gQueue, out);
    if (out.size() <= 512) gQueueChar->setValue(out);   // large queues served via GetQueue chunks
  }

  // Asset out — READ (frame→app asset bytes; thumbnail for lists, master for recrop). Loaded on
  // demand by kBleGetAsset; the app long-reads it after the 0x11 AssetReady notify.
  gAssetOutChar = pService->createCharacteristic(
    BLE_ASSET_OUT_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ
  );

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
  uint8_t *fb = nullptr;
  // Decode the BMP into the framebuffer under the SD lock, then release it BEFORE the ~31 s
  // waveform so loop() can read/write SD freely while the panel refreshes on the render task.
  {
    SdGuard _sd;
    File f = SD.open(path, FILE_READ);
    if (!f) { Serial.printf("Failed to open: %s\n", path); return false; }

    BmpHeader hdr;
    if (!parseBmpHeader(f, hdr)) { f.close(); return false; }
    Serial.printf("BMP: %ldx%ld, %ubpp\n", (long)hdr.width, (long)hdr.height, hdr.bpp);

    // Orientation/rotation is handled entirely in the app, which always sends a panel-native
    // 800×480 BMP already rotated for the mount. The firmware renders it directly — no rotation
    // here (the two portrait mounts are indistinguishable from BMP dims alone). Centering offsets
    // are kept as a safety so an unexpected smaller image letterboxes instead of corrupting.
    const int dw     = EPD_WIDTH;
    const int dh     = EPD_HEIGHT;
    const int xOff   = (dw - hdr.width)  / 2;
    const int yOff   = (dh - hdr.height) / 2;
    const int rowSize = ((hdr.width * 3 + 3) / 4) * 4;

    size_t fbBytes = (size_t)EPD_WIDTH * EPD_HEIGHT;
    fb = (uint8_t *)heap_caps_malloc(fbBytes, MALLOC_CAP_SPIRAM);
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
  }   // SD lock released — waveform below runs concurrent with loop() SD access

  gFrameBuffer = fb;
  Serial.println("BMP decoded — rendering...");

  Serial.printf("BMP decode: %u ms\n", millis() - tDecodeStart);

  uint32_t tWaveStart = millis();
  PIC_display(gFrameBuffer);
  EPD_sleep();
  Serial.printf("EPD waveform: %u ms\n", millis() - tWaveStart);
  Serial.println("Render complete");
  return true;
}

// Flush the panel through solid black/white passes to clear e-ink ghosting / color retention,
// then restore the shown image. Each PIC_display is a full ~31 s Spectra 6 refresh. Runs in
// loop() (ample stack) — triggered over USB serial by typing "clear" (frame.sh option 3). This
// is a dev/maintenance utility, not part of the BLE protocol.
static void clearGhost() {
  // clearGhost drives the EPD directly from loop(); the render task also owns the EPD. Refuse if a
  // render is in flight so the two never drive the panel at once. (loop() is blocked for the whole
  // ~124 s clear, so no BLE command can post a new render mid-clear.)
  if (gRendering) { Serial.println("clearGhost: render in progress — retry when idle"); return; }
  size_t fbBytes = (size_t)EPD_WIDTH * EPD_HEIGHT;
  uint8_t *fb = (uint8_t *)heap_caps_malloc(fbBytes, MALLOC_CAP_SPIRAM);
  if (!fb) { Serial.println("clearGhost: PSRAM alloc failed"); return; }
  const uint8_t passes[] = { 0x00, 0xFF, 0x00, 0xFF };   // black/white inversions; end white
  const unsigned n = sizeof(passes);
  Serial.printf("Clearing ghosting — %u passes (~%us)...\n", n, n * 31);
  for (unsigned i = 0; i < n; ++i) {
    memset(fb, passes[i], fbBytes);
    epd_reinit();
    PIC_display(fb);
    EPD_sleep();
    Serial.printf("  pass %u/%u (0x%02X) done\n", i + 1, n, passes[i]);
  }
  heap_caps_free(fb);
  Serial.println("Ghost clear complete — restoring current image.");
  // Don't leave the panel blank-white: re-render whatever the queue is showing.
  JsonArray items = queueItems();
  if (items.size() > 0) {
    int cur = currentIdx();
    if (cur < 0 || (size_t)cur >= items.size()) cur = 0;
    renderItem(cur);
  } else if (SD.exists(kLegacyImage)) {
    requestRenderPath(kLegacyImage);   // hand the restore to the render task (owns the EPD)
  }
}

// ── SD helpers ────────────────────────────────────────────────────────────────

static bool initSdCard() {
  sdSpi.begin(kSdSckPin, kSdMisoPin, kSdMosiPin, kSdCsPin);
  if (!SD.begin(kSdCsPin, sdSpi, 4000000)) {
    Serial.println("SD init failed"); return false;
  }
  Serial.println("SD init OK");
  if (!SD.exists(kImgDir))   SD.mkdir(kImgDir);
  if (!SD.exists(kOrigDir))  SD.mkdir(kOrigDir);
  if (!SD.exists(kThumbDir)) SD.mkdir(kThumbDir);
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

static bool writeBufToSd(const char *path, const uint8_t *buf, size_t len) {
  SdGuard _sd;
  uint32_t t0 = millis();
  if (SD.exists(path)) SD.remove(path);   // guard: removing a missing file logs a vfs [E] (Bug B)
  File f = SD.open(path, FILE_WRITE);
  if (!f) { Serial.printf("SD open for write failed: %s\n", path); return false; }
  size_t written = f.write(buf, len);
  f.flush();
  f.close();
  bool ok = (written == len);
  Serial.printf("SD write %s: %zu/%zu %s [%u ms]\n", path, written, len, ok ? "OK" : "INCOMPLETE", millis() - t0);
  return ok;
}

// ── Queue engine (frame-canonical; mirrors the Pi /api/queue/* semantics) ─────

static JsonArray queueItems() {
  if (!gQueue["items"].is<JsonArray>()) gQueue["items"].to<JsonArray>();
  return gQueue["items"].as<JsonArray>();
}
static int currentIdx() { return gQueue["current"] | 0; }
static void setCurrent(int idx) { gQueue["current"] = idx; }

static void loadQueue() {
  SdGuard _sd;
  File f = SD.open(kQueueFile, FILE_READ);
  if (f) {
    DeserializationError err = deserializeJson(gQueue, f);
    f.close();
    if (!err && gQueue["items"].is<JsonArray>()) {
      Serial.printf("Queue loaded: %u items, current=%d, interval=%d\n",
                    queueItems().size(), currentIdx(), (int)(gQueue["interval"] | 0));
      return;
    }
    Serial.printf("queue.json parse error (%s) — resetting\n", err.c_str());
  } else {
    Serial.println("No queue.json — starting empty");
  }
  gQueue.clear();
  gQueue["items"].to<JsonArray>();
  gQueue["current"]  = 0;
  gQueue["interval"] = 0;
}

static void saveQueue() {
  SdGuard _sd;
  gQueue.remove("next_in");   // transient (publish-only); never persist
  File f = SD.open(kQueueFile, FILE_WRITE);
  if (!f) { Serial.println("queue.json open for write failed"); return; }
  serializeJson(gQueue, f);
  f.flush();
  f.close();
}

// Sweep /img and /orig and delete any file whose id isn't referenced by the queue. Cleans up
// orphans left when the "keep last file on empty queue" rule retains a file the user later
// replaced. Called after remove and on boot.
static void pruneOrphanFiles() {
  SdGuard _sd;
  JsonArray items = queueItems();
  const char *dirs[] = { kImgDir, kOrigDir, kThumbDir };
  for (const char *dir : dirs) {
    File d = SD.open(dir);
    if (!d) continue;
    // Collect names first (deleting while iterating openNextFile is unsafe on some FS impls).
    String victims[kMaxQueueItems * 2];
    int nv = 0;
    while (nv < (int)(sizeof(victims) / sizeof(victims[0]))) {
      File e = d.openNextFile();
      if (!e) break;
      String name = e.name();          // basename, e.g. "6A2D9C3A.bmp"
      e.close();
      uint32_t id = (uint32_t)strtoul(name.c_str(), nullptr, 16);
      bool referenced = false;
      for (JsonObject it : items) if ((uint32_t)(it["id"] | 0u) == id) { referenced = true; break; }
      if (!referenced) { victims[nv++] = String(dir) + "/" + name; }
    }
    d.close();
    for (int i = 0; i < nv; ++i) {
      Serial.printf("Pruning orphan: %s\n", victims[i].c_str());
      SD.remove(victims[i]);
    }
  }
}

// Post a BMP path to the render task (single slot, latest-wins so spammed shows coalesce to the
// last one). Returns immediately — the ~31 s render happens on the render task, not the caller.
static void requestRenderPath(const char *path, uint32_t id) {
  portENTER_CRITICAL(&gRenderReqMux);
  strncpy(gRenderPath, path, sizeof(gRenderPath) - 1);
  gRenderPath[sizeof(gRenderPath) - 1] = 0;
  gRenderReqId = id;
  gRenderReqPending = true;
  portEXIT_CRITICAL(&gRenderReqMux);
  if (gRenderTask) xTaskNotifyGive(gRenderTask);
}

// Request an async render of queue item `idx`. Resolves idx→path on the caller (which owns the
// gQueue mutation), then hands off. Returns false only for an out-of-range index.
static bool renderItem(int idx) {
  JsonArray items = queueItems();
  if (idx < 0 || (size_t)idx >= items.size()) return false;
  uint32_t id = items[idx]["id"] | 0u;
  char path[40];
  bmpPathForId(id, path, sizeof(path));
  requestRenderPath(path, id);
  return true;
}

// The render task: waits for a request, then runs epd_reinit + decode + waveform off loop(). Drains
// to the latest pending path each wakeup so a burst of requests collapses to one final render.
static void renderTaskFn(void *) {
  for (;;) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    for (;;) {
      char path[40];
      uint32_t id;
      portENTER_CRITICAL(&gRenderReqMux);
      bool pending = gRenderReqPending;
      if (pending) { strncpy(path, gRenderPath, sizeof(path)); id = gRenderReqId; gRenderReqPending = false; }
      portEXIT_CRITICAL(&gRenderReqMux);
      if (!pending) break;

      gRendering = true;
      notifyStatus(kBleStatusRendering);
      uint32_t tInit = millis();
      epd_reinit();
      Serial.printf("EPD init: %u ms\n", millis() - tInit);
      bool ok = renderBmpFromSd(path);
      gRendering = false;
      // Remember what's now on the panel so boot can skip a redundant re-render (NVS skips the
      // write when the value is unchanged, so repeated renders of the same id don't wear flash).
      if (ok && id != 0) { gPrefs.begin("frame", false); gPrefs.putUInt(kLastRenderKey, id); gPrefs.end(); }
      notifyStatus(ok ? kBleStatusReady : kBleStatusError);
    }
  }
}

// Restart the countdown from now. Use only when the shown image actually changes (show/next/
// auto-rotate/add-show-now) or the interval is set — those are the events that should reset the
// "time until next" clock.
static void resetRotate() {
  uint32_t interval = gQueue["interval"] | 0;   // seconds
  int n = queueItems().size();
  if (interval > 0 && n > 1) {
    gNextRotateMs = millis() + interval * 1000UL;
    gRotateArmed  = true;
    Serial.printf("Auto-rotate reset: %u s (n=%d)\n", interval, n);
  } else {
    gRotateArmed = false;
  }
}

// Keep the existing countdown running; only arm/disarm if the armed-ness should change (e.g. a
// queue grew 1→2 items). Use for ops that must NOT reset the timer — rename, reorder,
// add-to-queue, remove. Per product: rearranging/renaming/recrop don't restart the clock.
static void armRotateIfNeeded() {
  uint32_t interval = gQueue["interval"] | 0;   // seconds
  int n = queueItems().size();
  if (interval > 0 && n > 1) {
    if (!gRotateArmed) { gNextRotateMs = millis() + interval * 1000UL; gRotateArmed = true; }
  } else {
    gRotateArmed = false;
  }
}

// Seconds until the next auto-rotate, or -1 if not armed. Published to the app so it can show a
// "next in …" countdown (the frame has no RTC; this is relative to millis()).
static long rotateSecondsRemaining() {
  if (!gRotateArmed) return -1;
  int32_t delta = (int32_t)(gNextRotateMs - millis());
  return delta > 0 ? (long)(delta / 1000) : 0;
}

// Delete an item's on-SD assets unless another queue item still references the same id.
static void deleteItemFiles(uint32_t id) {
  JsonArray items = queueItems();
  for (JsonObject it : items) {
    if ((uint32_t)(it["id"] | 0u) == id) return;   // still referenced
  }
  SdGuard _sd;
  char p[40];
  bmpPathForId(id, p, sizeof(p));  if (SD.exists(p)) SD.remove(p);
  origPathForId(id, p, sizeof(p)); if (SD.exists(p)) SD.remove(p);
}

static void handleAdd(const FrameCmd &c) {
  JsonArray items = queueItems();
  bool wasEmpty = items.size() == 0;
  int  newIdx;

  // NOTE: store label/asset as String(), NOT the raw char[]. ArduinoJson stores a char*/char[]
  // BY REFERENCE (assumes a string literal) — c.label lives on loop()'s reused stack slot, so
  // every item would alias the same address and all names collapse to the last one written.
  // String forces a copy into the document. (Root cause of the rename-hits-all / add-resets-all
  // / blank-label corruption.)
  if (c.showNow || wasEmpty) {
    JsonObject slot = items.add<JsonObject>();
    slot["id"]    = c.id;
    slot["label"] = String(c.label);
    if (c.asset[0]) slot["asset"] = String(c.asset);
    newIdx = items.size() - 1;
    setCurrent(newIdx);
  } else {
    // Insert before the currently-shown item; bump current so it still points at the same
    // shown item (mirrors the Pi insert-at-current behavior).
    int cur = currentIdx();
    if (cur < 0) cur = 0;
    if (cur > (int)items.size()) cur = items.size();
    items.add<JsonObject>();                          // grow by one (trailing slot)
    for (int i = (int)items.size() - 1; i > cur; --i) // shift right to open a hole at cur
      items[i].set(items[i - 1]);
    JsonObject slot = items[cur];
    slot.clear();
    slot["id"]    = c.id;
    slot["label"] = String(c.label);
    if (c.asset[0]) slot["asset"] = String(c.asset);
    newIdx = cur;
    setCurrent(cur + 1);
  }

  saveQueue();
  pruneOrphanFiles();   // drop any stale file left by the "keep last on empty" rule
  // Arm/reset the clock BEFORE publish so the published next_in is fresh.
  // add-to-queue (non-show) must not reset the clock — only arm if needed.
  if (c.showNow || wasEmpty) resetRotate(); else armRotateIfNeeded();
  publishQueue();
  if (c.showNow || wasEmpty) renderItem(newIdx);
}

static void handleRemove(const FrameCmd &c) {
  JsonArray items = queueItems();
  int idx = c.idx;
  if (idx < 0 || (size_t)idx >= items.size()) { notifyStatus(kBleStatusError); return; }

  int oldCurrent = currentIdx();
  uint32_t id = items[idx]["id"] | 0u;
  items.remove(idx);

  // Empty-after-remove: keep the last item's files on disk (still on e-ink). Otherwise
  // delete the removed item's assets (unless another item shares the id).
  if (items.size() > 0) deleteItemFiles(id);

  if (idx < oldCurrent) {
    setCurrent(oldCurrent - 1);                       // shown item shifted left
  } else if (currentIdx() >= (int)items.size() && currentIdx() > 0) {
    setCurrent((int)items.size() - 1);                // was at/after end → clamp
  }

  saveQueue();
  bool rerender = (idx == oldCurrent && items.size() > 0);
  if (rerender) resetRotate(); else armRotateIfNeeded();   // BEFORE publish for fresh next_in
  publishQueue();
  if (rerender) renderItem(currentIdx());
}

static void handleReorder(const FrameCmd &c) {
  JsonArray items = queueItems();
  int n = items.size();
  if (c.orderN != n || n > kMaxQueueItems) { notifyStatus(kBleStatusError); return; }
  // Validate the order is a permutation of 0..n-1.
  bool seen[kMaxQueueItems] = {false};
  for (int i = 0; i < n; ++i) {
    int v = c.order[i];
    if (v < 0 || v >= n || seen[v]) { notifyStatus(kBleStatusError); return; }
    seen[v] = true;
  }
  // Snapshot to plain values first. Building a new array from JsonVariants that still alias
  // the live document (and then overwriting that document) corrupts the items — copy out the
  // primitives, then rebuild the array in place from the snapshot.
  uint32_t ids[kMaxQueueItems];
  String   labels[kMaxQueueItems];
  String   assets[kMaxQueueItems];
  bool     hasAsset[kMaxQueueItems];
  for (int i = 0; i < n; ++i) {
    ids[i]      = items[i]["id"] | 0u;
    labels[i]   = (const char *)(items[i]["label"] | "");
    hasAsset[i] = items[i]["asset"].is<const char *>();
    assets[i]   = hasAsset[i] ? (const char *)(items[i]["asset"] | "") : String();
  }
  int cur = currentIdx();
  int newCur = 0;
  JsonArray ni = gQueue["items"].to<JsonArray>();   // clears the array
  for (int i = 0; i < n; ++i) {
    int src = c.order[i];
    JsonObject o = ni.add<JsonObject>();
    o["id"]    = ids[src];
    o["label"] = labels[src];
    if (hasAsset[src]) o["asset"] = assets[src];
    if (src == cur) newCur = i;
  }
  setCurrent(newCur);

  saveQueue();
  armRotateIfNeeded();   // reorder must not reset the clock (BEFORE publish for fresh next_in)
  publishQueue();
}

static void handleShow(const FrameCmd &c) {
  JsonArray items = queueItems();
  if (c.idx < 0 || (size_t)c.idx >= items.size()) { notifyStatus(kBleStatusError); return; }
  setCurrent(c.idx);
  saveQueue();
  resetRotate();         // shown image changed → restart the clock (BEFORE publish for fresh next_in)
  publishQueue();
  renderItem(c.idx);
}

static void handleNext() {
  JsonArray items = queueItems();
  int n = items.size();
  if (n < 2) { notifyStatus(kBleStatusError); return; }
  int next = (currentIdx() + 1) % n;
  setCurrent(next);
  saveQueue();
  resetRotate();         // BEFORE publish so next_in reflects the new clock
  publishQueue();
  renderItem(next);
}

static void handleInterval(const FrameCmd &c) {
  gQueue["interval"] = c.interval;
  saveQueue();
  resetRotate();         // interval change → restart the clock (BEFORE publish so next_in is fresh)
  publishQueue();
}

static void handleRename(const FrameCmd &c) {
  JsonArray items = queueItems();
  if (c.idx < 0 || (size_t)c.idx >= items.size()) { notifyStatus(kBleStatusError); return; }
  items[c.idx]["label"] = String(c.label);   // String → copy (see handleAdd note)
  saveQueue();
  publishQueue();
  // no rotate change — rename must not reset the clock
}

static void handleCommit(FrameCmd &c) {
  bool ok = false;
  char path[40];
  if (c.kind == STREAM_LEGACY) {
    // Back-compat: bare image, no queue entry. Write, then hand the render to the render task
    // (owns the EPD). The task notifies Rendering→Ready; only surface a write error here.
    ok = writeBufToSd(kLegacyImage, c.buf, c.bufLen);
    if (ok) requestRenderPath(kLegacyImage);
    else    notifyStatus(kBleStatusError);
  } else if (c.kind == STREAM_BMP) {
    bmpPathForId(c.id, path, sizeof(path));
    ok = writeBufToSd(path, c.buf, c.bufLen);   // no render — ADD/SHOW drives display
    notifyStatus(ok ? kBleStatusReady : kBleStatusError);
  } else if (c.kind == STREAM_JPEG) {
    origPathForId(c.id, path, sizeof(path));
    ok = writeBufToSd(path, c.buf, c.bufLen);   // recrop master; no render
    notifyStatus(ok ? kBleStatusReady : kBleStatusError);
  } else if (c.kind == STREAM_THUMB) {
    thumbPathForId(c.id, path, sizeof(path));
    ok = writeBufToSd(path, c.buf, c.bufLen);   // list thumbnail; no render
    notifyStatus(ok ? kBleStatusReady : kBleStatusError);
  } else if (c.kind == STREAM_CROP) {
    // Crop transformation JSON → stored opaque in the item's "crop" field (not an SD file), so the
    // app can re-seed Mantis on recrop and render crop-accurate thumbnails. Persists in queue.json.
    JsonDocument cropDoc;
    DeserializationError err = deserializeJson(cropDoc, c.buf, c.bufLen);
    if (!err) {
      JsonArray items = queueItems();
      for (JsonObject it : items) {
        if ((uint32_t)(it["id"] | 0u) == c.id) { it["crop"] = cropDoc; ok = true; break; }
      }
      if (ok) { saveQueue(); publishQueue(); }
      else Serial.printf("SetCrop: id %08lX not found\n", (unsigned long)c.id);
    } else {
      Serial.printf("SetCrop parse error: %s\n", err.c_str());
    }
    notifyStatus(ok ? kBleStatusReady : kBleStatusError);
  } else {
    Serial.println("COMMIT with unknown stream kind");
    notifyStatus(kBleStatusError);
  }
  if (c.buf) { heap_caps_free(c.buf); c.buf = nullptr; }
}

// Read-back is chunked so the frame never holds a whole asset (master ≈ 250 KB) in RAM at once.
// GetAsset records the path/size and returns the 4-byte length; the app then pulls fixed-size
// slices with GetChunk. Both run in loop() — SD I/O off the BLE task.
static void handleGetAsset(const FrameCmd &c) {
  if (!gAssetOutChar) { notifyStatus(kBleStatusError); return; }
  gServingQueue = false;   // a real asset read supersedes any in-flight queue read
  SdGuard _sd;
  char path[40];
  if (c.kind == kAssetJpeg)       origPathForId(c.id, path, sizeof(path));
  else if (c.kind == kAssetThumb) thumbPathForId(c.id, path, sizeof(path));
  else                            bmpPathForId(c.id, path, sizeof(path));

  File f = SD.open(path, FILE_READ);
  if (!f || f.size() == 0) {
    if (f) f.close();
    gReqPath[0] = 0; gReqLen = 0;
    Serial.printf("GetAsset miss: %s\n", path);
    notifyStatus(kBleStatusAssetMissing);
    return;
  }
  gReqLen = f.size();
  f.close();
  strncpy(gReqPath, path, sizeof(gReqPath) - 1);
  gReqPath[sizeof(gReqPath) - 1] = 0;
  uint8_t hdr[4] = { (uint8_t)(gReqLen), (uint8_t)(gReqLen >> 8), (uint8_t)(gReqLen >> 16), (uint8_t)(gReqLen >> 24) };
  gAssetOutChar->setValue(hdr, 4);
  Serial.printf("GetAsset ready: %s (%zu bytes)\n", path, gReqLen);
  notifyStatus(kBleStatusAssetReady);
}

static void deleteAllInDir(const char *dir) {
  SdGuard _sd;
  File d = SD.open(dir);
  if (!d) return;
  // Snapshot names to a heap vector (NOT a stack array — a fixed String[256] here overflowed the
  // loop-task stack and double-faulted on Clear). Then delete; can't remove while iterating the
  // open dir handle.
  std::vector<String> victims;
  for (;;) {
    File e = d.openNextFile();
    if (!e) break;
    victims.push_back(String(dir) + "/" + e.name());
    e.close();
  }
  d.close();
  for (auto &v : victims) SD.remove(v);
}

// Wipe the entire gallery: empty the queue and delete every stored asset. The frame is
// canonical, so this is the app's "reset" (deleting the app does NOT clear the frame).
static void handleClear() {
  gQueue["items"].to<JsonArray>();   // clears items
  setCurrent(0);
  gQueue["interval"] = 0;            // reset auto-rotate on clear (don't keep a stale interval)
  gRotateArmed = false;
  saveQueue();
  deleteAllInDir(kImgDir);
  deleteAllInDir(kOrigDir);
  deleteAllInDir(kThumbDir);
  publishQueue();
  Serial.println("Queue cleared (all assets deleted)");
}

// Serve one read-back slice. Runs in loop() (NOT the BLE write callback) — SD/FatFS needs more
// stack than the BTC_TASK has, and a 512 B buffer there overflows its canary. The app fires one
// GetChunk at a time and waits for the 0x11 ready-notify before reading; an app-side pending
// flag guards the case where the notify lands before the app registers its waiter.
// Stage the published queue JSON into PSRAM and hand the app the 4-byte length, mirroring GetAsset.
// The app then pulls it with GetChunk (routed to gQueueOutBuf below). Lets the gallery exceed the
// ~600 B queue-char cap that silently dropped queues past ~6 items.
static void handleGetQueue() {
  if (!gAssetOutChar) { notifyStatus(kBleStatusError); return; }
  std::string out;
  buildPublishJson(out);
  if (gQueueOutBuf) { heap_caps_free(gQueueOutBuf); gQueueOutBuf = nullptr; }
  size_t cap = out.size() ? out.size() : 1;
  gQueueOutBuf = (char *)heap_caps_malloc(cap, MALLOC_CAP_SPIRAM);
  if (!gQueueOutBuf) { gServingQueue = false; notifyStatus(kBleStatusError); return; }
  memcpy(gQueueOutBuf, out.data(), out.size());
  gReqLen       = out.size();
  gReqPath[0]   = 0;       // not SD-backed
  gServingQueue = true;
  uint8_t hdr[4] = { (uint8_t)(gReqLen), (uint8_t)(gReqLen >> 8), (uint8_t)(gReqLen >> 16), (uint8_t)(gReqLen >> 24) };
  gAssetOutChar->setValue(hdr, 4);
  Serial.printf("GetQueue ready (%zu bytes)\n", gReqLen);
  notifyStatus(kBleStatusAssetReady);
}

static void handleGetChunk(const FrameCmd &c) {
  if (!gAssetOutChar) { notifyStatus(kBleStatusError); return; }
  // Queue read-back: serve the slice straight from the staged PSRAM buffer (no SD).
  if (gServingQueue) {
    if (!gQueueOutBuf || c.offset >= gReqLen) { gAssetOutChar->setValue((uint8_t *)"", 0); notifyStatus(kBleStatusAssetReady); return; }
    uint16_t want = c.length;
    if (want > 512) want = 512;
    size_t avail = gReqLen - c.offset;
    if (want > avail) want = (uint16_t)avail;
    gAssetOutChar->setValue((uint8_t *)(gQueueOutBuf + c.offset), want);
    notifyStatus(kBleStatusAssetReady);
    return;
  }
  if (gReqPath[0] == 0) { notifyStatus(kBleStatusError); return; }
  SdGuard _sd;
  File f = SD.open(gReqPath, FILE_READ);
  if (!f) { notifyStatus(kBleStatusError); return; }
  if (!f.seek(c.offset)) { f.close(); notifyStatus(kBleStatusError); return; }
  // Bluedroid caps a characteristic value at 600 bytes (ESP_GATT_MAX_ATTR_LEN). Clamp the slice
  // so a stale/oversized app request can't wedge the read-back. App and firmware agree on 512.
  uint16_t want = c.length;
  if (want > 512) want = 512;
  uint8_t *buf = (uint8_t *)heap_caps_malloc(want, MALLOC_CAP_SPIRAM);
  if (!buf) { f.close(); notifyStatus(kBleStatusError); return; }
  size_t rd = f.read(buf, want);
  f.close();
  gAssetOutChar->setValue(buf, rd);
  heap_caps_free(buf);
  notifyStatus(kBleStatusAssetReady);
}

static void processCommand(FrameCmd &c) {
  switch (c.op) {
    case kBleCommit:   handleCommit(c);   break;
    case kBleAdd:      handleAdd(c);      break;
    case kBleRemove:   handleRemove(c);   break;
    case kBleReorder:  handleReorder(c);  break;
    case kBleShow:     handleShow(c);     break;
    case kBleNext:     handleNext();      break;
    case kBleInterval: handleInterval(c); break;
    case kBleRename:   handleRename(c);   break;
    case kBleList:     publishQueue();    break;
    case kBleGetAsset: handleGetAsset(c); break;
    case kBleGetChunk: handleGetChunk(c); break;
    case kBleGetQueue: handleGetQueue();  break;
    case kBleClear:    handleClear();     break;
    default: break;
  }
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
  Serial.println("Plink Frame v0.1 — BLE+SD (queue/gallery)");

  gCmdQueue = xQueueCreate(16, sizeof(FrameCmd));   // headroom for ops queued during a ~31s render
  gSdMutex  = xSemaphoreCreateRecursiveMutex();      // serialize all SD access (render task vs loop)
  gBleMutex = xSemaphoreCreateMutex();               // serialize status notifies (render task vs loop)
  // Render task: owns the EPD (global SPI bus); 8 KB stack covers epd_reinit + PIC_display. Core 1,
  // priority 1 (below the BLE/loop tasks) so a ~31 s waveform never starves command handling.
  xTaskCreatePinnedToCore(renderTaskFn, "render", 8192, nullptr, 1, &gRenderTask, 1);

  initDisplay();

  if (!initSdCard()) {
    Serial.println("SD failed — continuing to BLE init");
  } else {
    listRootFiles();
    loadQueue();
    // Prune orphans only when the queue is non-empty — an empty queue intentionally keeps the
    // last-shown file on disk (e-ink retention), so don't sweep it away.
    if (queueItems().size() > 0) pruneOrphanFiles();
    JsonArray items = queueItems();
    if (items.size() > 0) {
      // Resume the last shown item (frame-canonical).
      int cur = currentIdx();
      if (cur < 0 || (size_t)cur >= items.size()) { cur = 0; setCurrent(0); }
      uint32_t id = items[cur]["id"] | 0u;
      gPrefs.begin("frame", true);
      uint32_t lastRendered = gPrefs.getUInt(kLastRenderKey, 0);
      gPrefs.end();
      if (id == lastRendered) {
        // E-ink still shows this exact item (retained without power) — skip the redundant ~31s flash.
        Serial.printf("Resume: item %d already on panel (id %08lX) — skip render\n", cur, (unsigned long)id);
      } else {
        char path[40];
        bmpPathForId(id, path, sizeof(path));
        Serial.printf("Resuming queue item %d (%s)\n", cur, path);
        requestRenderPath(path, id);   // async on the render task — see note below
      }
    } else if (SD.exists(kLegacyImage)) {
      Serial.printf("Empty queue — rendering legacy %s\n", kLegacyImage);
      requestRenderPath(kLegacyImage);
    } else {
      Serial.println("Empty queue, no legacy image — nothing to render on boot");
    }
  }

  // Bring BLE up BEFORE the boot render finishes. The resume render is posted to the render task
  // above, so advertising starts within ~1 s instead of being blocked behind the ~41 s waveform —
  // which was leaving the frame unconnectable at power-on and causing the app's connect retries /
  // "searching" churn (Bug C).
  initBle();
  armRotateIfNeeded();
}

// ── Dev serial debug (USB UART) ──────────────────────────────────────────────
// List a directory's files + sizes; called per asset dir by the `ls` serial command.
static void serialLsDir(const char *dir) {
  File d = SD.open(dir);
  if (!d) { Serial.printf("%s: (missing)\n", dir); return; }
  Serial.printf("%s:\n", dir);
  int n = 0;
  for (;;) {
    File e = d.openNextFile();
    if (!e) break;
    Serial.printf("  %-20s %8u bytes\n", e.name(), (unsigned)e.size());
    e.close();
    n++;
  }
  d.close();
  if (n == 0) Serial.println("  (empty)");
}

// `ls` — dump the SD layout the queue/gallery uses.
static void serialLs() {
  SdGuard _sd;
  Serial.println("── SD ──");
  File qf = SD.open(kQueueFile, FILE_READ);
  if (qf) { Serial.printf("%s %8u bytes\n", kQueueFile, (unsigned)qf.size()); qf.close(); }
  else    Serial.printf("%s (missing)\n", kQueueFile);
  serialLsDir(kImgDir);
  serialLsDir(kOrigDir);
  serialLsDir(kThumbDir);
}

// `cat <path>` — stream a file to serial. Defaults to queue.json. Caps binary dumps so a stray
// `cat /img/x.bmp` can't flood the monitor — text files (queue.json) are small and print whole.
static void serialCat(const char *path) {
  SdGuard _sd;
  File f = SD.open(path, FILE_READ);
  if (!f) { Serial.printf("cat: %s not found\n", path); return; }
  size_t sz = f.size();
  Serial.printf("── %s (%u bytes) ──\n", path, (unsigned)sz);
  // JSON files: parse + pretty-print for readability (SD stays compact). Falls through to a raw
  // dump on parse error.
  String name(path);
  if (name.endsWith(".json")) {
    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, f);
    f.close();
    if (!err) { serializeJsonPretty(doc, Serial); Serial.println(); return; }
    Serial.printf("(parse error: %s — raw dump)\n", err.c_str());
    f = SD.open(path, FILE_READ);
    if (!f) return;
  }
  const size_t kCap = 4096;   // guard against binary blobs
  size_t printed = 0;
  uint8_t buf[128];
  while (f.available() && printed < kCap) {
    size_t rd = f.read(buf, sizeof(buf));
    Serial.write(buf, rd);
    printed += rd;
  }
  f.close();
  Serial.println();
  if (printed < sz) Serial.printf("…(truncated, %u/%u bytes)\n", (unsigned)printed, (unsigned)sz);
}

void loop() {
  // Drain queued BLE commands (SD/render work runs here, off the BLE task).
  FrameCmd c;
  if (gCmdQueue && xQueueReceive(gCmdQueue, &c, 0) == pdTRUE) {
    processCommand(c);
  }

  // Autonomous auto-rotate — no phone needed.
  if (gRotateArmed && !gRendering && (int32_t)(millis() - gNextRotateMs) >= 0) {
    JsonArray items = queueItems();
    int n = items.size();
    if (n > 1) {
      int next = (currentIdx() + 1) % n;
      setCurrent(next);
      saveQueue();
      resetRotate();        // re-arm from now BEFORE publish so next_in is fresh, not 0
      publishQueue();
      Serial.printf("Auto-rotate → item %d\n", next);
      renderItem(next);
    } else {
      resetRotate();        // ≤1 item → disarm
    }
  }

  // Dev maintenance over USB serial: clear (ghosting cycle), ls + cat (inspect SD). Accumulate
  // chars across loop iterations until a newline — readStringUntil()'s 1 s timeout fragmented
  // lines typed by hand (a slow `cat /img/x.bmp` arrived as several partial commands).
  static String gSerialLine;
  while (Serial.available()) {
    char ch = (char)Serial.read();
    Serial.write(ch);   // echo — the monitor has no local echo, so without this typing is invisible
    if (ch == '\n' || ch == '\r') {
      String cmd = gSerialLine; gSerialLine = "";
      cmd.trim();
      if (cmd.equalsIgnoreCase("clear")) clearGhost();
      else if (cmd.equalsIgnoreCase("ls")) serialLs();
      else if (cmd.equalsIgnoreCase("cat") || cmd.equalsIgnoreCase("cat queue.json")) serialCat(kQueueFile);
      else if (cmd.startsWith("cat ")) {
        String p = cmd.substring(4); p.trim();
        if (!p.startsWith("/")) p = "/" + p;   // accept "img/x.bmp" or "/img/x.bmp"
        serialCat(p.c_str());
      }
      else if (cmd.length()) Serial.printf("Unknown serial cmd: '%s'\n", cmd.c_str());
    } else {
      gSerialLine += ch;
    }
  }

  delay(10);
}
