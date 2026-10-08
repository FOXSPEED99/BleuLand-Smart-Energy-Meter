// SEM-1 Smart Energy Meter: production firmware
//
// Two things run side by side:
//  - meterTask (high priority): reads the HLW8032, averages every second,
//    counts energy and drives the LEDs. Nothing else can slow it down, so no
//    energy is missed even while the network code is busy.
//  - loop(): WiFi, clock, the 5-minute history log, the button, the local web
//    API and the serial console.
#include <Arduino.h>
#include <Wire.h>
#include <esp_arduino_version.h>
#include <esp_ota_ops.h>
#include <esp_sntp.h>
#include <esp_task_wdt.h>
#include <sys/time.h>

#include "app.h"
#include "sem1.h"
#include "board.h"
#include "config.h"
#include "console.h"
#include "flash_partition.h"
#include "hlw8032.h"
#include "leds.h"
#include "local_api.h"
#include "meter.h"
#include "net.h"
#include "settings.h"

#if ESP_ARDUINO_VERSION_MAJOR != 2
#error "SEM-1 needs board package 'esp32 by Espressif Systems' version 2.0.17 (Tools > Board > Boards Manager)"
#endif

using namespace sem1;

namespace {
HardwareSerial HlwSerial(HLW_UART);
Hlw8032 hlw;
Meter meter;
IntervalStats interval;
uint32_t lastPacketMs = 0;
SemaphoreHandle_t mtx;

RtcDs1307 rtcChip;
PartitionFlash logFlash;
DataLog dataLog;
bool logOk = false;
uint32_t uploadedSeqVal = 0;

volatile TimeSource timeSrc = TimeSource::None;
volatile bool ntpSynced = false;

struct Lock {
  Lock() { xSemaphoreTake(mtx, portMAX_DELAY); }
  ~Lock() { xSemaphoreGive(mtx); }
};

void applyCoeffs() {
  const Settings& s = settings::get();
  HlwCoeffs c;
  c.kv = KV;
  c.ki = KI;
  c.calV = s.calV;
  c.calI = s.calI;
  c.calP = s.calP;
  Lock l;
  hlw.setCoeffs(c);
  meter.setEnergySource(s.energySource);
}

// ---------------- metering task ----------------
void meterTask(void*) {
  esp_task_wdt_add(nullptr);
  HlwSample s;
  Reading r;
  for (;;) {
    while (HlwSerial.available()) {
      uint8_t b = HlwSerial.read();
      Lock l;
      if (hlw.feed(b, s)) {
        meter.add(s);
        lastPacketMs = millis();
      }
    }
    uint32_t pulses = 0;
    {
      Lock l;
      if (meter.tick(millis(), r)) {
        interval.add(r);
        interval.flags |= meter.takeFlags();  // same bit values as LogFlags
        pulses = meter.takeWhPulses();
      }
    }
    if (pulses) leds::addEnergyPulses(pulses);
    leds::update(millis());
    esp_task_wdt_reset();
    vTaskDelay(pdMS_TO_TICKS(10));
  }
}

// ---------------- clock ----------------
void onNtpSync(struct timeval*) { ntpSynced = true; }

void setSystemTime(time_t t) {
  struct timeval tv = {t, 0};
  settimeofday(&tv, nullptr);
}

void clockLoop() {
  static bool sntpStarted = false;
  if (!sntpStarted && net::online()) {
    sntpStarted = true;
    sntp_set_time_sync_notification_cb(onNtpSync);
    configTime(0, 0, "pool.ntp.org", "time.google.com", "time.cloudflare.com");  // UTC
  }
  if (ntpSynced) {
    ntpSynced = false;
    timeSrc = TimeSource::Ntp;
    if (rtcChip.present()) rtcChip.write(time(nullptr));  // keep the RTC right (hourly)
  }
}

// ---------------- energy backup ----------------
void restoreEnergy() {
  uint64_t mwh = settings::loadEnergyMilliWh();
  EnergyBackup b;
  if (rtcChip.present() && rtcChip.loadBackup(b)) {
    if (b.energyMilliWh > mwh) mwh = b.energyMilliWh;
    uploadedSeqVal = b.uploadedSeq;
  }
  LogRecord last;
  if (logOk && dataLog.latest(last) && (uint64_t)last.energyDWh * 100 > mwh) mwh = (uint64_t)last.energyDWh * 100;
  Lock l;
  meter.setTotalWh(mwh / 1000.0);
  Serial.printf("[energy] restored %.3f kWh\n", mwh / 1e6);
}

uint64_t totalMilliWh() {
  Lock l;
  return (uint64_t)(meter.totalWh() * 1000.0);
}

void backupLoop() {
  static uint32_t lastRtcMs = 0, lastNvsMs = 0;
  uint32_t now = millis();
  if (rtcChip.present() && now - lastRtcMs >= ENERGY_BACKUP_MS) {
    lastRtcMs = now;
    EnergyBackup b;
    b.energyMilliWh = totalMilliWh();
    b.uploadedSeq = uploadedSeqVal;
    rtcChip.saveBackup(b);
  }
  // Flash copy: often if there is no RTC, otherwise every 6 h as a spare.
  uint32_t nvsEvery = rtcChip.present() ? 6UL * 3600 * 1000 : ENERGY_NVS_BACKUP_MS;
  if (now - lastNvsMs >= nvsEvery) {
    lastNvsMs = now;
    settings::saveEnergyMilliWh(totalMilliWh());
  }
}

// ---------------- 5-minute history log ----------------
void logLoop() {
  static uint32_t periodEnd = 0, startTs = 0;
  static double whAtStart = 0;
  static uint8_t pendingFlags = kLogBoot;
  if (!logOk) return;
  time_t t = app::now();
  if (!t) return;  // clock unknown: energy keeps counting, records start once time is known
  uint32_t now = (uint32_t)t;
  uint32_t pe = now - now % LOG_INTERVAL_S;
  double wh;
  {
    Lock l;
    wh = meter.totalWh();
  }
  if (!periodEnd || pe < periodEnd) {  // first run, or the clock was moved back
    periodEnd = pe;
    startTs = now;
    whAtStart = wh;
    return;
  }
  if (pe == periodEnd) return;

  IntervalStats st;
  {
    Lock l;
    st = interval;
    interval.reset();
  }
  uint32_t span = now > startTs ? now - startTs : 1;
  double pAvg = (wh - whAtStart) * 3600.0 / span;

  LogRecord rec = {};
  rec.ts = pe;
  rec.energyDWh = (uint32_t)(wh * 10.0);
  rec.pAvgW = (uint16_t)constrain(pAvg + 0.5, 0.0, 65535.0);
  rec.pMaxW = (uint16_t)constrain(st.pMax + 0.5f, 0.0f, 65535.0f);
  rec.vAvgDV = (uint16_t)constrain(st.vAvg() * 10.0f + 0.5f, 0.0f, 65535.0f);
  rec.flags = st.flags | pendingFlags | (timeSrc == TimeSource::Ntp ? 0 : kLogTimeRtc);
  uint32_t seq = dataLog.append(rec);
  if (!seq) Serial.println("[log] write failed");

  pendingFlags = 0;
  periodEnd = pe;
  startTs = now;
  whAtStart = wh;
}

// ---------------- button ----------------
void buttonLoop() {
  static uint32_t pressedAt = 0;
  uint32_t now = millis();
  bool down = digitalRead(PIN_BUTTON) == LOW;
  if (down && !pressedAt) pressedAt = now ? now : 1;
  if (!down && pressedAt) {
    uint32_t held = now - pressedAt;
    pressedAt = 0;
    if (held >= BUTTON_FACTORY_RESET_MS) {
      Serial.println("[button] factory reset");
      settings::factoryReset();
      net::forgetWifiAndRestart();
    } else if (held >= BUTTON_WIFI_RESET_MS) {
      Serial.println("[button] WiFi reset");
      net::forgetWifiAndRestart();
    }
  }
  if (pressedAt) {
    uint32_t held = now - pressedAt;
    if (held >= BUTTON_FACTORY_RESET_MS) {
      leds::setWifi(WifiLed::FactoryArmed);
      return;
    }
    if (held >= BUTTON_WIFI_RESET_MS) {
      leds::setWifi(WifiLed::ResetArmed);
      return;
    }
  }
  switch (net::state()) {
    case NetState::Setup: leds::setWifi(WifiLed::Setup); break;
    case NetState::Connecting: leds::setWifi(WifiLed::Connecting); break;
    case NetState::Online: leds::setWifi(WifiLed::Online); break;
  }
}
}  // namespace

