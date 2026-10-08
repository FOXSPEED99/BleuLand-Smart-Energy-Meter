// WiFi: phone setup over Bluetooth LE, then normal station mode.
//
// First power-up (or after a WiFi reset) the meter advertises over BLE as
// "SEM1_XXXXXX". The app scans the QR code on the front label (name + proof
// of possession), connects over BLE and sends the home WiFi name/password
// using Espressif's standard provisioning protocol (encrypted, "security 1").
// No SSID is ever hard-coded and there is no always-on access point (which is
// what froze the test firmware when the home network was missing).
//
// During setup the app can also send a one-time "claim code" on the extra
// BLE endpoint "sem1-claim"; the meter uses it later to link itself to the
// user's cloud account.
#pragma once
#include <Arduino.h>

enum class NetState : uint8_t { Setup, Connecting, Online };

namespace net {
void begin();   // call early: also brings up the radio for settings::begin()
void startProvisioningOrConnect();
void loop();
NetState state();
bool online();
String ip();
int rssi();
String hostname();
// Forget the home WiFi and restart into setup mode.
void forgetWifiAndRestart();
}  // namespace net
