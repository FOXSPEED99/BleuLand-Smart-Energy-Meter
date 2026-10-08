// Cloud link (Supabase): registers the meter, sends live values every 10 s
// and uploads the 5-minute history it stored while offline.
//
// Runs in its own background task, so a slow or broken internet connection
// can never block the button, the web page or the energy counting.
#pragma once
#include <Arduino.h>

enum class CloudState : uint8_t {
  Off,         // no WiFi yet
  Connecting,  // trying to reach the cloud
  Ok,          // last upload worked
  Error,       // cloud not reachable (internet down, server error)
  AuthError,   // the cloud rejected this meter's secret
};

namespace cloud {
void begin();
CloudState state();
const char* stateName();
bool claimed();           // the meter has an owner in the app
uint32_t lastOkUnix();    // time of the last successful upload (0 = never)
String lastError();
}  // namespace cloud