// ---------------- app:: (used by the API and console) ----------------
namespace app {

LiveSnapshot snapshot() {
  LiveSnapshot s;
  Lock l;
  s.reading = meter.last();
  s.totalWh = meter.totalWh();
  s.altWhBoot = meter.altWhSinceBoot();
  s.goodPackets = hlw.goodPackets();
  s.badPackets = hlw.badPackets();
  s.packetAgeMs = lastPacketMs ? millis() - lastPacketMs : 0;
  s.haveRaw = hlw.hasPacket();
  memcpy(s.raw, hlw.lastPacket(), sizeof(s.raw));
  return s;
}

time_t now() {
  time_t t = time(nullptr);
  return t >= (time_t)MIN_VALID_UNIX ? t : 0;
}

TimeSource timeSource() { return timeSrc; }
const char* timeSourceName() {
  switch (timeSrc) {
    case TimeSource::Ntp: return "ntp";
    case TimeSource::Rtc: return "rtc";
    default: return "none";
  }
}

RtcDs1307& rtc() { return rtcChip; }
DataLog& log() { return dataLog; }
uint32_t uploadedSeq() { return uploadedSeqVal; }

String calibrate(char what, float target) {
  Reading r = snapshot().reading;
  Settings& s = settings::get();
  String msg;
  if (what == 'v') {
    if (r.v > 50 && target > 50) {
      s.calV *= target / r.v;
      msg = "Voltage calibrated";
    } else return "Need mains connected (V > 50)";
  } else if (what == 'i') {
    if (r.i > 0.2f && target > 0.2f) {
      s.calI *= target / r.i;
      msg = "Current calibrated";
    } else return "Need a load above 0.2 A";
  } else if (what == 'p') {
    if (r.p > 50 && target > 50) {
      s.calP *= target / r.p;
      msg = "Power calibrated";
    } else return "Need a load above 50 W";
  } else {
    return "Unknown value";
  }
  settings::saveCalibration();
  applyCoeffs();
  return msg;
}

String resetCalibration() {
  Settings& s = settings::get();
  s.calV = s.calI = s.calP = 1.0f;
  settings::saveCalibration();
  applyCoeffs();
  return "Calibration reset";
}

String setEnergySource(EnergySource src) {
  settings::get().energySource = src;
  settings::saveEnergySource();
  applyCoeffs();
  return src == EnergySource::PfPulses ? "Energy from PF pulse counter" : "Energy from P x dt";
}

}  // namespace app

