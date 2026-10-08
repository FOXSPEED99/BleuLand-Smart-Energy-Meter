#include "datalog.h"

#include <string.h>

namespace sem1 {

uint8_t crc8(const uint8_t* data, size_t len) {
  uint8_t crc = 0;
  for (size_t k = 0; k < len; k++) {
    crc ^= data[k];
    for (int b = 0; b < 8; b++) crc = (crc & 0x80) ? (uint8_t)((crc << 1) ^ 0x07) : (uint8_t)(crc << 1);
  }
  return crc;
}

static uint8_t recordCrc(const LogRecord& r) {
  return crc8(reinterpret_cast<const uint8_t*>(&r), sizeof(LogRecord) - 1);
}

bool DataLog::valid(const LogRecord& r) {
  return r.seq != 0 && r.seq != 0xFFFFFFFF && r.crc == recordCrc(r);
}

bool DataLog::blank(const LogRecord& r) {
  const uint8_t* p = reinterpret_cast<const uint8_t*>(&r);
  for (size_t k = 0; k < sizeof(LogRecord); k++)
    if (p[k] != 0xFF) return false;
  return true;
}

uint32_t DataLog::slotOffset(uint32_t slot) const {
  return (slot / kPerSector) * kSectorSize + (slot % kPerSector) * sizeof(LogRecord);
}

bool DataLog::readSlot(uint32_t slot, LogRecord& r) {
  return io_->read(slotOffset(slot), &r, sizeof(r));
}

bool DataLog::begin(FlashIo* io) {
  io_ = io;
  uint32_t sectors = io->size() / kSectorSize;
  if (sectors < 2) return false;
  slots_ = sectors * kPerSector;

  // Find the newest record that sits in the slot its seq belongs to.
  uint32_t maxSeq = 0;
  LogRecord r;
  for (uint32_t s = 0; s < slots_; s++) {
    if (!readSlot(s, r) || !valid(r)) continue;
    if ((r.seq - 1) % slots_ != s) continue;
    if (r.seq > maxSeq) maxSeq = r.seq;
  }
  nextSeq_ = maxSeq + 1;
  return true;
}

uint32_t DataLog::append(LogRecord rec) {
  if (!io_ || !slots_) return 0;
  // Normally one pass. More only if a slot is damaged (e.g. a power cut in
  // the middle of a write): that slot is skipped.
  for (uint32_t tries = 0; tries < kPerSector + 1; tries++) {
    uint32_t slot = (nextSeq_ - 1) % slots_;
    if (slot % kPerSector == 0) {
      // Starting a new sector: wipe it (this drops the oldest records once
      // the ring has wrapped).
      if (!io_->eraseSector(slotOffset(slot))) return 0;
    } else {
      LogRecord cur;
      if (!readSlot(slot, cur)) return 0;
      if (!blank(cur)) {
        nextSeq_++;
        continue;
      }
    }
    rec.seq = nextSeq_;
    rec.crc = recordCrc(rec);
    if (!io_->write(slotOffset(slot), &rec, sizeof(rec))) {
      nextSeq_++;  // slot is now unknown: never write it twice
      continue;
    }
    LogRecord check;
    nextSeq_++;
    if (readSlot(slot, check) && memcmp(&check, &rec, sizeof(rec)) == 0) return rec.seq;
  }
  return 0;
}

uint32_t DataLog::oldestSeq() const {
  // Lower bound: anything older has certainly been overwritten.
  return nextSeq_ > slots_ ? nextSeq_ - slots_ : 1;
}

size_t DataLog::readFrom(uint32_t fromSeq, LogRecord* out, size_t max, uint32_t* resumeSeq) {
  uint32_t s = fromSeq < oldestSeq() ? oldestSeq() : fromSeq;
  size_t n = 0;
  LogRecord r;
  while (s < nextSeq_ && n < max) {
    if (readSlot((s - 1) % slots_, r) && valid(r) && r.seq == s) out[n++] = r;
    s++;
  }
  if (resumeSeq) *resumeSeq = s;
  return n;
}

bool DataLog::latest(LogRecord& out) {
  uint32_t lo = oldestSeq();
  for (uint32_t s = nextSeq_ - 1; s >= lo && s > 0 && nextSeq_ - s <= 2 * kPerSector; s--) {
    if (readSlot((s - 1) % slots_, out) && valid(out) && out.seq == s) return true;
  }
  return false;
}

bool DataLog::clear() {
  if (!io_) return false;
  for (uint32_t off = 0; off + kSectorSize <= io_->size(); off += kSectorSize)
    if (!io_->eraseSector(off)) return false;
  nextSeq_ = 1;
  return true;
}

}  // namespace sem1
