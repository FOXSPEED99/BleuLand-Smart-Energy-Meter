/*
  SEM-1 prototype test firmware
  ------------------------------------------------------------
  - Reads the HLW8032 on GPIO16 (4800 baud, 8E1)
  - Live web page: voltage, current, power, PF, energy, raw packet
  - Calibration from the web page (saved in flash)
  - OTA updates over WiFi (no USB cable needed after the first flash)
  - Checks that the DS1307 RTC answers on I2C

  Pins come from the SEM-1 schematic (Energy-Meter.SchDoc):
    HLW8032 TX -> R11 1k / R6 2k divider -> IO16
    Blue LED  D1 -> IO19 (active LOW)
    White LED D2 -> IO18 (active LOW)
    DS1307 SDA -> IO23, SCL -> IO22

  Board in Arduino IDE: "ESP32 Dev Module"
*/

#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoOTA.h>
#include <Preferences.h>
#include <Wire.h>

// ================== CHANGE THESE ==================
const char* WIFI_SSID = "YOUR_WIFI_NAME";
const char* WIFI_PASS = "YOUR_WIFI_PASSWORD";
const char* OTA_PASS  = "sem1ota";        // asked by Arduino IDE when uploading over WiFi

// R14 burden resistor actually fitted:
//   prototype: 2 x R220 in series = 0.44
//   real PCB : 0.5
const float R14_OHMS = 0.44;

// Which CT is plugged in:
//   SCT-013-030 (30A/1V, voltage output) : CT_TURNS 1800, CT_INT_BURDEN 62
//   SCT-013-000 (100A:50mA, current out) : CT_TURNS 2000, CT_INT_BURDEN 0
const float CT_TURNS      = 1800;
const float CT_INT_BURDEN = 62.0;   // ohms, built into the 30A/1V model
// ==================================================

// ---------- pins ----------
const int PIN_HLW_RX = 16;
const int PIN_HLW_TX = 17;   // not connected, HLW8032 RX is unused
const int PIN_LED_B  = 19;
const int PIN_LED_W  = 18;
const int PIN_SDA    = 23;
const int PIN_SCL    = 22;

// ---------- front-end coefficients ----------
// Voltage: 4 x 47k = 188k into ZMPT101B (2mA:2mA), 100R burden.
// Same ratio as the datasheet's 1.88M / 1k divider -> coefficient 1.88
const float KV = 1.88;
// Current: the CT turns line current into I/CT_TURNS, which flows through the burden
// (R14, in parallel with the CT's own internal burden if it has one).
// "Equivalent shunt" = R_burden / CT_TURNS. HLW8032 coefficient is 1.0 for a 1 mOhm shunt.
const float R_BURDEN = (CT_INT_BURDEN > 0) ? (R14_OHMS * CT_INT_BURDEN) / (R14_OHMS + CT_INT_BURDEN)
                                           : R14_OHMS;
const float KI = 0.001f / (R_BURDEN / CT_TURNS);   // 30A/1V + 0.44R -> 4.12, 100A + 0.44R -> 4.545

// ---------- calibration (saved in flash) ----------
Preferences prefs;
float calV = 1.0f, calI = 1.0f, calP = 1.0f;

// ---------- HLW8032 packet state ----------
uint8_t  buf[24];
int      fill = 0;
uint8_t  lastRaw[24];
bool     haveRaw = false;
uint32_t goodPk = 0, badPk = 0, lastPkMs = 0;
uint8_t  lastState = 0;

// per-second averaging
double   sumV = 0, sumI = 0, sumP = 0;
uint32_t nAvg = 0, lastAvgMs = 0;

// published values
float V = 0, I = 0, P = 0, S = 0, PF = 0;
double kWh = 0;

bool rtcFound = false;
bool apMode = false;

WebServer server(80);

// ---------- DS1307 RTC test ----------
// Reads the clock registers directly (no library needed).
const uint8_t RTC_ADDR  = 0x68;
const uint8_t RTC_RAM   = 0x08;   // first byte of the DS1307's battery-backed RAM
const uint8_t RTC_MAGIC = 0xA5;   // written when you set the time; survives only if the battery works

