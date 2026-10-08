#include "leds.h"

#include <Arduino.h>

#include "board.h"

namespace {
volatile WifiLed wifiMode = WifiLed::Off;
volatile uint32_t pendingPulses = 0;
uint32_t pulseUntilMs = 0;
uint32_t nextPulseMs = 0;
constexpr uint32_t PULSE_ON_MS = 40;
constexpr uint32_t PULSE_MIN_GAP_MS = 40;
constexpr uint32_t MAX_QUEUED = 20;

void drive(int pin, bool on) { digitalWrite(pin, (on ^ LED_ACTIVE_LOW) ? HIGH : LOW); }
}  // namespace

namespace leds {

void begin() {
  pinMode(PIN_LED_WIFI, OUTPUT);
  pinMode(PIN_LED_ENERGY, OUTPUT);
  drive(PIN_LED_WIFI, false);
  drive(PIN_LED_ENERGY, false);
}

void setWifi(WifiLed mode) { wifiMode = mode; }

void addEnergyPulses(uint32_t n) {
  uint32_t p = pendingPulses + n;
  pendingPulses = p > MAX_QUEUED ? MAX_QUEUED : p;  // never lag far behind
}

void update(uint32_t now) {
  bool w = false;
  switch (wifiMode) {
    case WifiLed::Off: w = false; break;
    case WifiLed::Setup: w = (now / 1000) % 2; break;
    case WifiLed::Connecting: w = (now / 125) % 2; break;
    case WifiLed::Online: w = true; break;
    case WifiLed::CloudDown: w = (now % 2000) >= 150; break;
    case WifiLed::ResetArmed: w = (now / 50) % 2; break;
    case WifiLed::FactoryArmed: w = true; break;
  }
  drive(PIN_LED_WIFI, w);

  if (wifiMode == WifiLed::FactoryArmed) {
    drive(PIN_LED_ENERGY, true);  // both on: release now for a factory reset
    return;
  }
  if (pulseUntilMs && (int32_t)(now - pulseUntilMs) >= 0) {
    pulseUntilMs = 0;
    nextPulseMs = now + PULSE_MIN_GAP_MS;
    drive(PIN_LED_ENERGY, false);
  }
  if (!pulseUntilMs && pendingPulses && (int32_t)(now - nextPulseMs) >= 0) {
    pendingPulses = pendingPulses - 1;
    pulseUntilMs = now + PULSE_ON_MS;
    if (!pulseUntilMs) pulseUntilMs = 1;
    drive(PIN_LED_ENERGY, true);
  }
  if (!pulseUntilMs) drive(PIN_LED_ENERGY, false);
}

}  // namespace leds
