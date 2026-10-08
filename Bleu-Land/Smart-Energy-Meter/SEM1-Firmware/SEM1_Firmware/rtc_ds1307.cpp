#include "rtc_ds1307.h"

#include <Wire.h>
#include <string.h>

#include "config.h"
#include "datalog.h"  // crc8

namespace {
constexpr uint8_t ADDR = 0x68;
constexpr uint8_t REG_RAM = 0x08;     // RAM marker (same as the test firmware)
constexpr uint8_t MAGIC = 0xA5;
constexpr uint8_t REG_SLOT_A = 0x10;  // 0x10..0x37: two 20-byte backup copies
constexpr uint8_t REG_SLOT_B = 0x24;
constexpr uint8_t SLOT_BYTES = 20;

#pragma pack(push, 1)
struct Slot {
  uint32_t counter;
  uint64_t energyMilliWh;
  uint32_t uploadedSeq;
  uint8_t crc;
};
#pragma pack(pop)
static_assert(sizeof(Slot) <= SLOT_BYTES, "slot must fit its RAM area");

uint8_t bcd2dec(uint8_t b) { return (b >> 4) * 10 + (b & 0x0F); }
uint8_t dec2bcd(uint8_t d) { return ((d / 10) << 4) | (d % 10); }

// Days since 1970-01-01 for a civil date (Howard Hinnant's algorithm).
int64_t daysFromCivil(int y, unsigned m, unsigned d) {
  y -= m <= 2;
  const int era = (y >= 0 ? y : y - 399) / 400;
  const unsigned yoe = (unsigned)(y - era * 400);
  const unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
  const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return (int64_t)era * 146097 + (int64_t)doe - 719468;
}
}  // namespace

bool RtcDs1307::readBytes(uint8_t reg, uint8_t* dst, uint8_t n) {
  Wire.beginTransmission(ADDR);
  Wire.write(reg);
  if (Wire.endTransmission() != 0) return false;
  if (Wire.requestFrom((int)ADDR, (int)n) != n) return false;
  for (uint8_t k = 0; k < n; k++) dst[k] = Wire.read();
  return true;
}

bool RtcDs1307::writeBytes(uint8_t reg, const uint8_t* src, uint8_t n) {
  Wire.beginTransmission(ADDR);
  Wire.write(reg);
  Wire.write(src, n);
  return Wire.endTransmission() == 0;
}

bool RtcDs1307::begin() {
  uint8_t m = 0;
  present_ = readBytes(REG_RAM, &m, 1);
  keptAtBoot_ = present_ && m == MAGIC;
  if (present_ && !keptAtBoot_) {
    // RAM was lost (new chip or flat battery): wipe the backup slots.
    uint8_t zero[SLOT_BYTES] = {};
    writeBytes(REG_SLOT_A, zero, SLOT_BYTES);
    writeBytes(REG_SLOT_B, zero, SLOT_BYTES);
    uint8_t mm = MAGIC;
    writeBytes(REG_RAM, &mm, 1);
  }
  return present_;
}

time_t RtcDs1307::read() {
  uint8_t r[7];
  if (!readBytes(0x00, r, 7)) {
    present_ = false;
    return 0;
  }
  present_ = true;
  halted_ = r[0] & 0x80;  // CH bit: oscillator stopped
  if (halted_) return 0;
  uint8_t sec = bcd2dec(r[0] & 0x7F);
  uint8_t min = bcd2dec(r[1] & 0x7F);
  uint8_t hour;
  if (r[2] & 0x40) {  // 12-hour mode (only if something else set it)
    uint8_t h = bcd2dec(r[2] & 0x1F);
    hour = (h % 12) + ((r[2] & 0x20) ? 12 : 0);
  } else {
    hour = bcd2dec(r[2] & 0x3F);
  }
  uint8_t day = bcd2dec(r[4] & 0x3F);
  uint8_t mon = bcd2dec(r[5] & 0x1F);
  int year = 2000 + bcd2dec(r[6]);
  if (mon < 1 || mon > 12 || day < 1 || day > 31 || hour > 23 || min > 59 || sec > 59) return 0;
  time_t t = (time_t)(daysFromCivil(year, mon, day) * 86400 + hour * 3600 + min * 60 + sec);
  return t >= (time_t)MIN_VALID_UNIX ? t : 0;
}

bool RtcDs1307::write(time_t utc) {
  struct tm tmv;
  gmtime_r(&utc, &tmv);
  uint8_t r[7];
  r[0] = dec2bcd(tmv.tm_sec) & 0x7F;  // CH = 0 starts the oscillator
  r[1] = dec2bcd(tmv.tm_min);
  r[2] = dec2bcd(tmv.tm_hour);  // 24-hour mode
  r[3] = tmv.tm_wday + 1;
  r[4] = dec2bcd(tmv.tm_mday);
  r[5] = dec2bcd(tmv.tm_mon + 1);
  r[6] = dec2bcd(tmv.tm_year % 100);
  bool ok = writeBytes(0x00, r, 7);
  uint8_t ctrl = 0x00;  // square-wave output off
  ok = ok && writeBytes(0x07, &ctrl, 1);
  if (ok) halted_ = false;
  return ok;
}

bool RtcDs1307::loadBackup(EnergyBackup& out) {
  Slot a, b;
  bool okA = readBytes(REG_SLOT_A, (uint8_t*)&a, sizeof(Slot)) &&
             a.crc == sem1::crc8((const uint8_t*)&a, sizeof(Slot) - 1) && a.counter;
  bool okB = readBytes(REG_SLOT_B, (uint8_t*)&b, sizeof(Slot)) &&
             b.crc == sem1::crc8((const uint8_t*)&b, sizeof(Slot) - 1) && b.counter;
  if (!okA && !okB) return false;
  const Slot& s = (okA && (!okB || a.counter > b.counter)) ? a : b;
  out.energyMilliWh = s.energyMilliWh;
  out.uploadedSeq = s.uploadedSeq;
  backupCounter_ = s.counter;
  return true;
}

bool RtcDs1307::saveBackup(const EnergyBackup& b) {
  if (!present_) return false;
  Slot s;
  s.counter = ++backupCounter_;
  s.energyMilliWh = b.energyMilliWh;
  s.uploadedSeq = b.uploadedSeq;
  s.crc = sem1::crc8((const uint8_t*)&s, sizeof(Slot) - 1);
  return writeBytes((s.counter & 1) ? REG_SLOT_A : REG_SLOT_B, (const uint8_t*)&s, sizeof(Slot));
}