struct RtcTime { uint8_t sec, min, hour, dow, day, mon; uint16_t year; bool halted; };
RtcTime  rtcNow = {0, 0, 0, 0, 1, 1, 2000, true};
bool     rtcKeptAtBoot = false;   // RAM marker was still there at power-up
uint8_t  rtcLastSec = 255;
uint32_t rtcLastChangeMs = 0;

static uint8_t bcd2dec(uint8_t b) { return (b >> 4) * 10 + (b & 0x0F); }
static uint8_t dec2bcd(uint8_t d) { return ((d / 10) << 4) | (d % 10); }

bool rtcRead(RtcTime& t) {
  Wire.beginTransmission(RTC_ADDR);
  Wire.write((uint8_t)0x00);
  if (Wire.endTransmission() != 0) return false;
  if (Wire.requestFrom((int)RTC_ADDR, 7) != 7) return false;
  uint8_t r[7];
  for (int k = 0; k < 7; k++) r[k] = Wire.read();
  t.halted = r[0] & 0x80;                       // CH bit: 1 = oscillator stopped
  t.sec    = bcd2dec(r[0] & 0x7F);
  t.min    = bcd2dec(r[1] & 0x7F);
  if (r[2] & 0x40) {                            // 12-hour mode
    uint8_t h = bcd2dec(r[2] & 0x1F);
    t.hour = (h % 12) + ((r[2] & 0x20) ? 12 : 0);
  } else {
    t.hour = bcd2dec(r[2] & 0x3F);
  }
  t.dow  = r[3] & 0x07;
  t.day  = bcd2dec(r[4] & 0x3F);
  t.mon  = bcd2dec(r[5] & 0x1F);
  t.year = 2000 + bcd2dec(r[6]);
  return true;
}

bool rtcWrite(uint16_t y, uint8_t mo, uint8_t d, uint8_t h, uint8_t mi, uint8_t s, uint8_t dow) {
  Wire.beginTransmission(RTC_ADDR);
  Wire.write((uint8_t)0x00);
  Wire.write(dec2bcd(s) & 0x7F);   // CH = 0 -> starts the crystal
  Wire.write(dec2bcd(mi));
  Wire.write(dec2bcd(h));          // 24-hour mode
  Wire.write(dow);                 // 1..7
  Wire.write(dec2bcd(d));
  Wire.write(dec2bcd(mo));
  Wire.write(dec2bcd(y % 100));
  Wire.write((uint8_t)0x00);       // control register: square-wave output off
  Wire.write(RTC_MAGIC);           // RAM marker for the battery test
  return Wire.endTransmission() == 0;
}

bool rtcReadMagic() {
  Wire.beginTransmission(RTC_ADDR);
  Wire.write(RTC_RAM);
  if (Wire.endTransmission() != 0) return false;
  if (Wire.requestFrom((int)RTC_ADDR, 1) != 1) return false;
  return Wire.read() == RTC_MAGIC;
}

void checkRTC() {
  RtcTime t;
  rtcFound = rtcRead(t);
  if (!rtcFound) return;
  rtcNow = t;
  if (t.sec != rtcLastSec) {
    rtcLastSec = t.sec;
    rtcLastChangeMs = millis();
  }
}

bool rtcTicking() { return rtcFound && !rtcNow.halted && millis() - rtcLastChangeMs < 2500; }

void handleRtcSet() {
  if (!rtcFound) { server.send(200, "text/plain", "RTC not found"); return; }
  bool ok = rtcWrite(server.arg("y").toInt(), server.arg("mo").toInt(), server.arg("d").toInt(),
                     server.arg("h").toInt(), server.arg("mi").toInt(), server.arg("s").toInt(),
                     server.arg("dw").toInt());
  server.send(200, "text/plain", ok ? "RTC set from phone time" : "RTC write failed");
}

