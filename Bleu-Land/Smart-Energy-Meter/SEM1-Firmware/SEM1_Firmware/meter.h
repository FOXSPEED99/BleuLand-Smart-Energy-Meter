// Turns the HLW8032's ~18 packets/s into 1-second readings and a running
// energy total. Plain C++ so it can be unit-tested on a PC.
#pragma once
#include <stdint.h>

#include "hlw8032.h"

namespace sem1 {

// One averaged reading (1 second).
struct Reading {
  float v = 0, i = 0, p = 0;  // V, A, W
  float s = 0;                // apparent power, VA
  float pf = 0;               // power factor 0..1
  uint16_t samples = 0;       // packets that went into this average (0 = no data)
};

// Where the energy total comes from.
enum class EnergySource : uint8_t {
  Integrated = 0,  // sum of P * dt (proven on the prototype)
  PfPulses = 1,    // HLW8032 PF pulse counter (verify against a reference meter first)
};

// Problems seen since the last call to takeFlags().
enum MeterFlags : uint8_t {
  kFlagChipError = 0x01,  // HLW8032 reported 0xAA
  kFlagNoData = 0x02,     // a whole second passed without a valid packet
};

class Meter {
 public:
  void setEnergySource(EnergySource s) { source_ = s; }

  // No-load cutoff ("anti-creep"): a 1-second power below this many watts is
  // noise on the current input, not a real load, so it reads as 0 W / 0 A and
  // adds no energy. Once a load is seen it stays on until the power falls
  // below 80 % of the limit, so a load near the limit doesn't flicker.
  // 0 = off.
  void setNoLoadW(float w) { noLoadW_ = w; }
  EnergySource energySource() const { return source_; }

  // Feed every valid packet.
  void add(const HlwSample& s);

  // Call often. Once per second it fills `out`, updates the energy total and
  // returns true.
  bool tick(uint32_t nowMs, Reading& out);

  const Reading& last() const { return last_; }

  // Lifetime energy total in Wh (restored from storage at boot).
  double totalWh() const { return totalWh_; }
  void setTotalWh(double wh) { totalWh_ = wh; }

  // The other energy method, since boot only. Lets you compare both methods
  // against a reference meter without reflashing.
  double altWhSinceBoot() const { return altWh_; }

  // Number of 1 Wh steps reached since the last call (drives the
  // "ENERGY 1000 imp/kWh" LED on the front label).
  uint32_t takeWhPulses();

  uint8_t takeFlags() {
    uint8_t f = flags_;
    flags_ = 0;
    return f;
  }

 private:
  EnergySource source_ = EnergySource::Integrated;
  float noLoadW_ = 0;
  bool loadOn_ = false;
  double sumV_ = 0, sumI_ = 0, sumP_ = 0;
  uint32_t n_ = 0;
  double pulseWhAcc_ = 0;  // PF-pulse energy since the last tick
  uint32_t lastMs_ = 0;
  bool started_ = false;
  Reading last_;
  double totalWh_ = 0;
  double altWh_ = 0;
  double ledAcc_ = 0;
  uint32_t ledPulses_ = 0;
  uint8_t flags_ = 0;
};

// Collects 1 s readings over one log interval (e.g. 5 minutes).
struct IntervalStats {
  double sumV = 0;
  uint32_t nV = 0;
  float pMax = 0;
  uint8_t flags = 0;

  void add(const Reading& r) {
    if (r.samples && r.v > 0) {
      sumV += r.v;
      nV++;
    }
    if (r.p > pMax) pMax = r.p;
  }
  float vAvg() const { return nV ? (float)(sumV / nV) : 0; }
  void reset() { *this = IntervalStats(); }
};

}  // namespace sem1
