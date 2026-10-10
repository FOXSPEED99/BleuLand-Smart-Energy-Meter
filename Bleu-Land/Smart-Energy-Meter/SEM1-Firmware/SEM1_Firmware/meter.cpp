#include "meter.h"

namespace sem1 {

void Meter::add(const HlwSample& s) {
  if (s.chipError) {
    flags_ |= kFlagChipError;
    return;
  }
  sumV_ += s.v;
  sumI_ += s.i;
  sumP_ += s.p;
  n_++;
  pulseWhAcc_ += s.pfPulses * s.whPerPulse;
}

bool Meter::tick(uint32_t nowMs, Reading& out) {
  if (!started_) {
    started_ = true;
    lastMs_ = nowMs;
    return false;
  }
  uint32_t elapsed = nowMs - lastMs_;
  if (elapsed < 1000) return false;
  lastMs_ = nowMs;
  // A long gap (e.g. the loop was blocked) must not be counted as a long
  // period at the current power: cap it.
  if (elapsed > 5000) elapsed = 5000;

  Reading r;
  r.samples = n_ > 0xFFFF ? 0xFFFF : (uint16_t)n_;
  if (n_ > 0) {
    r.v = (float)(sumV_ / n_);
    r.i = (float)(sumI_ / n_);
    r.p = (float)(sumP_ / n_);
  } else {
    flags_ |= kFlagNoData;
  }
  if (noLoadW_ > 0) {
    loadOn_ = r.p >= (loadOn_ ? noLoadW_ * 0.8f : noLoadW_);
    if (!loadOn_) {
      r.i = 0;
      r.p = 0;
      pulseWhAcc_ = 0;
    }
  }
  r.s = r.v * r.i;
  r.pf = (r.s > 1.0f) ? r.p / r.s : 0;
  if (r.pf > 1.0f) r.pf = 1.0f;

  double integratedWh = (double)r.p * elapsed / 3600000.0;
  double pulseWh = pulseWhAcc_;
  double dWh = (source_ == EnergySource::PfPulses) ? pulseWh : integratedWh;
  altWh_ += (source_ == EnergySource::PfPulses) ? integratedWh : pulseWh;
  if (dWh < 0) dWh = 0;
  totalWh_ += dWh;

  ledAcc_ += dWh;
  while (ledAcc_ >= 1.0) {
    ledAcc_ -= 1.0;
    ledPulses_++;
  }

  sumV_ = sumI_ = sumP_ = 0;
  n_ = 0;
  pulseWhAcc_ = 0;
  last_ = r;
  out = r;
  return true;
}

uint32_t Meter::takeWhPulses() {
  uint32_t n = ledPulses_;
  ledPulses_ = 0;
  return n;
}

}  // namespace sem1
