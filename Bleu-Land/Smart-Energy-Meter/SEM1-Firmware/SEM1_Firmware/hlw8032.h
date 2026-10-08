// HLW8032 packet decoder.
//
// Plain C++ (no Arduino calls) so it can be unit-tested on a PC.
// Feed it every byte that arrives on the UART; it finds packets on its own.
//
// Packet (24 bytes, streamed back-to-back at 4800 8E1):
//   [0]      state: 0x55 OK, 0xAA chip error, 0xFx overflow (bit3 V, bit2 I, bit1 P)
//   [1]      check byte, always 0x5A
//   [2..4]   voltage parameter   [5..7]   voltage register
//   [8..10]  current parameter   [11..13] current register
//   [14..16] power parameter     [17..19] power register
//   [20]     data-update flags (bit7 = PF counter carry)
//   [21..22] PF pulse counter
//   [23]     checksum = low byte of sum(bytes 2..22)
#pragma once
#include <stddef.h>
#include <stdint.h>

namespace sem1 {

struct HlwCoeffs {
  float kv = 1.88f;    // voltage front-end coefficient
  float ki = 4.0f;     // current front-end coefficient (0.001 / (R_burden / CT_turns))
  float calV = 1.0f;   // per-unit calibration factors (factory calibration)
  float calI = 1.0f;
  float calP = 1.0f;
};

// Result of one valid packet.
struct HlwSample {
  uint8_t state = 0;        // raw state byte
  bool chipError = false;   // state 0xAA: values are unusable
  bool vOvf = false, iOvf = false, pOvf = false;
  float v = 0, i = 0, p = 0;  // volts, amps, watts (already calibrated)
  // Energy from the chip's own PF pulse counter since the previous packet.
  // 0 for the very first packet (no previous count to compare against).
  uint16_t pfPulses = 0;
  double whPerPulse = 0;    // energy of one PF pulse, Wh (0 if unknown)
};

class Hlw8032 {
 public:
  static constexpr size_t kPacketLen = 24;

  void setCoeffs(const HlwCoeffs& c) { coeffs_ = c; }
  const HlwCoeffs& coeffs() const { return coeffs_; }

  // Push one received byte. Returns true when it completed a valid packet,
  // in which case `out` holds the decoded values.
  bool feed(uint8_t byte, HlwSample& out);

  uint32_t goodPackets() const { return good_; }
  uint32_t badPackets() const { return bad_; }
  const uint8_t* lastPacket() const { return last_; }
  bool hasPacket() const { return good_ > 0; }

  // Exposed for tests.
  static bool headerOk(const uint8_t* f);
  static bool checksumOk(const uint8_t* f);
  void decode(const uint8_t* f, HlwSample& out);

 private:
  HlwCoeffs coeffs_;
  uint8_t win_[kPacketLen] = {};
  size_t fill_ = 0;
  uint8_t last_[kPacketLen] = {};
  uint32_t good_ = 0, bad_ = 0;
  bool havePf_ = false;
  uint16_t lastPf_ = 0;
};

}  // namespace sem1
