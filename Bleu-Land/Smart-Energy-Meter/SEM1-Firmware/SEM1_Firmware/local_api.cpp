#include "local_api.h"

#include <ArduinoJson.h>
#include <WebServer.h>
#include <WiFi.h>

#include "app.h"
#include "board.h"
#include "cloud.h"
#include "config.h"
#include "net.h"
#include "settings.h"

namespace {
WebServer server(80);

void sendJson(const JsonDocument& doc, int code = 200) {
  String out;
  serializeJson(doc, out);
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Cache-Control", "no-store");
  server.send(code, "application/json", out);
}

void handleLive() {
  LiveSnapshot l = app::snapshot();
  JsonDocument d;
  d["id"] = settings::identity().deviceId;
  d["ts"] = (uint32_t)app::now();
  d["v"] = serialized(String(l.reading.v, 1));
  d["i"] = serialized(String(l.reading.i, 3));
  d["p"] = serialized(String(l.reading.p, 1));
  d["s"] = serialized(String(l.reading.s, 1));
  d["pf"] = serialized(String(l.reading.pf, 3));
  d["kwh"] = serialized(String(l.totalWh / 1000.0, 4));
  d["ok"] = l.reading.samples > 0;
  sendJson(d);
}

void handleInfo() {
  const Identity& id = settings::identity();
  const Settings& s = settings::get();
  LiveSnapshot l = app::snapshot();
  JsonDocument d;
  d["id"] = id.deviceId;
  d["fw"] = SEM1_FW_VERSION;
  d["hw"] = SEM1_HW_NAME;
  d["mac"] = WiFi.macAddress();
  d["ip"] = net::ip();
  d["host"] = net::hostname() + ".local";
  d["rssi"] = net::rssi();
  d["uptime"] = millis() / 1000;
  d["heap"] = ESP.getFreeHeap();
  d["time"] = (uint32_t)app::now();
  d["timeSrc"] = app::timeSourceName();

  JsonObject rtc = d["rtc"].to<JsonObject>();
  rtc["present"] = app::rtc().present();
  rtc["halted"] = app::rtc().halted();
  rtc["keptAtBoot"] = app::rtc().keptAtBoot();

  JsonObject h = d["hlw"].to<JsonObject>();
  h["good"] = l.goodPackets;
  h["bad"] = l.badPackets;
  h["ageMs"] = l.packetAgeMs;
  char hex[24 * 3 + 1] = "-";
  if (l.haveRaw)
    for (int k = 0; k < 24; k++) snprintf(hex + k * 3, 4, "%02X ", l.raw[k]);
  h["raw"] = hex;

  JsonObject c = d["cal"].to<JsonObject>();
  c["v"] = s.calV;
  c["i"] = s.calI;
  c["p"] = s.calP;
  c["kv"] = KV;
  c["ki"] = KI;
  d["energySrc"] = s.energySource == sem1::EnergySource::PfPulses ? "pf" : "int";
  d["altKwhBoot"] = serialized(String(l.altWhBoot / 1000.0, 5));

  JsonObject lg = d["log"].to<JsonObject>();
  lg["next"] = app::log().nextSeq();
  lg["oldest"] = app::log().oldestSeq();
  lg["capacity"] = app::log().capacity();
  lg["uploaded"] = app::uploadedSeq();
  JsonObject cl = d["cloud"].to<JsonObject>();
  cl["state"] = cloud::stateName();
  cl["claimed"] = cloud::claimed();
  cl["lastOk"] = cloud::lastOkUnix();
  cl["error"] = cloud::lastError();
  sendJson(d);
}

void handleCal() {
  JsonDocument d;
  if (server.arg("key") != settings::identity().pop) {
    d["msg"] = "Wrong key (it's the 'pop' value from the label QR / serial 'info')";
    sendJson(d, 403);
    return;
  }
  String msg = "Nothing to do";
  if (server.hasArg("reset")) msg = app::resetCalibration();
  else if (server.hasArg("v")) msg = app::calibrate('v', server.arg("v").toFloat());
  else if (server.hasArg("i")) msg = app::calibrate('i', server.arg("i").toFloat());
  else if (server.hasArg("p")) msg = app::calibrate('p', server.arg("p").toFloat());
  else if (server.arg("energy") == "pf") msg = app::setEnergySource(sem1::EnergySource::PfPulses);
  else if (server.arg("energy") == "int") msg = app::setEnergySource(sem1::EnergySource::Integrated);
  d["msg"] = msg;
  sendJson(d);
}

// Bench page. Polling is chained (next request only after the previous one
// finished, with a timeout) so requests never pile up on the device.
const char PAGE[] PROGMEM = R"HTML(<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>SEM-1</title>
<style>
body{font-family:system-ui,sans-serif;background:#1b1d21;color:#e8e8e8;margin:0;padding:16px;max-width:560px}
h1{font-size:20px;margin:0 0 12px}.g{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.c{background:#26292f;border-radius:10px;padding:12px}.l{font-size:12px;color:#9aa}.v{font-size:26px;font-weight:600}
.s{font-size:13px;color:#bbb;margin-top:14px;line-height:1.6}code{font-size:12px;word-break:break-all;color:#8fd}
input{width:90px;padding:6px;border-radius:6px;border:1px solid #444;background:#111;color:#eee}
button{padding:6px 10px;border-radius:6px;border:0;background:#1fc8a0;color:#111;font-weight:600}.row{margin:6px 0}
</style></head><body><h1>SEM-1 <span id="id" style="color:#9aa;font-weight:400"></span></h1>
<div class="g">
<div class="c"><div class="l">Voltage</div><div class="v" id="v">-</div></div>
<div class="c"><div class="l">Current</div><div class="v" id="i">-</div></div>
<div class="c"><div class="l">Active power</div><div class="v" id="p">-</div></div>
<div class="c"><div class="l">Power factor</div><div class="v" id="pf">-</div></div>
<div class="c"><div class="l">Apparent power</div><div class="v" id="s">-</div></div>
<div class="c"><div class="l">Energy (lifetime)</div><div class="v" id="e">-</div></div></div>
<div class="s" id="st"></div><div class="s">Last packet:<br><code id="raw">-</code></div>
<div class="s"><b>Calibrate</b> (enter what the reference meter shows)
<div class="row">Key <input id="key" placeholder="from label"></div>
<div class="row">Voltage <input id="cv" placeholder="230.0"> V <button onclick="cal('v','cv')">Set</button></div>
<div class="row">Current <input id="ci" placeholder="8.70"> A <button onclick="cal('i','ci')">Set</button></div>
<div class="row">Power <input id="cp" placeholder="2000"> W <button onclick="cal('p','cp')">Set</button></div>
<div class="row"><button onclick="post('reset=1')">Reset calibration</button>
<button onclick="post('energy=int')">Energy: P&middot;dt</button> <button onclick="post('energy=pf')">Energy: PF pulses</button></div></div>
<div class="s" id="msg"></div>
<script>
const $=id=>document.getElementById(id),f=(n,d)=>Number(n).toFixed(d);
function post(q){fetch('/api/cal?key='+encodeURIComponent($('key').value)+'&'+q,{method:'POST'})
 .then(r=>r.json()).then(j=>$('msg').textContent=j.msg).catch(e=>$('msg').textContent=e);}
function cal(k,id){const x=$(id).value;if(x)post(k+'='+encodeURIComponent(x));}
async function get(u){const ac=new AbortController(),t=setTimeout(()=>ac.abort(),3000);
 try{return await (await fetch(u,{signal:ac.signal,cache:'no-store'})).json();}finally{clearTimeout(t);}}
let n=0;
async function tick(){
 try{
  const d=await get('/api/live');
  $('id').textContent=d.id;$('v').textContent=f(d.v,1)+' V';$('i').textContent=f(d.i,3)+' A';
  $('p').textContent=f(d.p,1)+' W';$('pf').textContent=f(d.pf,3);$('s').textContent=f(d.s,1)+' VA';
  $('e').textContent=f(d.kwh,3)+' kWh';
  if(n++%5==0){const x=await get('/api/info');
   $('st').innerHTML='FW '+x.fw+' &middot; '+x.hw+'<br>Packets OK '+x.hlw.good+' &middot; bad '+x.hlw.bad+
   ' &middot; last '+x.hlw.ageMs+' ms ago<br>Clock: '+(x.time?new Date(x.time*1000).toLocaleString():'not set')+
   ' ('+x.timeSrc+') &middot; RTC '+(x.rtc.present?'ok':'MISSING')+
   '<br>Cal V/I/P '+f(x.cal.v,4)+' / '+f(x.cal.i,4)+' / '+f(x.cal.p,4)+' &middot; energy from '+x.energySrc+
   ' (other method since boot '+x.altKwhBoot+' kWh)<br>History log: next #'+x.log.next+' of '+x.log.capacity+
   '<br>WiFi '+x.ip+' ('+x.rssi+' dBm) &middot; free heap '+x.heap+
   '<br>Cloud: '+x.cloud.state+(x.cloud.claimed?' (in an account)':' (not added to an account yet)')+
   ' &middot; uploaded to #'+x.log.uploaded+(x.cloud.error&&x.cloud.state!='ok'?'<br>'+x.cloud.error:'');
   $('raw').textContent=x.hlw.raw;}
 }catch(e){}
 setTimeout(tick,1000);
}
tick();
</script></body></html>)HTML";
}  // namespace

namespace localApi {

void begin() {
  server.on("/", HTTP_GET, []() { server.send_P(200, "text/html", PAGE); });
  server.on("/api/live", HTTP_GET, handleLive);
  server.on("/api/info", HTTP_GET, handleInfo);
  server.on("/api/cal", HTTP_POST, handleCal);
  server.onNotFound([]() { server.send(404, "text/plain", "not found"); });
  server.begin();
}

void loop() { server.handleClient(); }

}  // namespace localApi