// ---------- helpers ----------
static uint32_t r24(const uint8_t* b) {
  return ((uint32_t)b[0] << 16) | ((uint32_t)b[1] << 8) | b[2];
}

static void ledB(bool on) { digitalWrite(PIN_LED_B, on ? LOW : HIGH); }
static void ledW(bool on) { digitalWrite(PIN_LED_W, on ? LOW : HIGH); }

static bool headerOk(const uint8_t* f) {
  if (f[1] != 0x5A) return false;
  return f[0] == 0x55 || f[0] == 0xAA || (f[0] & 0xF0) == 0xF0;
}

static bool checksumOk(const uint8_t* f) {
  uint8_t sum = 0;
  for (int k = 2; k <= 22; k++) sum += f[k];
  return sum == f[23];
}

// ---------- decode one valid 24-byte packet ----------
void parsePacket(const uint8_t* f) {
  memcpy(lastRaw, f, 24);
  haveRaw = true;
  goodPk++;
  lastPkMs = millis();
  lastState = f[0];

  if (f[0] == 0xAA) return;   // chip error: calibration registers unusable

  uint32_t vPar = r24(f + 2),  vDat = r24(f + 5);
  uint32_t iPar = r24(f + 8),  iDat = r24(f + 11);
  uint32_t pPar = r24(f + 14), pDat = r24(f + 17);

  // 0xFx = some period registers overflowed (signal too small, e.g. no load)
  bool vOvf = false, iOvf = false, pOvf = false;
  if ((f[0] & 0xF0) == 0xF0) {
    vOvf = f[0] & 0x08;
    iOvf = f[0] & 0x04;
    pOvf = f[0] & 0x02;
  }

  float v = (!vOvf && vDat) ? (float)vPar / vDat * KV * calV : 0;
  float i = (!iOvf && iDat) ? (float)iPar / iDat * KI * calI : 0;
  float p = (!pOvf && pDat) ? (float)pPar / pDat * KV * KI * calP : 0;

  // No-load cutoff: if the chip sees no real power, the small current
  // reading is just the input noise floor (~0.2 A on the prototype).
  if (pOvf) i = 0;

  sumV += v; sumI += i; sumP += p; nAvg++;

  if (goodPk % 20 == 0) ledB(true);   // short blink about once a second
}

// sliding window: works even though packets arrive back-to-back
void feedByte(uint8_t c) {
  if (fill < 24) {
    buf[fill++] = c;
  } else {
    memmove(buf, buf + 1, 23);
    buf[23] = c;
  }
  if (fill == 24 && headerOk(buf)) {
    if (checksumOk(buf)) {
      parsePacket(buf);
      fill = 0;
    } else {
      badPk++;
    }
  }
}

// ---------- once per second ----------
void updateAverages() {
  uint32_t now = millis();
  if (now - lastAvgMs < 1000) return;
  float dt = (now - lastAvgMs) / 1000.0f;
  lastAvgMs = now;

  if (nAvg > 0) {
    V = sumV / nAvg;
    I = sumI / nAvg;
    P = sumP / nAvg;
  } else {
    V = I = P = 0;      // no packets in the last second
  }
  sumV = sumI = sumP = 0;
  nAvg = 0;

  S  = V * I;
  PF = (S > 1.0f) ? P / S : 0;
  if (PF > 1.0f) PF = 1.0f;

  kWh += (double)P * dt / 3600000.0;

  ledB(false);
}

// ---------- calibration ----------
void loadCal() {
  prefs.begin("sem1", true);
  calV = prefs.getFloat("calV", 1.0f);
  calI = prefs.getFloat("calI", 1.0f);
  calP = prefs.getFloat("calP", 1.0f);
  prefs.end();
}

void saveCal() {
  prefs.begin("sem1", false);
  prefs.putFloat("calV", calV);
  prefs.putFloat("calI", calI);
  prefs.putFloat("calP", calP);
  prefs.end();
}

