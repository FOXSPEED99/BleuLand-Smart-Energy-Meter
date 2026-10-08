/*
  SEM-1 Smart Energy Meter: production firmware

  This sketch is split into several files: they are the other tabs at the
  top of the Arduino IDE. When you press Upload, the IDE compiles ALL of
  them together, not just this tab.

    main.cpp        start-up, metering task, clock, history log, button
    hlw8032.cpp     reads the HLW8032 metering chip
    meter.cpp       1-second averages and the kWh counter
    datalog.cpp     5-minute history kept in flash while offline
    net.cpp         WiFi setup from the phone (Bluetooth) and reconnecting
    local_api.cpp   web page + JSON on your home network
    rtc_ds1307.cpp  DS1307 clock + energy backup
    settings.cpp    calibration and device identity (saved in flash)
    console.cpp     Serial Monitor commands (type "help")
    leds.cpp        ENERGY and WiFi LEDs
    board.h         pins and CT for each board (picked automatically)
    partitions.csv  flash layout (used automatically)

  Tools menu, prototype (DevKit):
    Board            "ESP32 Dev Module"
    Partition Scheme "Minimal SPIFFS (1.9MB APP with OTA/190KB SPIFFS)"
  Tools menu, production (ESP32-C3):
    Board            "ESP32C3 Dev Module"
    Partition Scheme "Minimal SPIFFS (1.9MB APP with OTA/190KB SPIFFS)"
    USB CDC On Boot  "Enabled",  Flash Mode "DIO"

  Needs: board package "esp32 by Espressif Systems" 3.x (tested 3.3.12;
  2.0.17 also works) and the "ArduinoJson" library 7.x (see README.md).
*/

#include "sem1.h"

void setup() {
  sem1Setup();  // runs once at power-up (see main.cpp)
}

void loop() {
  sem1Loop();   // runs over and over (see main.cpp)
}
