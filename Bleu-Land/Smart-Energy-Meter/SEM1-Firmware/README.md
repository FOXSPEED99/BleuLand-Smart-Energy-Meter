# SEM-1 production firmware

This is the "real" firmware for the SEM-1, replacing `SEM1-App/reference/SEM1_Test.ino`.
It builds for two boards:

| Target | Board | CT |
|---|---|---|
| `devkit` | Your prototype: ESP32-DevKitC on the current PCB | SCT-013-030 (30 A / 1 V), R14 = 0.44 Ω |
| `c3` | Production: ESP32-C3-WROOM-02 (PCB not made yet) | SCT-013-000 (100 A : 50 mA), R14 = 0.5 Ω |

## What it does (stage 1)

- **Reads the HLW8032.** Packets are found with a sliding window and the checksum, as in the test firmware. Values are averaged every second, and the "no load → I = 0" rule is kept.
- **Energy counter.** The lifetime kWh total never goes backwards and survives power cuts:
  - it's saved every 10 s in the DS1307's battery-backed RAM, which doesn't wear out;
  - and every 5 minutes in the history log.
  - It's calculated from P × dt, the method proven on your bench. The HLW8032's own PF pulse counter is calculated alongside it, so you can compare both against a reference meter. Switch with `energy pf`.
- **5-minute history in flash ("offline buffer").** About **69 days** of records: time, kWh counter, average power, peak power and voltage. When the cloud part is added, the meter uploads these, so no data is lost while the internet is down.
- **Clock.** Gets the time from the internet (NTP) when online and keeps the DS1307 correct. After a power cut with no internet, the DS1307 provides the time. Everything is stored in **UTC**, and the app converts to local time.
- **WiFi setup from the phone over Bluetooth.** Nothing is hard-coded and there's no always-on access point, so the AP+STA freeze from the test firmware can't happen.
- **LEDs as printed on the label:**
  - **ENERGY** (white): one flash per Wh, i.e. 1000 imp/kWh.
  - **WiFi** (blue): link / setup status.
- **Button:**
  - hold 5 s = forget WiFi and go back to phone setup;
  - hold 15 s = also forget the owner.
- **Local web page and JSON API** on your home network, for the app, Home Assistant, and calibration on the bench.
- **Metering in its own high-priority task.** Network work can never make it miss packets. A watchdog restarts the meter if it ever hangs.

Coming in the next stages:

- cloud upload (Supabase)
- linking a meter to an account
- OTA updates from the cloud
- MQTT / Home Assistant

## Why PlatformIO (and not ESP-IDF or the Arduino IDE)

