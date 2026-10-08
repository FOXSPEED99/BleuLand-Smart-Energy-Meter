#include "settings.h"

#include <Preferences.h>
#include <bootloader_random.h>
#include <esp_mac.h>
#include <esp_random.h>

namespace {
Preferences prefs;
Identity ident;
Settings cfg;
constexpr const char* NS = "sem1";

String randomString(size_t len, const char* alphabet) {
  size_t n = strlen(alphabet);
  String s;
  s.reserve(len);
  for (size_t k = 0; k < len; k++) s += alphabet[esp_random() % n];
  return s;
}
}  // namespace

namespace settings {

void begin() {
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char suffix[7];
  snprintf(suffix, sizeof(suffix), "%02X%02X%02X", mac[3], mac[4], mac[5]);
  ident.deviceId = String("SEM1-") + suffix;
  ident.bleName = String("SEM1_") + suffix;

  prefs.begin(NS, false);
  // The radio is not on yet, so switch on the hardware entropy source to get
  // real random numbers for the codes below.
  bootloader_random_enable();
  // Generated once, on the very first boot (end of the production line).
  // No 0/o/1/l/i: easy to read off a label.
  ident.pop = prefs.getString("pop", "");
  if (ident.pop.length() != 8) {
    ident.pop = randomString(8, "abcdefghjkmnpqrstuvwxyz23456789");
    prefs.putString("pop", ident.pop);
  }
  ident.secret = prefs.getString("secret", "");
  if (ident.secret.length() != 32) {
    ident.secret = randomString(32, "0123456789abcdef");
    prefs.putString("secret", ident.secret);
  }
  bootloader_random_disable();

  cfg.calV = prefs.getFloat("calV", 1.0f);
  cfg.calI = prefs.getFloat("calI", 1.0f);
  cfg.calP = prefs.getFloat("calP", 1.0f);
  cfg.energySource = (sem1::EnergySource)prefs.getUChar("esrc", 0);
  cfg.claimCode = prefs.getString("claim", "");
  prefs.end();
}

const Identity& identity() { return ident; }
Settings& get() { return cfg; }

void saveCalibration() {
  prefs.begin(NS, false);
  prefs.putFloat("calV", cfg.calV);
  prefs.putFloat("calI", cfg.calI);
  prefs.putFloat("calP", cfg.calP);
  prefs.end();
}

void saveEnergySource() {
  prefs.begin(NS, false);
  prefs.putUChar("esrc", (uint8_t)cfg.energySource);
  prefs.end();
}

void saveClaimCode(const String& code) {
  cfg.claimCode = code;
  prefs.begin(NS, false);
  prefs.putString("claim", code);
  prefs.end();
}

bool wifiFromSetup() {
  prefs.begin(NS, true);
  bool v = prefs.getBool("wifiok", false);
  prefs.end();
  return v;
}

void setWifiFromSetup(bool v) {
  prefs.begin(NS, false);
  prefs.putBool("wifiok", v);
  prefs.end();
}

uint64_t loadEnergyMilliWh() {
  prefs.begin(NS, true);
  uint64_t v = prefs.getULong64("emwh", 0);
  prefs.end();
  return v;
}

void saveEnergyMilliWh(uint64_t mwh) {
  prefs.begin(NS, false);
  prefs.putULong64("emwh", mwh);
  prefs.end();
}

String qrPayload() {
  return String("{\"ver\":\"v1\",\"name\":\"") + ident.bleName + "\",\"pop\":\"" + ident.pop +
         "\",\"transport\":\"ble\"}";
}

void factoryReset() {
  prefs.begin(NS, false);
  prefs.remove("claim");
  prefs.end();
  cfg.claimCode = "";
}

}  // namespace settings
