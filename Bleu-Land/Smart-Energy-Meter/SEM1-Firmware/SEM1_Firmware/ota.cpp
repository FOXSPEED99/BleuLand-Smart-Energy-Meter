#include "ota.h"

#include <HTTPClient.h>
#include <Update.h>
#include <WiFiClientSecure.h>
#include <esp_ota_ops.h>

#include "cloud_certs.h"
#include "config.h"

// The Arduino core asks this at boot. true = "don't approve a freshly updated
// image yet, the sketch decides" (see markHealthy / loop). Has no effect on
// firmware flashed over USB, which is never on probation.
extern "C" bool verifyRollbackLater() { return true; }

namespace {
bool probation = false;
bool healthy = false;
constexpr uint32_t PROBATION_MS = 10UL * 60 * 1000;
}  // namespace

namespace ota {

void begin() {
  esp_ota_img_states_t s;
  const esp_partition_t* run = esp_ota_get_running_partition();
  probation = run && esp_ota_get_state_partition(run, &s) == ESP_OK && s == ESP_OTA_IMG_PENDING_VERIFY;
  if (probation) Serial.printf("[ota] new firmware %s on probation: must reach the cloud within 10 min\n", SEM1_FW_VERSION);
}

bool onProbation() { return probation && !healthy; }

void markHealthy() {
  if (!probation || healthy) return;
  healthy = true;
  esp_ota_mark_app_valid_cancel_rollback();
  Serial.printf("[ota] firmware %s confirmed\n", SEM1_FW_VERSION);
}

void loop() {
  if (probation && !healthy && millis() > PROBATION_MS) {
    Serial.println("[ota] new firmware could not reach the cloud: going back to the previous version");
    delay(200);
    esp_ota_mark_app_invalid_rollback_and_reboot();
  }
}

String install(const char* url, size_t size, const char* md5) {
  const esp_partition_t* spare = esp_ota_get_next_update_partition(nullptr);
  if (!spare) return "this meter has no spare firmware slot";
  if (!size || size > spare->size) return "file too big for this meter";

  WiFiClientSecure tls;
  tls.setCACert(CLOUD_ROOT_CAS);
  tls.setTimeout(20);
  HTTPClient http;
  http.setTimeout(20000);
  if (!http.begin(tls, url)) return "bad download address";
  int code = http.GET();
  if (code != 200) {
    http.end();
    return "download failed: HTTP " + String(code);
  }
  int len = http.getSize();
  if (len > 0 && (size_t)len != size) {
    http.end();
    return "download has the wrong size";
  }

  if (!Update.begin(size)) {
    http.end();
    return String("can't prepare the update: ") + Update.errorString();
  }
  Update.setMD5(md5);
  Serial.printf("[ota] downloading %u bytes...\n", (unsigned)size);
  uint32_t t0 = millis();
  size_t written = Update.writeStream(*http.getStreamPtr());
  http.end();
  if (written != size) {
    Update.abort();
    return "download interrupted (" + String((unsigned)(written * 100 / size)) + "%)";
  }
  if (!Update.end()) return String("check failed: ") + Update.errorString();  // MD5 mismatch etc.
  Serial.printf("[ota] written and checked in %u s\n", (unsigned)((millis() - t0) / 1000));
  return "";
}

void printInfo() {
  const esp_partition_t* run = esp_ota_get_running_partition();
  const esp_partition_t* next = esp_ota_get_next_update_partition(nullptr);
  esp_ota_img_states_t s;
  const char* state = "-";
  if (run && esp_ota_get_state_partition(run, &s) == ESP_OK) {
    state = s == ESP_OTA_IMG_VALID            ? "confirmed"
            : s == ESP_OTA_IMG_PENDING_VERIFY ? "on probation"
            : s == ESP_OTA_IMG_NEW            ? "new"
                                              : "other";
  }
  Serial.printf("firmware  %s  running from %s (%s)\n", SEM1_FW_VERSION, run ? run->label : "?",
                probation ? (healthy ? "confirmed after update" : "on probation") : state);
  Serial.printf("spare     %s, %u KB\n", next ? next->label : "?", next ? (unsigned)(next->size / 1024) : 0);
}

}  // namespace ota
