// Offline data log: a ring buffer of fixed-size records in raw flash.
//
// Why raw flash and not a file system: records are tiny and always appended,
// so a simple ring is faster, wears the flash evenly and survives power cuts
// (every record carries its own CRC; a half-written record is just skipped).
//
// Layout: the partition is split into 4 KB sectors, each holding 204 records
// of 20 bytes. Record number `seq` always lives in slot (seq - 1) % slots, so
// finding a record never needs a search. When the ring wraps, the oldest
// sector is erased before it is reused.
#pragma once
#include <stddef.h>
#include <stdint.h>

namespace sem1 {

// Abstract flash so the ring can be tested on a PC with a RAM "flash".
class FlashIo {
 public:
  virtual ~FlashIo() {}
  virtual uint32_t size() const = 0;
  virtual bool read(uint32_t offset, void* dst, size_t len) = 0;
  virtual bool write(uint32_t offset, const void* src, size_t len) = 0;  // bits 1->0 only
  virtual bool eraseSector(uint32_t offset) = 0;                          // 4 KB, -> 0xFF
};

#pragma pack(push, 1)
struct LogRecord {
  uint32_t seq;        // 1, 2, 3 ... (0xFFFFFFFF = empty slot)
  uint32_t ts;         // interval end, Unix time UTC (s)
  uint32_t energyDWh;  // lifetime energy counter at interval end, 0.1 Wh units
  uint16_t pAvgW;      // average power over the interval, W
  uint16_t pMaxW;      // highest 1 s power in the interval, W
  uint16_t vAvgDV;     // average voltage, 0.1 V units
  uint8_t flags;       // LogFlags
  uint8_t crc;         // CRC-8 of all bytes above
};
#pragma pack(pop)
static_assert(sizeof(LogRecord) == 20, "LogRecord must be 20 bytes");

enum LogFlags : uint8_t {
  kLogChipError = 0x01,  // HLW8032 reported an error during the interval
  kLogNoData = 0x02,     // no packets from the HLW8032 for at least 1 s
  kLogBoot = 0x04,       // device (re)started during this interval
  kLogTimeRtc = 0x08,    // clock came from the RTC only, not yet confirmed by NTP
};

uint8_t crc8(const uint8_t* data, size_t len);

class DataLog {
 public:
  static constexpr uint32_t kSectorSize = 4096;
  static constexpr uint32_t kPerSector = kSectorSize / sizeof(LogRecord);  // 204

  // Scans the flash and finds where to continue. Returns false if the
  // partition is too small (needs at least 2 sectors).
  bool begin(FlashIo* io);

  // Appends a record (seq and crc are filled in). Returns the seq used, 0 on error.
  uint32_t append(LogRecord rec);

  // Next seq that will be written, and the oldest seq that may still exist.
  uint32_t nextSeq() const { return nextSeq_; }
  uint32_t oldestSeq() const;
  uint32_t capacity() const { return slots_; }

  // Reads up to `max` valid records with seq >= fromSeq, oldest first.
  // Returns how many were copied; `*resumeSeq` is where to continue next time.
  size_t readFrom(uint32_t fromSeq, LogRecord* out, size_t max, uint32_t* resumeSeq);

  // Most recent valid record, if any.
  bool latest(LogRecord& out);

  // Erases the whole log.
  bool clear();

 private:
  bool readSlot(uint32_t slot, LogRecord& r);
  static bool valid(const LogRecord& r);
  static bool blank(const LogRecord& r);
  uint32_t slotOffset(uint32_t slot) const;

  FlashIo* io_ = nullptr;
  uint32_t slots_ = 0;
  uint32_t nextSeq_ = 1;
};

}  // namespace sem1