// ---------------- start-up and main loop (called from SEM1_Firmware.ino) ----------------
void sem1Setup() {
  leds::begin();
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  Serial.begin(115200);
  delay(50);
  Serial.printf("\nSEM-1 firmware %s (%s)\n", SEM1_FW_VERSION, SEM1_HW_NAME);

  // The IDE's size check (1.9 MB) is looser than our app slot (1.75 MB).
  const esp_partition_t* slot = esp_ota_get_running_partition();
  if (slot && ESP.getSketchSize() > slot->size)
    Serial.println("!!! FIRMWARE TOO BIG FOR ITS FLASH SLOT: OTA updates will break !!!");

  mtx = xSemaphoreCreateMutex();
  settings::begin();
  Serial.printf("Device %s\n", settings::identity().deviceId.c_str());

  // Clock first, so the first history record has the right time.
  Wire.begin(PIN_SDA, PIN_SCL);
  if (rtcChip.begin()) {
    time_t t = rtcChip.read();
    if (t) {
      setSystemTime(t);
      timeSrc = TimeSource::Rtc;
    }
    Serial.printf("[rtc] DS1307 found, %s\n", t ? "time valid" : "time NOT set");
  } else {
    Serial.println("[rtc] DS1307 NOT found");
  }

  logOk = logFlash.begin("datalog") && dataLog.begin(&logFlash);
  Serial.printf("[log] %s, next record #%u\n", logOk ? "ok" : "MISSING PARTITION", dataLog.nextSeq());

  applyCoeffs();
  restoreEnergy();

  HlwSerial.setRxBufferSize(1024);
  HlwSerial.begin(4800, SERIAL_8E1, PIN_HLW_RX, PIN_HLW_TX);
  xTaskCreate(meterTask, "meter", 4096, nullptr, 5, nullptr);

  net::begin();
  net::startProvisioningOrConnect();
  localApi::begin();
  console::begin();
  enableLoopWDT();
}

void sem1Loop() {
  net::loop();
  clockLoop();
  logLoop();
  backupLoop();
  buttonLoop();
  localApi::loop();
  console::loop();
  delay(2);
}
