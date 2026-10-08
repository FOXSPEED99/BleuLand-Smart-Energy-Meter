// Shared state between the metering task, the main loop and the local API.
#pragma once
#include <Arduino.h>
#include <time.h>

#include "datalog.h"
#include "meter.h"
#include "rtc_ds1307.h"

struct LiveSnapshot {
  sem1::Reading reading;
  double totalWh = 0;      // lifetime energy counter
  double altWhBoot = 0;    // other energy method, since boot (for verification)
  uint32_t goodPackets = 0, badPackets = 0;
  uint32_t packetAgeMs = 0;  // since the last valid HLW8032 packet (0 = never)
  uint8_t raw[24] = {};
  bool haveRaw = false;
};

enum class TimeSource : uint8_t { None, Rtc, Ntp };

namespace app {
LiveSnapshot snapshot();

time_t now();  // Unix time UTC, 0 if unknown
TimeSource timeSource();
const char* timeSourceName();

RtcDs1307& rtc();
sem1::DataLog& log();
uint32_t uploadedSeq();

// Calibration against a reference meter. `what` is 'v', 'i' or 'p'; `target`
// is what the reference shows right now. Returns a message for the user.
String calibrate(char what, float target);
String resetCalibration();
String setEnergySource(sem1::EnergySource s);
}  // namespace app
