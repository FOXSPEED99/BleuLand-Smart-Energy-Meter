// FlashIo backed by an ESP32 flash partition (see partitions_sem1.csv).
#pragma once
#include <esp_partition.h>

#include "datalog.h"

class PartitionFlash : public sem1::FlashIo {
 public:
  // Finds the data partition with this label. Returns false if missing.
  bool begin(const char* label) {
    part_ = esp_partition_find_first(ESP_PARTITION_TYPE_DATA, ESP_PARTITION_SUBTYPE_ANY, label);
    return part_ != nullptr;
  }
  uint32_t size() const override { return part_ ? part_->size : 0; }
  bool read(uint32_t offset, void* dst, size_t len) override {
    return esp_partition_read(part_, offset, dst, len) == ESP_OK;
  }
  bool write(uint32_t offset, const void* src, size_t len) override {
    return esp_partition_write(part_, offset, src, len) == ESP_OK;
  }
  bool eraseSector(uint32_t offset) override {
    return esp_partition_erase_range(part_, offset, sem1::DataLog::kSectorSize) == ESP_OK;
  }

 private:
  const esp_partition_t* part_ = nullptr;
};
