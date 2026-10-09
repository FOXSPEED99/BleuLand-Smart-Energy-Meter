// Values kept in flash (NVS namespace "sem1", same as the test firmware, so
// calibration done with SEM1_Test.ino carries over).
#pragma once
#include <Arduino.h>

#include "meter.h"

struct Identity {
  String deviceId;     // "SEM1-A1B2C3" (from the MAC address)
  String bleName;      // "SEM1_A1B2C3" (what the phone sees during setup)
  String pop;          // 8-char "proof of possession" printed in the label QR
  String secret;       // 32 hex chars, device's cloud password (never shown to users)
};

struct Settings {
  float calV = 1.0f, calI = 1.0f, calP = 1.0f;
  sem1::EnergySource energySource = sem1::EnergySource::Integrated;
  String claimCode;    // one-time code from the app; used once to link the device to an account
};

namespace settings {
void begin();  // call after WiFi is initialised (needs the MAC and a good RNG)
const Identity& identity();
Settings& get();
void saveCalibration();
void saveEnergySource();
void saveClaimCode(const String& code);

// True once the saved WiFi came from our own phone setup (not from other firmware).
bool wifiFromSetup();
void setWifiFromSetup(bool v);

// "Open WiFi setup at the next boot": 1 = someone asked (button, app),
// 2 = automatic (the saved WiFi has been unreachable for a while).
void requestSetupWindow(uint8_t why);
uint8_t takeSetupWindow();  // reads and clears the request (0 = none)

// The working WiFi, kept while a setup window runs, so it can be put back if
// nobody sets up a new one (or the power fails in the middle).
void saveWifiBackup(const String& ssid, const String& pass);
bool loadWifiBackup(String& ssid, String& pass);
void clearWifiBackup();

// Fallback energy storage when the board has no working RTC.
uint64_t loadEnergyMilliWh();
void saveEnergyMilliWh(uint64_t mwh);

// The Espressif provisioning QR payload for the label / app.
String qrPayload();

// Forget owner + user settings. Keeps identity and factory calibration.
void factoryReset();
}  // namespace settings
