#include "cloud.h"

#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>

#include "app.h"
#include "board.h"
#include "cloud_certs.h"
#include "config.h"
#include "net.h"
#include "settings.h"

namespace {
volatile CloudState st = CloudState::Off;
volatile bool isClaimed = false;
volatile uint32_t lastOk = 0;
String lastErr;  // written by the cloud task only
SemaphoreHandle_t errMtx;

WiFiClientSecure tls;
HTTPClient http;

void setError(CloudState s, const String& e) {
  st = s;
  xSemaphoreTake(errMtx, portMAX_DELAY);
  lastErr = e;
  xSemaphoreGive(errMtx);
  Serial.printf("[cloud] %s\n", e.c_str());
}

// POST to a database function. Returns the HTTP status (negative = network
// error) and fills `res` with the JSON answer.
int callRpc(const char* fn, const JsonDocument& body, JsonDocument& res) {
  String url = String(CLOUD_URL) + "/rest/v1/rpc/" + fn;
  if (!http.begin(tls, url)) return -1000;
  http.addHeader("apikey", CLOUD_KEY);
  http.addHeader("Content-Type", "application/json");
  String payload;
  serializeJson(body, payload);
  int code = http.POST(payload);
  if (code > 0) {
    String text = http.getString();
    res.clear();
    deserializeJson(res, text);
  }
  http.end();  // keeps the TLS connection open for the next call (keep-alive)
  return code;
}

bool hello() {
  const Identity& id = settings::identity();
  JsonDocument body, res;
  body["p_id"] = id.deviceId;
  body["p_secret"] = id.secret;
  body["p_pop"] = id.pop;
  body["p_fw"] = SEM1_FW_VERSION;
  body["p_hw"] = SEM1_HW_NAME;
  int code = callRpc("device_hello", body, res);
  if (code != 200) {
    setError(CloudState::Error, String("hello failed: HTTP ") + code);
    return false;
  }
  if (!(res["ok"] | false)) {
    String e = res["error"] | "unknown";
    // "auth": this meter's secret doesn't match the one the cloud stored
    // when it first registered (e.g. after a full flash erase).
    setError(e == "auth" ? CloudState::AuthError : CloudState::Error, "hello rejected: " + e);
    return false;
  }
  isClaimed = res["claimed"] | false;
  Serial.printf("[cloud] registered, %s\n", isClaimed ? "linked to an account" : "not yet added to an account");
  return true;
}

// One upload: live values plus up to CLOUD_BATCH history records that the
// cloud doesn't have yet. Returns true on success; *more = records left.
bool push(bool* more) {
  *more = false;
  const Identity& id = settings::identity();
  JsonDocument body, res;
  body["p_id"] = id.deviceId;
  body["p_secret"] = id.secret;

  time_t now = app::now();
  if (now) {
    LiveSnapshot l = app::snapshot();
    JsonObject live = body["p_live"].to<JsonObject>();
    live["ts"] = (uint32_t)now;
    live["v"] = serialized(String(l.reading.v, 1));
    live["i"] = serialized(String(l.reading.i, 3));
    live["p"] = serialized(String(l.reading.p, 1));
    live["s"] = serialized(String(l.reading.s, 1));
    live["pf"] = serialized(String(l.reading.pf, 3));
    live["kwh"] = serialized(String(l.totalWh / 1000.0, 4));
    live["rssi"] = net::rssi();
  } else {
    body["p_live"] = nullptr;
  }

  // The log was wiped (e.g. full flash erase) but the "uploaded up to" mark
  // survived in the RTC: start over (the cloud ignores duplicates).
  if (app::uploadedSeq() >= app::log().nextSeq()) app::setUploadedSeq(0);

  static sem1::LogRecord recs[CLOUD_BATCH];
  uint32_t resume = 0;
  size_t n = app::readLog(app::uploadedSeq() + 1, recs, CLOUD_BATCH, &resume);
  if (n) {
    JsonArray arr = body["p_records"].to<JsonArray>();
    for (size_t k = 0; k < n; k++) {
      JsonObject r = arr.add<JsonObject>();
      r["seq"] = recs[k].seq;
      r["ts"] = recs[k].ts;
      r["e"] = recs[k].energyDWh;
      r["pa"] = recs[k].pAvgW;
      r["pm"] = recs[k].pMaxW;
      r["v"] = serialized(String(recs[k].vAvgDV / 10.0, 1));
      r["f"] = recs[k].flags;
    }
  } else {
    body["p_records"] = nullptr;
  }

  int code = callRpc("device_push", body, res);
  if (code != 200) {
    setError(CloudState::Error, String("upload failed: HTTP ") + code);
    return false;
  }
  if (!(res["ok"] | false)) {
    String e = res["error"] | "unknown";
    setError(e == "auth" ? CloudState::AuthError : CloudState::Error, "upload rejected: " + e);
    return false;
  }
  // Records that were skipped while reading (damaged slots) count as sent too.
  if (n) app::setUploadedSeq(resume - 1);
  else if (resume > app::uploadedSeq() + 1) app::setUploadedSeq(resume - 1);
  *more = resume < app::log().nextSeq();
  return true;
}

void cloudTask(void*) {
  tls.setCACert(CLOUD_ROOT_CAS);
  tls.setTimeout(15);  // seconds
  http.setReuse(true);
  http.setTimeout(15000);

  bool registered = false;
  uint32_t backoffS = 5;
  for (;;) {
    if (!net::online() || !app::now()) {
      // no WiFi, or no clock yet (TLS needs the date to check certificates)
      if (!net::online()) st = CloudState::Off;
      vTaskDelay(pdMS_TO_TICKS(1000));
      continue;
    }
    if (st == CloudState::Off) st = CloudState::Connecting;

    bool ok, more = false;
    if (!registered) ok = registered = hello();
    else ok = push(&more);

    if (ok) {
      if (st != CloudState::Ok) Serial.println("[cloud] connected");
      st = CloudState::Ok;
      lastOk = (uint32_t)app::now();
      backoffS = 5;
      if (registered && !more) vTaskDelay(pdMS_TO_TICKS(CLOUD_LIVE_S * 1000));
      else vTaskDelay(pdMS_TO_TICKS(200));  // still catching up on history
    } else {
      tls.stop();
      // a rejected secret won't fix itself: try rarely
      uint32_t wait = (st == CloudState::AuthError) ? 600 : backoffS;
      vTaskDelay(pdMS_TO_TICKS(wait * 1000));
      backoffS = backoffS * 2 > CLOUD_RETRY_MAX_S ? CLOUD_RETRY_MAX_S : backoffS * 2;
    }
  }
}
}  // namespace

namespace cloud {

void begin() {
  errMtx = xSemaphoreCreateMutex();
  // TLS needs a large stack; low priority so it never delays metering.
  xTaskCreate(cloudTask, "cloud", 12288, nullptr, 1, nullptr);
}

CloudState state() { return st; }

const char* stateName() {
  switch (st) {
    case CloudState::Off: return "off";
    case CloudState::Connecting: return "connecting";
    case CloudState::Ok: return "ok";
    case CloudState::Error: return "error";
    case CloudState::AuthError: return "auth_error";
  }
  return "?";
}

bool claimed() { return isClaimed; }
uint32_t lastOkUnix() { return lastOk; }

String lastError() {
  xSemaphoreTake(errMtx, portMAX_DELAY);
  String e = lastErr;
  xSemaphoreGive(errMtx);
  return e;
}

}  // namespace cloud
