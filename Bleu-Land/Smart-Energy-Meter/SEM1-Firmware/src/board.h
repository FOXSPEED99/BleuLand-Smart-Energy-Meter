// Pin map. The board is picked in platformio.ini (env:devkit or env:c3).
#pragma once

#if defined(SEM1_BOARD_DEVKIT)
// Prototype: ESP32-DevKitC-V4 (WROOM-32E) on the current Energy-Meter PCB.
#define SEM1_HW_NAME "SEM1-proto-devkit"
#define PIN_HLW_RX 16    // HLW8032 TX -> R11 1k / R6 2k divider -> IO16
#define PIN_HLW_TX 17    // not connected (HLW8032 RX is unused); same as the test firmware
#define HLW_UART 2
#define PIN_LED_WIFI 19  // D1 blue,  active LOW  (label: "WiFi link / setup")
#define PIN_LED_ENERGY 18  // D2 white, active LOW  (label: "ENERGY 1000 imp/kWh")
#define PIN_SDA 23       // DS1307
#define PIN_SCL 22
#define PIN_BUTTON 0     // DevKit BOOT button (no user button on the PCB yet)

#elif defined(SEM1_BOARD_C3)
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

#else
#error "Select a board: build with -D SEM1_BOARD_DEVKIT or -D SEM1_BOARD_C3 (see platformio.ini)"
#endif

#define LED_ACTIVE_LOW 1  // LED anode -> 330R -> 5 V, cathode -> GPIO
