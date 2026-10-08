/*
  SEM-1 Smart Energy Meter: production firmware
  ---------------------------------------------
  Open THIS file in the Arduino IDE. The code lives in the src/ folder next
  to it; the IDE compiles that folder automatically.

  setup() and loop() are in src/main.cpp.

  Before you upload (once):
    Tools > Board > Boards Manager: "esp32 by Espressif Systems" version 2.0.17
    Sketch > Include Library > Manage Libraries: "ArduinoJson" by Benoit Blanchon (7.x)

  Tools menu settings:
    Prototype (DevKit):  Board "ESP32 Dev Module"
                         Partition Scheme "Minimal SPIFFS (1.9MB APP with OTA/190KB SPIFFS)"
    Production (C3):     Board "ESP32C3 Dev Module"
                         Partition Scheme "Minimal SPIFFS (1.9MB APP with OTA/190KB SPIFFS)"
                         USB CDC On Boot "Enabled", Flash Mode "DIO"

  The Partition Scheme choice only raises the IDE's size limit. The flash
  layout actually used is partitions.csv in this folder (picked up
  automatically).

  The board pins and the CT type are chosen automatically from the board you
  select (see src/board.h).
*/
