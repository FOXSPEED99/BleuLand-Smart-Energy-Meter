// PC unit tests for the metering core. Run with:  sh test/run_tests.sh
#include <string.h>
#include <unity.h>

#include <vector>

#include "datalog.h"
#include "hlw8032.h"
#include "meter.h"

using namespace sem1;

void setUp() {}
void tearDown() {}

// ---------- helpers ----------
static void put24(uint8_t* b, uint32_t v) {
  b[0] = v >> 16;
  b[1] = v >> 8;
  b[2] = v;
}

static std::vector<uint8_t> makePacket(uint8_t state, uint32_t vPar, uint32_t vReg, uint32_t iPar,
                                       uint32_t iReg, uint32_t pPar, uint32_t pReg, uint16_t pf = 0) {
  std::vector<uint8_t> f(24, 0);
  f[0] = state;
  f[1] = 0x5A;
  put24(&f[2], vPar);
  put24(&f[5], vReg);
  put24(&f[8], iPar);
  put24(&f[11], iReg);
  put24(&f[14], pPar);
  put24(&f[17], pReg);
  f[20] = 0x70;
  f[21] = pf >> 8;
  f[22] = pf & 0xFF;
  uint8_t sum = 0;
  for (int k = 2; k <= 22; k++) sum += f[k];
  f[23] = sum;
  return f;
}

// 230 V, ~4.35 A, ~1000 W with KV 1.88 / KI 4.0
static std::vector<uint8_t> normalPacket(uint16_t pf = 0) {
  return makePacket(0x55, 2000000, 16348, 100000, 92000, 5000000, 37600, pf);
}

static int feedAll(Hlw8032& h, const std::vector<uint8_t>& bytes, HlwSample& last) {
  int n = 0;
  HlwSample s;
  for (uint8_t b : bytes)
    if (h.feed(b, s)) {
      last = s;
      n++;
    }
  return n;
}

// ---------- HLW8032 ----------
void test_decodes_normal_packet() {
  Hlw8032 h;
  HlwSample s;
  TEST_ASSERT_EQUAL(1, feedAll(h, normalPacket(), s));
  TEST_ASSERT_FLOAT_WITHIN(0.1f, 230.0f, s.v);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 100000.0f / 92000 * 4.0f, s.i);
  TEST_ASSERT_FLOAT_WITHIN(0.5f, 5000000.0f / 37600 * 1.88f * 4.0f, s.p);
  TEST_ASSERT_FALSE(s.chipError);
}

void test_syncs_on_back_to_back_stream_with_garbage() {
  Hlw8032 h;
  std::vector<uint8_t> stream = {0x12, 0x5A, 0x55, 0x00, 0xFF};  // junk first
  for (int k = 0; k < 10; k++) {
    auto p = normalPacket(k);
    stream.insert(stream.end(), p.begin(), p.end());
  }
  HlwSample s;
  TEST_ASSERT_EQUAL(10, feedAll(h, stream, s));
  TEST_ASSERT_EQUAL_UINT32(10, h.goodPackets());
}

void test_rejects_bad_checksum() {
  Hlw8032 h;
  auto p = normalPacket();
  p[23] ^= 0x01;
  HlwSample s;
  TEST_ASSERT_EQUAL(0, feedAll(h, p, s));
  TEST_ASSERT_TRUE(h.badPackets() >= 1);
}

void test_power_overflow_zeroes_current_and_power() {
  Hlw8032 h;
  HlwSample s;
  auto p = makePacket(0xF2, 2000000, 16348, 100000, 400000, 5000000, 0xFFFFFF);
  TEST_ASSERT_EQUAL(1, feedAll(h, p, s));
  TEST_ASSERT_TRUE(s.pOvf);
  TEST_ASSERT_EQUAL_FLOAT(0.0f, s.p);
  TEST_ASSERT_EQUAL_FLOAT(0.0f, s.i);  // noise-floor cutoff
  TEST_ASSERT_FLOAT_WITHIN(0.1f, 230.0f, s.v);
}

void test_chip_error_flagged() {
  Hlw8032 h;
  HlwSample s;
  TEST_ASSERT_EQUAL(1, feedAll(h, makePacket(0xAA, 1, 1, 1, 1, 1, 1), s));
  TEST_ASSERT_TRUE(s.chipError);
}

