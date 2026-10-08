// DS1307 real-time clock (I2C 0x68) with CR2032 backup.
//
// Two jobs:
//  1. Keep UTC time through power cuts, so history records get the right
//     timestamp even when the internet (NTP) is down.
//  2. Hold the energy total in the chip's 56-byte battery-backed RAM. Unlike
//     flash, this RAM can be rewritten every few seconds forever, so at most a
//     few seconds of energy are lost on a power cut.
#pragma once
#include <stdint.h>
#include <time.h>

struct EnergyBackup {
  uint64_t energyMilliWh = 0;  // lifetime energy counter
  uint32_t uploadedSeq = 0;    // last data-log record confirmed by the cloud
};

class RtcDs1307 {
 public:
  bool begin();  // Wire must already be started
  bool present() const { return present_; }

  // Unix time (UTC) from the chip; 0 if missing, stopped or not set.
  time_t read();
  bool write(time_t utc);

  // A/B copies with a counter and CRC: a power cut mid-write leaves the
  // other copy intact.
  bool loadBackup(EnergyBackup& out);
  bool saveBackup(const EnergyBackup& b);

  // Diagnostics for the factory test page.
  bool halted() const { return halted_; }
  bool keptAtBoot() const { return keptAtBoot_; }  // RAM marker survived power-off

 private:
  bool readBytes(uint8_t reg, uint8_t* dst, uint8_t n);
  bool writeBytes(uint8_t reg, const uint8_t* src, uint8_t n);
  bool present_ = false;
  bool halted_ = true;
  bool keptAtBoot_ = false;
  uint32_t backupCounter_ = 0;
};
