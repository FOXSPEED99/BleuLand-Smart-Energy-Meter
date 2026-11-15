// Pin map and CT for each board. Picked automatically from the board you
// select in the Arduino IDE (Tools > Board):
//   "ESP32 Dev Module"   -> prototype (DevKit on the current PCB)
//   "ESP32C3 Dev Module" -> production board (ESP32-C3-WROOM-02)
#pragma once
#include <sdkconfig.h>

#if defined(CONFIG_IDF_TARGET_ESP32)
// Prototype: ESP32-DevKitC-V4 (WROOM-32E) on the current Energy-Meter PCB.
#define SEM1_HW_NAME "SEM1-proto-devkit"
// Prototype CT: SCT-013-030 (30 A / 1 V, 1800 turns, ~62 R inside), R14 = 2 x R220
#define SEM1_CT_TURNS 1800.0f
#define SEM1_CT_INT_BURDEN 62.0f
#define SEM1_R14_OHMS 0.44f
#define PIN_HLW_RX 16    // HLW8032 TX -> R11 1k / R6 2k divider -> IO16
#define PIN_HLW_TX 17    // not connected (HLW8032 RX is unused); same as the test firmware
#define HLW_UART 2
#define PIN_LED_WIFI 19  // D1 blue,  active LOW  (label: "WiFi link / setup")
#define PIN_LED_ENERGY 18  // D2 white, active LOW  (label: "ENERGY 1000 imp/kWh")
#define PIN_SDA 23       // DS1307
#define PIN_SCL 22
#define PIN_BUTTON 0     // DevKit BOOT button (no user button on the PCB yet)

#elif defined(CONFIG_IDF_TARGET_ESP32C3)
// Production: ESP32-C3-WROOM-02. PROPOSED pin map for the new PCB.
//   - GPIO2, GPIO8, GPIO9 are boot strapping pins: keep 10k pull-ups on 2 and 8.
//   - GPIO9 doubles as the user button: a front button to GND gives
//     "hold 5 s = WiFi reset" in normal use and "hold at power-up = flash mode".
//   - GPIO18/19 = USB D-/D+ (flashing + serial console, no USB-UART chip needed).
#define SEM1_HW_NAME "SEM1-C3"
#define PIN_HLW_RX 3
#define PIN_HLW_TX -1    // no TX needed: the HLW8032 only talks
#define HLW_UART 1
#define PIN_LED_WIFI 6
#define PIN_LED_ENERGY 7
#define PIN_SDA 4
#define PIN_SCL 5
#define PIN_BUTTON 9
// Production CT: SCT-013-000 (100 A : 50 mA, 2000 turns), R14 = 0.5 R
#define SEM1_CT_TURNS 2000.0f
#define SEM1_CT_INT_BURDEN 0.0f
#define SEM1_R14_OHMS 0.5f

#else
#error "Pick Tools > Board > \"ESP32 Dev Module\" (prototype) or \"ESP32C3 Dev Module\" (production)"
#endif

#define LED_ACTIVE_LOW 1  // LED anode -> 330R -> 5 V, cathode -> GPIO