void test_pf_pulses_wrap_around() {
  Hlw8032 h;
  HlwSample s;
  feedAll(h, normalPacket(65530), s);
  TEST_ASSERT_EQUAL_UINT16(0, s.pfPulses);  // first packet: no reference yet
  feedAll(h, normalPacket(4), s);
  TEST_ASSERT_EQUAL_UINT16(10, s.pfPulses);
  TEST_ASSERT_TRUE(s.whPerPulse > 0);
}

void test_calibration_scales_values() {
  Hlw8032 h;
  HlwCoeffs c;
  c.calV = 1.01f;
  h.setCoeffs(c);
  HlwSample s;
  feedAll(h, normalPacket(), s);
  TEST_ASSERT_FLOAT_WITHIN(0.1f, 232.3f, s.v);
}

// ---------- Meter ----------
void test_meter_averages_and_integrates() {
  Meter m;
  Reading r;
  m.tick(0, r);  // start
  HlwSample s;
  s.v = 230;
  s.i = 4.35f;
  s.p = 1000;
  for (int k = 0; k < 18; k++) m.add(s);
  TEST_ASSERT_FALSE(m.tick(999, r));
  TEST_ASSERT_TRUE(m.tick(1000, r));
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 1000.0f, r.p);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 1000.0f / (230 * 4.35f), r.pf);
  // 1000 W for 1 s = 0.2778 Wh
  TEST_ASSERT_FLOAT_WITHIN(1e-6, 1000.0 / 3600.0, m.totalWh());
}

void test_meter_1000_imp_per_kwh_led() {
  Meter m;
  Reading r;
  m.tick(0, r);
  HlwSample s;
  s.v = 230;
  s.p = 3600;  // 1 Wh per second
  uint32_t pulses = 0;
  for (uint32_t t = 1; t <= 10; t++) {
    m.add(s);
    m.tick(t * 1000, r);
    pulses += m.takeWhPulses();
  }
  TEST_ASSERT_UINT32_WITHIN(1, 10, pulses);
}

void test_meter_no_load_cutoff() {
  Meter m;
  m.setNoLoadW(25);
  Reading r;
  m.tick(0, r);
  HlwSample s;
  s.v = 230;
  uint32_t t = 0;
  auto second = [&](float w, float a) {
    s.p = w;
    s.i = a;
    m.add(s);
    t += 1000;
    m.tick(t, r);
  };
  // noise: 20 W at 0.14 A reads as nothing and adds no energy
  second(20, 0.14f);
  TEST_ASSERT_EQUAL_FLOAT(0, r.p);
  TEST_ASSERT_EQUAL_FLOAT(0, r.i);
  TEST_ASSERT_EQUAL_FLOAT(0, r.pf);
  TEST_ASSERT_EQUAL_FLOAT(0, (float)m.totalWh());
  // a real 100 W load is measured and counted
  second(100, 0.5f);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 100, r.p);
  TEST_ASSERT_FLOAT_WITHIN(1e-6, 100.0 / 3600.0, m.totalWh());
  // once on, it stays on down to 80 % of the limit (no flicker at the edge)
  second(21, 0.1f);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 21, r.p);
  second(19, 0.1f);
  TEST_ASSERT_EQUAL_FLOAT(0, r.p);
  // and needs the full limit again to come back
  second(24, 0.1f);
  TEST_ASSERT_EQUAL_FLOAT(0, r.p);
  second(25, 0.12f);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 25, r.p);
}

void test_meter_no_data_flag() {
  Meter m;
  Reading r;
  m.tick(0, r);
  TEST_ASSERT_TRUE(m.tick(1000, r));
  TEST_ASSERT_EQUAL(0, r.samples);
  TEST_ASSERT_EQUAL_UINT8(kFlagNoData, m.takeFlags());
  TEST_ASSERT_EQUAL_UINT8(0, m.takeFlags());
}

void test_meter_caps_long_gap() {
  Meter m;
  Reading r;
  m.tick(0, r);
  HlwSample s;
  s.p = 3600;
  m.add(s);
  m.tick(60000, r);  // loop blocked for a minute: count at most 5 s
  TEST_ASSERT_FLOAT_WITHIN(1e-6, 5.0, m.totalWh());
}

// ---------- DataLog ----------
class RamFlash : public FlashIo {
 public:
  explicit RamFlash(uint32_t size) : mem(size, 0xFF) {}
  uint32_t size() const override { return mem.size(); }
  bool read(uint32_t o, void* d, size_t n) override {
    memcpy(d, &mem[o], n);
    return true;
  }
  bool write(uint32_t o, const void* s, size_t n) override {
    // NOR flash: a write can only clear bits
    for (size_t k = 0; k < n; k++) mem[o + k] &= ((const uint8_t*)s)[k];
    return true;
  }
  bool eraseSector(uint32_t o) override {
    memset(&mem[o], 0xFF, DataLog::kSectorSize);
    erases++;
    return true;
  }
  std::vector<uint8_t> mem;
  int erases = 0;
};

