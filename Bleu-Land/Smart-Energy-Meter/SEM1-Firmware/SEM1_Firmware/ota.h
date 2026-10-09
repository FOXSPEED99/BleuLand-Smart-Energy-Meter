// Firmware updates over WiFi.
//
// The new firmware is written into the spare app slot while the meter keeps
// measuring, checked (size + MD5), and only then made the boot slot. After the
// restart it is "on probation": it must reach the cloud within 10 minutes,
// otherwise (or if it crashes first) the bootloader goes back to the old one.
#pragma once
#include <Arduino.h>

namespace ota {

void begin();  // at boot: report whether this image is on probation
void loop();   // probation timeout

// The new firmware works (called after a successful cloud hello).
void markHealthy();
bool onProbation();

// Download `url` into the spare slot. Returns "" on success (then restart),
// otherwise a short reason for the app.
String install(const char* url, size_t size, const char* md5);

void printInfo();  // console "ota"

}  // namespace ota