- **You keep writing Arduino-style code.** PlatformIO uses the same Arduino core for ESP32 as your Arduino IDE (version 2.0.17 here), so `Serial`, `WiFi`, `Preferences` and `Wire` all work the same.
- **Every build is identical.** `platformio.ini` locks the exact core and library versions. In the Arduino IDE, anyone's installed versions can differ, which is bad for a product.
- **It handles a real project.** The code is split into many files, and one project builds both boards (DevKit and C3). It also includes a custom flash layout and unit tests that run on your PC.
- **ESP-IDF** (Espressif's own toolkit) gives more control, but it's much harder to learn and none of your Arduino knowledge carries over. We can move to it later if we ever need to; the metering core in `lib/sem1core` is plain C++ and would come along unchanged.

## Install (Windows, one time)

1. Install **VS Code**: https://code.visualstudio.com → Download for Windows → run the installer with the default options.
2. Open VS Code → click the **Extensions** icon on the left (four squares) → search **PlatformIO IDE** → **Install**. Wait until it says it's finished (a few minutes), then restart VS Code.
3. If Windows doesn't see the DevKit's USB port, install the driver for its USB chip. Most DevKitC boards use the **CP210x** chip (Silicon Labs website); some use the **CH340**. The Arduino IDE probably already installed it for you.

## Build and flash the prototype

1. In VS Code: **File → Open Folder…** → pick the `SEM1-Firmware` folder.
2. Wait for PlatformIO to finish loading the project. The first time, it downloads the ESP32 tools (about 500 MB).
3. In the blue bar at the bottom, click the environment name and choose **`env:devkit`**.
4. Plug in the DevKit and click the **→ (Upload)** arrow in the bottom bar.
5. Click the **plug icon (Serial Monitor)**. You'll see something like:

   ```
   SEM-1 firmware 0.1.0 (SEM1-proto-devkit)
   Device SEM1-A1B2C3
   [rtc] DS1307 found, time valid
   [log] ok, next record #1
   [energy] restored 0.000 kWh
   [net] setup mode: BLE name SEM1_A1B2C3
   [net] QR payload: {"ver":"v1","name":"SEM1_A1B2C3","pop":"k7m3x9qa","transport":"ble"}
   ```

> **Calibration carries over.** The settings area sits at the same flash
> address, under the same name (`sem1`, `calV/calI/calP`) as the test
> firmware's, and uploading doesn't erase it. To be safe, write down the
> values from the test page before you flash.

## Connect it to your WiFi (before our app exists)

Our own app will do this later. Until then, Espressif's free test app speaks the same protocol:

1. On your Android phone, install **"ESP BLE Provisioning"** (by Espressif) from the Play Store.
2. Make the QR code for your unit:
   1. Copy the `QR payload` line from the serial monitor.
   2. Open `https://espressif.github.io/esp-jumpstart/qrcode.html?data=` and paste the payload after the `=`.
3. In the app: **Provision New Device → scan the QR** on your PC screen.
4. Pick your home WiFi and type its password. The blue LED blinks fast while it connects, then stays on.
5. The serial monitor prints the meter's address, e.g. `http://192.168.1.57 (http://sem1-a1b2c3.local)`. Open it in a browser on the same WiFi to see live values.

The QR payload is fixed for each unit; it's created on the unit's first boot. In production, it's what gets printed on the front label's "SCAN TO PAIR" code.

## LEDs

| WiFi LED (blue) | Meaning |
|---|---|
| slow blink (1 s on / 1 s off) | waiting for setup from the phone |
| fast blink | connecting to the home WiFi |
| on | connected |
| very fast flicker | button held ≥ 5 s: release now to reset WiFi |
| on + ENERGY on | button held ≥ 15 s: release now for a factory reset |

ENERGY LED (white): one short flash per watt-hour (1000 imp/kWh), like a utility meter.
At 3.6 kW that's one flash per second.

## Calibration

You need a reference meter (or a known resistive load and a good multimeter).

- **Web page:** open the meter's address. In the *Key* box, type the `pop` value; you'll find it in the serial `info` output and in the QR payload. Then enter what the reference shows and press *Set*.
- **Serial monitor:** type `cal v 231.4`, `cal i 8.70` or `cal p 2000`.

Do voltage first, then power, then current, with a steady resistive load (heater, kettle) of 1–3 kW.

To compare the two energy methods, run a load for an hour and read the meter's energy (`info`) against the reference. `info` also shows the result of the other method since boot.

## Serial console commands

Type them in the Serial Monitor at 115200 baud:

```
info                  device status
qr                    QR payload for the front label
cal v|i|p <value>     calibrate to a reference meter reading
cal reset             back to 1.0 / 1.0 / 1.0
energy int|pf         energy from P x dt (default) or the PF pulse counter
time <unix>           set the clock by hand (UTC)
log [n]               last n history records
wifi-reset            forget WiFi, restart into phone setup
factory-reset         also forget the owner
reboot
```

## Local API (home network)

```
GET  /api/live   {"id":"SEM1-A1B2C3","ts":1760000000,"v":231.2,"i":4.351,"p":998.7,"s":1005.9,"pf":0.993,"kwh":12.3456,"ok":true}
GET  /api/info   firmware, WiFi, clock, RTC, HLW8032 packet counters, calibration, log status
POST /api/cal    key=<pop> and one of v= | i= | p= | reset=1 | energy=int|pf
```

## Unit tests (on your PC, no board needed)

To run the tests you also need a C++ compiler on Windows: install **MSYS2** and its `mingw-w64-ucrt-x86_64-gcc` package, then add its `bin` folder to `PATH`. Then, in VS Code: **PlatformIO icon → Project Tasks → native → Advanced → Test**. Or in the PlatformIO terminal:

```
pio test -e native
```

These tests check the HLW8032 decoder, the energy maths and the flash log, including power cuts in the middle of a write. All 15 pass.

## Files

```
platformio.ini            build settings for devkit / c3 / native tests
partitions_sem1.csv       flash layout: 2 x 1.75 MB app slots (for safe OTA) + 392 KB history log
lib/sem1core/             plain C++, no Arduino: HLW8032 decoder, meter maths, flash log
src/board.h               pin maps for both boards
src/config.h              CT / burden values, timings
src/main.cpp              start-up, metering task, clock, history log, button
src/net.cpp               BLE WiFi setup + reconnect
src/local_api.cpp         web page + JSON API
src/rtc_ds1307.cpp        clock + energy backup in RTC RAM
src/settings.cpp          calibration, identity (device ID, QR code, cloud secret)
src/console.cpp           serial commands
src/leds.cpp              LED patterns
test/test_core/           unit tests
```

## For the production PCB (ESP32-C3), hardware requests

1. **Add a user button** from **GPIO9** to GND, reachable from the front (e.g. a small hole for a pin).
   - GPIO9 is also the C3's "boot" pin, so the same button lets you re-flash a unit.
   - Without a button, a customer who changes their WiFi router can't re-pair the meter.
2. **Bring out USB (GPIO18 = D−, GPIO19 = D+)** to a connector or test pads. The C3 has USB built in, so there's no CP2102/CH340 chip to buy, and it's how the factory flashes units.
3. Proposed pins (in `src/board.h`, easy to change):

   | Signal | GPIO |
   |---|---|
   | HLW8032 TX → RX | 3 |
   | WiFi LED (blue) | 6 |
   | ENERGY LED (white) | 7 |
   | SDA / SCL | 4 / 5 |
   | Button | 9 |

   Keep 10 k pull-ups on GPIO2 and GPIO8 (boot strapping pins).
4. **DS1307 is a 5 V chip.** Make sure the I2C pull-ups go to **3.3 V**, not 5 V, because ESP32 pins are not 5 V tolerant. The DS1307 reads 3.3 V as a valid high. A **DS3231** or **PCF8563** would run on 3.3 V and keep much better time; worth considering.
5. The **front label QR** must be printed **per unit** with that unit's QR payload (read it with the `qr` command on the production line).

## Size budget

- C3: 1.53 MB of 1.75 MB (83%).
- DevKit: 1.64 MB (89%).
- Most of this is the Bluetooth stack used for WiFi setup.
- The cloud features of stage 2 should still fit on the C3. The DevKit is only for development.
