// Front-panel LEDs, as printed on the label:
//   ENERGY (white): one short flash per Wh = 1000 imp/kWh
//   WiFi   (blue) : link / setup status
//
// WiFi LED patterns:
//   slow blink (1 s on / 1 s off) ... waiting for setup from the phone app
//   fast blink (4x per second) ...... connecting to the home WiFi
//   on ............................... connected
//   on, short off-blink every 2 s ... connected, but the cloud can't be reached
//   flicker ......................... button held long enough: release to reset
#pragma once
#include <stdint.h>

enum class WifiLed : uint8_t { Off, Setup, Connecting, Online, CloudDown, ResetArmed, FactoryArmed };

namespace leds {
void begin();
void setWifi(WifiLed mode);
void addEnergyPulses(uint32_t n);  // queue ENERGY flashes
void update(uint32_t nowMs);       // call every ~10-20 ms
}  // namespace leds
