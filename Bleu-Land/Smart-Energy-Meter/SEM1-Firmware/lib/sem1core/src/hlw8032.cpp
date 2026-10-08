#include "hlw8032.h"

#include <string.h>

namespace sem1 {

static uint32_t r24(const uint8_t* b) {
  return ((uint32_t)b[0] << 16) | ((uint32_t)b[1] << 8) | b[2];
}

bool Hlw8032::headerOk(const uint8_t* f) {
  if (f[1] != 0x5A) return false;
  return f[0] == 0x55 || f[0] == 0xAA || (f[0] & 0xF0) == 0xF0;
}

bool Hlw8032::checksumOk(const uint8_t* f) {
  uint8_t sum = 0;
  for (size_t k = 2; k <= 22; k++) sum += f[k];
  return sum == f[23];
}

void Hlw8032::decode(const uint8_t* f, HlwSample& out) {
  out = HlwSample();
  out.state = f[0];
  if (f[0] == 0xAA) {  // chip error: calibration registers unusable
    out.chipError = true;
    return;
  }

  uint32_t vPar = r24(f + 2), vReg = r24(f + 5);
  uint32_t iPar = r24(f + 8), iReg = r24(f + 11);
  uint32_t pPar = r24(f + 14), pReg = r24(f + 17);

  // 0xFx = a period register overflowed (signal too small, e.g. no load)
  if ((f[0] & 0xF0) == 0xF0) {
    out.vOvf = f[0] & 0x08;
    out.iOvf = f[0] & 0x04;
    out.pOvf = f[0] & 0x02;
  }

  const HlwCoeffs& c = coeffs_;
  out.v = (!out.vOvf && vReg) ? (float)vPar / vReg * c.kv * c.calV : 0;
  out.i = (!out.iOvf && iReg) ? (float)iPar / iReg * c.ki * c.calI : 0;
  out.p = (!out.pOvf && pReg) ? (float)pPar / pReg * c.kv * c.ki * c.calP : 0;

  // No-load cutoff: with no real power the small current reading is only the
  // input noise floor (~0.2 A on the prototype).
  if (out.pOvf) out.i = 0;

  // PF pulse counter. A 16-bit difference handles the wrap-around; at ~18
  // packets/s it can never wrap twice between two packets.
  uint16_t pf = ((uint16_t)f[21] << 8) | f[22];
  if (havePf_) out.pfPulses = (uint16_t)(pf - lastPf_);
  lastPf_ = pf;
  havePf_ = true;

  // Energy per PF pulse. Commonly used formula (to verify against a reference
  // meter): pulses per kWh = 1e9 * 3600 / (PowPar * KV * KI).
  if (pPar) out.whPerPulse = (double)pPar * c.kv * c.ki * c.calP / 3.6e9;
}

bool Hlw8032::feed(uint8_t byte, HlwSample& out) {
  // Sliding 24-byte window: packets arrive with no gap between them, so we
  // look for a valid header + checksum at every byte position.
  if (fill_ < kPacketLen) {
    win_[fill_++] = byte;
  } else {
    memmove(win_, win_ + 1, kPacketLen - 1);
    win_[kPacketLen - 1] = byte;
  }
  if (fill_ < kPacketLen || !headerOk(win_)) return false;
  if (!checksumOk(win_)) {
    bad_++;
    return false;
  }
  memcpy(last_, win_, kPacketLen);
  good_++;
  fill_ = 0;
  decode(last_, out);
  return true;
}

}  // namespace sem1