static LogRecord rec(uint32_t ts) {
  LogRecord r = {};
  r.ts = ts;
  r.energyDWh = ts;
  return r;
}

void test_log_append_and_read_back() {
  RamFlash f(4 * 4096);
  DataLog log;
  TEST_ASSERT_TRUE(log.begin(&f));
  for (uint32_t k = 1; k <= 300; k++) TEST_ASSERT_EQUAL_UINT32(k, log.append(rec(1000 + k)));
  LogRecord out[50];
  uint32_t resume = 0;
  size_t n = log.readFrom(100, out, 50, &resume);
  TEST_ASSERT_EQUAL(50, n);
  TEST_ASSERT_EQUAL_UINT32(100, out[0].seq);
  TEST_ASSERT_EQUAL_UINT32(1100, out[0].ts);
  TEST_ASSERT_EQUAL_UINT32(150, resume);
}

void test_log_survives_reboot() {
  RamFlash f(4 * 4096);
  {
    DataLog log;
    log.begin(&f);
    for (uint32_t k = 1; k <= 250; k++) log.append(rec(k));
  }
  DataLog log2;
  log2.begin(&f);
  TEST_ASSERT_EQUAL_UINT32(251, log2.nextSeq());
  LogRecord last;
  TEST_ASSERT_TRUE(log2.latest(last));
  TEST_ASSERT_EQUAL_UINT32(250, last.ts);
}

void test_log_wraps_and_drops_oldest() {
  RamFlash f(3 * 4096);  // 612 slots
  DataLog log;
  log.begin(&f);
  for (uint32_t k = 1; k <= 1000; k++) TEST_ASSERT_NOT_EQUAL(0, log.append(rec(k)));
  LogRecord out[700];
  uint32_t resume;
  size_t n = log.readFrom(1, out, 700, &resume);
  TEST_ASSERT_TRUE(n >= 2 * DataLog::kPerSector);  // at least two full sectors kept
  TEST_ASSERT_EQUAL_UINT32(1000, out[n - 1].seq);
  for (size_t k = 1; k < n; k++) TEST_ASSERT_EQUAL_UINT32(out[k - 1].seq + 1, out[k].seq);
  DataLog again;
  again.begin(&f);
  TEST_ASSERT_EQUAL_UINT32(1001, again.nextSeq());
}

void test_log_skips_torn_record() {
  RamFlash f(4 * 4096);
  DataLog log;
  log.begin(&f);
  for (uint32_t k = 1; k <= 10; k++) log.append(rec(k));
  // Simulate a power cut halfway through writing record 11.
  f.mem[10 * sizeof(LogRecord) + 2] = 0x00;
  DataLog log2;
  log2.begin(&f);
  uint32_t seq = log2.append(rec(99));
  TEST_ASSERT_EQUAL_UINT32(12, seq);  // slot 11 is skipped, not overwritten
  LogRecord out[20];
  uint32_t resume;
  size_t n = log2.readFrom(1, out, 20, &resume);
  TEST_ASSERT_EQUAL(11, n);
  TEST_ASSERT_EQUAL_UINT32(99, out[10].ts);
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_decodes_normal_packet);
  RUN_TEST(test_syncs_on_back_to_back_stream_with_garbage);
  RUN_TEST(test_rejects_bad_checksum);
  RUN_TEST(test_power_overflow_zeroes_current_and_power);
  RUN_TEST(test_chip_error_flagged);
  RUN_TEST(test_pf_pulses_wrap_around);
  RUN_TEST(test_calibration_scales_values);
  RUN_TEST(test_meter_averages_and_integrates);
  RUN_TEST(test_meter_1000_imp_per_kwh_led);
  RUN_TEST(test_meter_no_load_cutoff);
  RUN_TEST(test_meter_no_data_flag);
  RUN_TEST(test_meter_caps_long_gap);
  RUN_TEST(test_log_append_and_read_back);
  RUN_TEST(test_log_survives_reboot);
  RUN_TEST(test_log_wraps_and_drops_oldest);
  RUN_TEST(test_log_skips_torn_record);
  return UNITY_END();
}
