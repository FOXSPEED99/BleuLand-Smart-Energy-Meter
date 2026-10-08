#include "net.h"

#include <ArduinoJson.h>
#include <ESPmDNS.h>
#include <WiFi.h>
#include <esp_arduino_version.h>
#include <esp_wifi.h>

// Espressif renamed the provisioning component between the two board-package
// generations (same phone protocol). These names cover both.
#if ESP_ARDUINO_VERSION_MAJOR >= 3
// Core 3.x frees the Bluetooth memory at boot unless a sketch says it uses
// BLE; this header says so. Without it, BLE setup would fail on the board.
#include <esp32-hal-alloc-ble-mem.h>
#include <network_provisioning/manager.h>
#include <network_provisioning/scheme_ble.h>
using prov_config_t = network_prov_mgr_config_t;
using prov_handler_t = network_prov_event_handler_t;
#define PROV_SCHEME_BLE network_prov_scheme_ble
#define PROV_HANDLER_FREE_BTDM NETWORK_PROV_SCHEME_BLE_EVENT_HANDLER_FREE_BTDM
#define PROV_HANDLER_NONE NETWORK_PROV_EVENT_HANDLER_NONE
#define PROV_SECURITY_1 NETWORK_PROV_SECURITY_1
#define prov_init network_prov_mgr_init
#define prov_deinit network_prov_mgr_deinit
#define prov_is_provisioned network_prov_mgr_is_wifi_provisioned
#define prov_set_uuid network_prov_scheme_ble_set_service_uuid
#define prov_endpoint_create network_prov_mgr_endpoint_create
#define prov_endpoint_register network_prov_mgr_endpoint_register
#define prov_start network_prov_mgr_start_provisioning
#define prov_reset_on_failure network_prov_mgr_reset_wifi_sm_state_on_failure
#else
#include <wifi_provisioning/manager.h>
#include <wifi_provisioning/scheme_ble.h>
using prov_config_t = wifi_prov_mgr_config_t;
using prov_handler_t = wifi_prov_event_handler_t;
#define PROV_SCHEME_BLE wifi_prov_scheme_ble
#define PROV_HANDLER_FREE_BTDM WIFI_PROV_SCHEME_BLE_EVENT_HANDLER_FREE_BTDM
#define PROV_HANDLER_NONE WIFI_PROV_EVENT_HANDLER_NONE
#define PROV_SECURITY_1 WIFI_PROV_SECURITY_1
#define prov_init wifi_prov_mgr_init
#define prov_deinit wifi_prov_mgr_deinit
#define prov_is_provisioned wifi_prov_mgr_is_provisioned
#define prov_set_uuid wifi_prov_scheme_ble_set_service_uuid
#define prov_endpoint_create wifi_prov_mgr_endpoint_create
#define prov_endpoint_register wifi_prov_mgr_endpoint_register
#define prov_start wifi_prov_mgr_start_provisioning
#define prov_reset_on_failure wifi_prov_mgr_reset_sm_state_on_failure
#endif

#include "config.h"
#include "settings.h"

bool wifiLowLevelInit(bool persistent);  // from the Arduino WiFi library

namespace {
volatile NetState netState = NetState::Connecting;
volatile bool gotIp = false;
bool mdnsStarted = false;
uint32_t lastRetryMs = 0;
String host;

// Espressif's default provisioning service UUID (what their apps expect).
uint8_t serviceUuid[16] = {0xb4, 0xdf, 0x5a, 0x1c, 0x3f, 0x6b, 0xf4, 0xbf,
                           0xea, 0x4a, 0x82, 0x03, 0x04, 0x90, 0x1a, 0x02};

// BLE endpoint "sem1-claim". Request:  {"claim":"<one-time code>"}
//                            Response: {"id":"SEM1-A1B2C3","fw":"0.1.0","ok":true}
esp_err_t claimHandler(uint32_t, const uint8_t* in, ssize_t inLen, uint8_t** out, ssize_t* outLen, void*) {
  JsonDocument req;
  bool ok = false;
  if (in && inLen > 0 && !deserializeJson(req, (const char*)in, (size_t)inLen)) {
    const char* code = req["claim"] | "";
    size_t n = strlen(code);
    if (n >= 6 && n <= 64) {
      settings::saveClaimCode(code);
      ok = true;
    }
  }
  JsonDocument res;
  res["id"] = settings::identity().deviceId;
  res["fw"] = SEM1_FW_VERSION;
  res["ok"] = ok;
  size_t len = measureJson(res);
  char* buf = (char*)malloc(len + 1);  // freed by the provisioning library
  if (!buf) return ESP_ERR_NO_MEM;
  serializeJson(res, buf, len + 1);
  *out = (uint8_t*)buf;
  *outLen = len;
  return ESP_OK;
}

void onEvent(arduino_event_id_t event, arduino_event_info_t) {
  switch (event) {
    case ARDUINO_EVENT_PROV_START:
      Serial.println("[net] BLE setup started, waiting for the app");
      netState = NetState::Setup;
      break;
    case ARDUINO_EVENT_PROV_CRED_RECV:
      Serial.println("[net] WiFi details received, connecting");
      netState = NetState::Connecting;
      break;
    case ARDUINO_EVENT_PROV_CRED_FAIL:
      // Wrong password or network not found: let the app try again.
      Serial.println("[net] could not join that WiFi, waiting for new details");
      prov_reset_on_failure();
      netState = NetState::Setup;
      break;
    case ARDUINO_EVENT_PROV_CRED_SUCCESS:
      Serial.println("[net] setup done");
      break;
    case ARDUINO_EVENT_WIFI_STA_GOT_IP:
      gotIp = true;
      netState = NetState::Online;
      break;
    case ARDUINO_EVENT_WIFI_STA_DISCONNECTED:
    case ARDUINO_EVENT_WIFI_STA_LOST_IP:
      gotIp = false;
      if (netState == NetState::Online) netState = NetState::Connecting;
      break;
    default:
      break;
  }
}
}  // namespace

