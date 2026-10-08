#include "console.h"

#include <Arduino.h>

#include "app.h"
#include "config.h"
#include "net.h"
#include "settings.h"

namespace {
String line;

void printInfo() {
  const Identity& id = settings::identity();
  const Settings& s = settings::get();
  LiveSnapshot l = app::snapshot();
  Serial.printf("id        %s\n", id.deviceId.c_str());
  Serial.printf("fw        %s\n", SEM1_FW_VERSION);
  Serial.printf("ble name  %s\n", id.bleName.c_str());
  Serial.printf("pop       %s\n", id.pop.c_str());
  Serial.printf("qr        %s\n", settings::qrPayload().c_str());
  Serial.printf("wifi      %s %s %d dBm\n",
                net::state() == NetState::Setup ? "setup" : net::online() ? "online" : "connecting",
                net::ip().c_str(), net::rssi());
  Serial.printf("time      %ld (%s)\n", (long)app::now(), app::timeSourceName());
  Serial.printf("rtc       %s\n", app::rtc().present() ? "present" : "MISSING");
  Serial.printf("live      %.1f V  %.3f A  %.1f W  PF %.3f\n", l.reading.v, l.reading.i, l.reading.p,
                l.reading.pf);
  Serial.printf("energy    %.4f kWh (other method since boot: %.4f kWh)\n", l.totalWh / 1000,
                l.altWhBoot / 1000);
  Serial.printf("hlw       good %u  bad %u  last %u ms ago\n", l.goodPackets, l.badPackets, l.packetAgeMs);
  Serial.printf("cal       V %.5f  I %.5f  P %.5f  (KV %.3f KI %.4f)\n", s.calV, s.calI, s.calP, KV, KI);
  Serial.printf("log       next #%u  capacity %u\n", app::log().nextSeq(), app::log().capacity());
  Serial.printf("claimed   %s\n", s.claimCode.length() ? "code stored" : "no");
}

void printLog(int n) {
  sem1::LogRecord recs[16];
  if (n < 1) n = 1;
  if (n > 16) n = 16;
  uint32_t next = app::log().nextSeq();
  uint32_t from = next > (uint32_t)n ? next - n : 1;
  uint32_t resume;
  size_t got = app::log().readFrom(from, recs, n, &resume);
  for (size_t k = 0; k < got; k++) {
    const auto& r = recs[k];
    Serial.printf("#%u ts %u  %.1f Wh  avg %u W  max %u W  %.1f V  flags %02X\n", r.seq, r.ts,
                  r.energyDWh / 10.0, r.pAvgW, r.pMaxW, r.vAvgDV / 10.0, r.flags);
  }
  if (!got) Serial.println("(log empty)");
}

void run(String cmd) {
  cmd.trim();
  if (!cmd.length()) return;
  int sp = cmd.indexOf(' ');
  String word = sp < 0 ? cmd : cmd.substring(0, sp);
  String arg = sp < 0 ? String("") : cmd.substring(sp + 1);
  arg.trim();

  if (word == "help") {
    Serial.println(
        "info                  device status\n"
        "qr                    QR payload for the front label\n"
        "cal v|i|p <value>     calibrate to a reference meter reading\n"
        "cal reset             back to 1.0 / 1.0 / 1.0\n"
        "energy int|pf         energy from P x dt (default) or the PF pulse counter\n"
        "time <unix>           set the clock by hand (UTC)\n"
        "log [n]               last n history records\n"
        "wifi-reset            forget WiFi, restart into phone setup\n"
        "factory-reset         also forget the owner\n"
        "reboot");
  } else if (word == "info") {
    printInfo();
  } else if (word == "qr") {
    Serial.println(settings::qrPayload());
  } else if (word == "cal") {
    if (arg == "reset") {
      Serial.println(app::resetCalibration());
    } else if (arg.length() > 2) {
      Serial.println(app::calibrate(arg[0], arg.substring(2).toFloat()));
    } else {
      Serial.println("usage: cal v 230.0");
    }
  } else if (word == "energy") {
    if (arg == "pf") Serial.println(app::setEnergySource(sem1::EnergySource::PfPulses));
    else if (arg == "int") Serial.println(app::setEnergySource(sem1::EnergySource::Integrated));
    else Serial.println("usage: energy int|pf");
  } else if (word == "time") {
    long t = arg.toInt();
    if (t >= (long)MIN_VALID_UNIX) {
      struct timeval tv = {(time_t)t, 0};
      settimeofday(&tv, nullptr);
      if (app::rtc().present()) app::rtc().write(t);
      Serial.println("clock set");
    } else {
      Serial.println("usage: time 1760000000");
    }
  } else if (word == "log") {
    printLog(arg.length() ? arg.toInt() : 8);
  } else if (word == "wifi-reset") {
    net::forgetWifiAndRestart();
  } else if (word == "factory-reset") {
    settings::factoryReset();
    net::forgetWifiAndRestart();
  } else if (word == "reboot") {
    ESP.restart();
  } else {
    Serial.println("unknown command, type: help");
  }
}
}  // namespace

namespace console {
void begin() { Serial.println("Type 'help' for commands."); }

void loop() {
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      run(line);
      line = "";
    } else if (line.length() < 80) {
      line += c;
    }
  }
}
}  // namespace console