// ---------- web page ----------
const char PAGE[] PROGMEM = R"HTML(
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SEM-1 Test</title>
<style>
body{font-family:system-ui,sans-serif;background:#1b1d21;color:#e8e8e8;margin:0;padding:16px;max-width:520px}
h1{font-size:20px;margin:0 0 12px}
.g{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.c{background:#26292f;border-radius:10px;padding:12px}
.l{font-size:12px;color:#9aa}
.v{font-size:26px;font-weight:600}
.s{font-size:13px;color:#bbb;margin-top:12px;line-height:1.6}
code{font-size:12px;word-break:break-all;color:#8fd}
input{width:90px;padding:6px;border-radius:6px;border:1px solid #444;background:#111;color:#eee}
button{padding:6px 10px;border-radius:6px;border:0;background:#3b82f6;color:#fff}
.row{margin:6px 0}
</style></head><body>
<h1>SEM-1 prototype</h1>
<div class="g">
 <div class="c"><div class="l">Voltage</div><div class="v" id="v">-</div></div>
 <div class="c"><div class="l">Current</div><div class="v" id="i">-</div></div>
 <div class="c"><div class="l">Active power</div><div class="v" id="p">-</div></div>
 <div class="c"><div class="l">Power factor</div><div class="v" id="pf">-</div></div>
 <div class="c"><div class="l">Apparent power</div><div class="v" id="s">-</div></div>
 <div class="c"><div class="l">Energy (since boot)</div><div class="v" id="e">-</div></div>
</div>
<div class="s" id="st"></div>
<div class="s">Last packet:<br><code id="raw">-</code></div>
<div class="s"><b>RTC test</b><br><span id="rtc">-</span>
 <div class="row"><button onclick="setRtc()">Set RTC from phone time</button></div>
</div>
<div class="s"><b>Calibrate</b> (type what your reference meter shows):
 <div class="row">Voltage <input id="cv" placeholder="230.0"> V <button onclick="cal('v','cv')">Set</button></div>
 <div class="row">Current <input id="ci" placeholder="8.70"> A <button onclick="cal('i','ci')">Set</button></div>
 <div class="row">Power <input id="cp" placeholder="2000"> W <button onclick="cal('p','cp')">Set</button></div>
 <div class="row"><button onclick="fetch('/cal?reset=1').then(r=>r.text()).then(say)">Reset calibration</button>
 <button onclick="fetch('/kwh').then(r=>r.text()).then(say)">Reset energy</button></div>
</div>
<div class="s" id="msg"></div>
<script>
function $(id){return document.getElementById(id);}
function say(t){$('msg').textContent=t;}
function cal(k,id){var x=$(id).value;if(x)fetch('/cal?'+k+'='+x).then(r=>r.text()).then(say);}
function f(n,d){return Number(n).toFixed(d);}
function setRtc(){
 const t=new Date();
 fetch('/rtc?y='+t.getFullYear()+'&mo='+(t.getMonth()+1)+'&d='+t.getDate()+'&h='+t.getHours()+
  '&mi='+t.getMinutes()+'&s='+t.getSeconds()+'&dw='+(t.getDay()+1)).then(r=>r.text()).then(say);
}
function rtcText(d){
 if(!d.rtc) return '<b style="color:#f87">DS1307 not found on I2C</b>';
 let s='Time: <b>'+d.rtcTime+'</b>';
 if(d.rtcHalted) return s+'<br><b style="color:#fc6">Clock stopped (normal for a new chip). Press the button below.</b>';
 const r=new Date(d.rtcY,d.rtcMo-1,d.rtcD,d.rtcH,d.rtcMi,d.rtcS);
 const diff=Math.round((r-new Date())/1000);
 s+='<br>Ticking: '+(d.rtcTick?'<b style="color:#6e6">yes</b>':'<b style="color:#f87">NO (check crystal)</b>');
 s+='<br>RTC vs phone: <b>'+(diff>0?'+':'')+diff+' s</b>';
 s+='<br>Battery backup: '+(d.rtcKept?'<b style="color:#6e6">memory kept through last power-off</b>':'not tested yet (set time, then unplug and replug)');
 return s;
}
async function tick(){
 // One request at a time, 3 s timeout, next request only after this one finishes.
 const ac=new AbortController(); const to=setTimeout(()=>ac.abort(),3000);
 try{
  const d=await (await fetch('/data',{signal:ac.signal,cache:'no-store'})).json();
  $('v').textContent=f(d.v,1)+' V'; $('i').textContent=f(d.i,3)+' A'; $('p').textContent=f(d.p,1)+' W';
  $('pf').textContent=f(d.pf,3); $('s').textContent=f(d.s,1)+' VA'; $('e').textContent=f(d.kwh,4)+' kWh';
  $('st').innerHTML='State: 0x'+d.state+' ('+d.stateText+')<br>Packets OK: '+d.good+' &middot; bad: '+d.bad+
   ' &middot; last '+d.age+' ms ago<br>RTC DS1307: '+(d.rtc?'found':'NOT found')+
   '<br>Cal V/I/P: '+f(d.calV,4)+' / '+f(d.calI,4)+' / '+f(d.calP,4)+
   '<br>Home WiFi IP: '+d.ip+' ('+d.rssi+' dBm)';
  $('raw').textContent=d.raw;
  $('rtc').innerHTML=rtcText(d);
 }catch(x){}
 clearTimeout(to);
 setTimeout(tick,1000);
}
tick();
</script></body></html>
)HTML";

String stateText(uint8_t st) {
  if (st == 0x55) return "normal";
  if (st == 0xAA) return "chip error";
  if ((st & 0xF0) == 0xF0) {
    String t = "overflow:";
    if (st & 0x08) t += " V";
    if (st & 0x04) t += " I";
    if (st & 0x02) t += " P";
    t += " (normal with no load / no CT)";
    return t;
  }
  return "no data";
}

void handleData() {
  char rawHex[24 * 3 + 1] = "-";
  if (haveRaw) {
    for (int k = 0; k < 24; k++) sprintf(rawHex + k * 3, "%02X ", lastRaw[k]);
  }
  uint32_t age = goodPk ? millis() - lastPkMs : 0;

  String j = "{";
  j += "\"v\":" + String(V, 2);
  j += ",\"i\":" + String(I, 4);
  j += ",\"p\":" + String(P, 2);
  j += ",\"s\":" + String(S, 2);
  j += ",\"pf\":" + String(PF, 3);
  j += ",\"kwh\":" + String(kWh, 5);
  char sb[3]; sprintf(sb, "%02X", lastState);
  j += ",\"state\":\"" + String(sb) + "\"";
  j += ",\"stateText\":\"" + stateText(lastState) + "\"";
  j += ",\"good\":" + String(goodPk);
  j += ",\"bad\":" + String(badPk);
  j += ",\"age\":" + String(age);
  j += ",\"raw\":\"" + String(rawHex) + "\"";
  j += ",\"rtc\":" + String(rtcFound ? "true" : "false");
  char rt[24];
  sprintf(rt, "%04u-%02u-%02u %02u:%02u:%02u", rtcNow.year, rtcNow.mon, rtcNow.day,
          rtcNow.hour, rtcNow.min, rtcNow.sec);
  j += ",\"rtcTime\":\"" + String(rt) + "\"";
  j += ",\"rtcY\":" + String((int)rtcNow.year) + ",\"rtcMo\":" + String((int)rtcNow.mon) +
       ",\"rtcD\":" + String((int)rtcNow.day) + ",\"rtcH\":" + String((int)rtcNow.hour) +
       ",\"rtcMi\":" + String((int)rtcNow.min) + ",\"rtcS\":" + String((int)rtcNow.sec);
  j += ",\"rtcHalted\":" + String(rtcNow.halted ? "true" : "false");
  j += ",\"rtcTick\":" + String(rtcTicking() ? "true" : "false");
  j += ",\"rtcKept\":" + String(rtcKeptAtBoot ? "true" : "false");
  j += ",\"calV\":" + String(calV, 5);
  j += ",\"calI\":" + String(calI, 5);
  j += ",\"calP\":" + String(calP, 5);
  j += ",\"rssi\":" + String(apMode ? 0 : WiFi.RSSI());
  j += ",\"ip\":\"" + String(apMode ? "not connected" : WiFi.localIP().toString().c_str()) + "\"";
  j += "}";
  server.send(200, "application/json", j);
}

void handleCal() {
  String msg;
  if (server.hasArg("reset")) {
    calV = calI = calP = 1.0f;
    msg = "Calibration reset";
  } else if (server.hasArg("v")) {
    float t = server.arg("v").toFloat();
    if (V > 50 && t > 50) { calV *= t / V; msg = "Voltage calibrated"; }
    else msg = "Need mains connected (V > 50)";
  } else if (server.hasArg("i")) {
    float t = server.arg("i").toFloat();
    if (I > 0.2f && t > 0.2f) { calI *= t / I; msg = "Current calibrated"; }
    else msg = "Need a load above 0.2 A";
  } else if (server.hasArg("p")) {
    float t = server.arg("p").toFloat();
    if (P > 50 && t > 50) { calP *= t / P; msg = "Power calibrated"; }
    else msg = "Need a load above 50 W";
  }
  saveCal();
  server.send(200, "text/plain", msg);
}

// ---------- WiFi ----------
void startWiFi() {
  // The device ALWAYS makes its own network "SEM1-Test" (page at http://192.168.4.1)
  // and also joins your home WiFi if it can.
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP("SEM1-Test", "sem1test");
  WiFi.setHostname("sem1");
  WiFi.setSleep(false);            // no modem sleep: faster, smoother page
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("Connecting to WiFi");
  uint32_t t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 20000) {
    delay(250);
    Serial.print(".");
    ledW((millis() / 250) % 2);
  }
  if (WiFi.status() == WL_CONNECTED) {
    apMode = false;
    ledW(true);
    Serial.printf("\nConnected. Open http://%s  (or http://sem1.local)\n",
                  WiFi.localIP().toString().c_str());
  } else {
    // Home WiFi not reachable. Stop trying: while the ESP32 keeps searching for
    // the home network it hops channels, and the SEM1-Test page freezes.
    apMode = true;
    WiFi.setAutoReconnect(false);
    WiFi.disconnect();
    WiFi.mode(WIFI_AP);
    WiFi.softAP("SEM1-Test", "sem1test");
    Serial.println("\nHome WiFi failed. Join 'SEM1-Test' (pass sem1test), open http://192.168.4.1");
  }
}

// ---------- setup / loop ----------
void setup() {
  pinMode(PIN_LED_B, OUTPUT);
  pinMode(PIN_LED_W, OUTPUT);
  ledB(false);
  ledW(false);

  Serial.begin(115200);
  Serial2.begin(4800, SERIAL_8E1, PIN_HLW_RX, PIN_HLW_TX);

  Wire.begin(PIN_SDA, PIN_SCL);
  checkRTC();
  if (rtcFound) rtcKeptAtBoot = rtcReadMagic();

  loadCal();
  startWiFi();

  ArduinoOTA.setHostname("sem1");
  ArduinoOTA.setPassword(OTA_PASS);
  ArduinoOTA.begin();

  server.on("/", []() { server.send_P(200, "text/html", PAGE); });
  server.on("/data", handleData);
  server.on("/cal", handleCal);
  server.on("/kwh", []() { kWh = 0; server.send(200, "text/plain", "Energy reset"); });
  server.on("/rtc", handleRtcSet);
  server.begin();

  lastAvgMs = millis();
}

void loop() {
  ArduinoOTA.handle();
  server.handleClient();

  while (Serial2.available()) feedByte(Serial2.read());

  updateAverages();

  // AP mode: slow blink on the white LED
  if (apMode) ledW((millis() / 1000) % 2);

  static uint32_t lastRtc = 0;
  if (millis() - lastRtc > 500) {
    lastRtc = millis();
    checkRTC();
  }
}