namespace net {

void begin() {
  host = settings::identity().deviceId;
  host.toLowerCase();  // "sem1-a1b2c3" -> http://sem1-a1b2c3.local
  WiFi.onEvent(onEvent);
  WiFi.setHostname(host.c_str());
  wifiLowLevelInit(true);
}

void startProvisioningOrConnect() {
  prov_config_t cfg = {};
  cfg.scheme = PROV_SCHEME_BLE;
  prov_handler_t freeBt = PROV_HANDLER_FREE_BTDM;
  cfg.scheme_event_handler = freeBt;  // release BT memory once setup is over
  prov_handler_t none = PROV_HANDLER_NONE;
  cfg.app_event_handler = none;

  if (prov_init(cfg) != ESP_OK) {
    Serial.println("[net] provisioning init failed, trying saved WiFi");
    WiFi.begin();
    return;
  }
  bool provisioned = false;
  prov_is_provisioned(&provisioned);

  if (!provisioned) {
    const Identity& id = settings::identity();
    netState = NetState::Setup;
    prov_set_uuid(serviceUuid);
    prov_endpoint_create("sem1-claim");
    if (prov_start(PROV_SECURITY_1, id.pop.c_str(), id.bleName.c_str(), nullptr) != ESP_OK) {
      Serial.println("[net] could not start BLE setup");
      return;
    }
    prov_endpoint_register("sem1-claim", claimHandler, nullptr);
    Serial.printf("[net] setup mode: BLE name %s\n", id.bleName.c_str());
    Serial.printf("[net] QR payload: %s\n", settings::qrPayload().c_str());
  } else {
    netState = NetState::Connecting;
    esp_wifi_start();
    prov_deinit();
    WiFi.setSleep(false);  // no modem sleep: smoother live data
    WiFi.begin();          // saved network
    lastRetryMs = millis();
  }
}

void loop() {
  uint32_t now = millis();
  if (netState == NetState::Connecting && !gotIp && now - lastRetryMs > 30000) {
    // Router off or out of range: keep trying every 30 s. Only the station
    // runs (no access point), so this can't freeze anything.
    lastRetryMs = now;
    WiFi.reconnect();
  }
  static bool wasOnline = false;
  bool on = gotIp;
  if (on && !wasOnline) {
    if (!mdnsStarted && MDNS.begin(host.c_str())) {
      mdnsStarted = true;
      MDNS.addService("http", "tcp", 80);
      MDNS.addService("sem1", "tcp", 80);  // lets the app find meters on the LAN
      MDNS.addServiceTxt("sem1", "tcp", "id", settings::identity().deviceId.c_str());
      MDNS.addServiceTxt("sem1", "tcp", "fw", SEM1_FW_VERSION);
    }
    Serial.printf("[net] online: http://%s  (http://%s.local)\n", WiFi.localIP().toString().c_str(),
                  host.c_str());
  }
  wasOnline = on;
}

NetState state() { return netState; }
bool online() { return gotIp; }
String ip() { return gotIp ? WiFi.localIP().toString() : String(""); }
int rssi() { return gotIp ? WiFi.RSSI() : 0; }
String hostname() { return host; }

void forgetWifiAndRestart() {
  Serial.println("[net] forgetting WiFi and restarting into setup mode");
  WiFi.disconnect(true, true);  // erase the saved network
  delay(200);
  ESP.restart();
}

}  // namespace net
