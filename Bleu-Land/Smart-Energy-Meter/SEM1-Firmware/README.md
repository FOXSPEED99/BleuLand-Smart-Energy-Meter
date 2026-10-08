# SEM-1 production firmware

This is the "real" firmware for the SEM-1, replacing `SEM1-App/reference/SEM1_Test.ino`.
It builds for two boards:

| Arduino IDE board (Tools > Board) | Hardware | CT |
|---|---|---|
| **ESP32 Dev Module** | Your prototype: ESP32-DevKitC on the current PCB | SCT-013-030 (30 A / 1 V), R14 = 0.44 Ω |
| **ESP32C3 Dev Module** | Production: ESP32-C3-WROOM-02 (PCB not made yet) | SCT-013-000 (100 A : 50 mA), R14 = 0.5 Ω |

The firmware picks the right pins and CT values from the board you select; you don't edit anything.

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

## Arduino IDE setup (one time)

You already have the Arduino IDE. Two things to add:

1. **ESP32 board package, version 2.0.17.**
   1. **Tools → Board → Boards Manager…**, search **esp32**.
   2. In the entry **"esp32 by Espressif Systems"**, open the version drop-down, pick **2.0.17** and click **Install**. If a 3.x version is installed, this replaces it.
   3. Why exactly 2.0.17: version 3.x changed the Bluetooth WiFi-setup code. If the wrong version is installed, the sketch stops with an error telling you to install 2.0.17.
2. **ArduinoJson library.** **Sketch → Include Library → Manage Libraries…**, search **ArduinoJson** (by Benoit Blanchon), install the newest **7.x**.

Your old test firmware also builds fine on 2.0.17.

## Build and flash the prototype

1. **File → Open…** → open `SEM1-Firmware/SEM1_Firmware/SEM1_Firmware.ino`.
   - You'll only see one tab with instructions. The real code is in the `src` folder next to it, and the IDE compiles it automatically.
   - To read or edit the code, open those files in any text editor; Notepad++ or VS Code are nicer than Notepad.
2. In the **Tools** menu set:
   - **Board:** "ESP32 Dev Module" (under esp32)
   - **Partition Scheme:** "Minimal SPIFFS (1.9MB APP with OTA/190KB SPIFFS)"
   - **Port:** your DevKit's COM port

   Why the Partition Scheme matters: it only raises the IDE's size limit. The firmware is about 1.6 MB, which doesn't fit the IDE's default 1.2 MB limit. The flash layout actually used is our own `partitions.csv` in the sketch folder, which the IDE picks up automatically.
3. Click **Upload (→)**.
   - The first compile takes a few minutes; after that it's faster.
   - If the upload doesn't start, hold the DevKit's BOOT button while it says "Connecting…".
4. Open **Tools → Serial Monitor**, set **115200 baud**, and press the DevKit's EN (reset) button. You'll see something like:

   ```
   SEM-1 firmware 0.1.0 (SEM1-proto-devkit)
   Device SEM1-A1B2C3
   [rtc] DS1307 found, time valid
   [log] ok, next record #1
   [energy] restored 0.000 kWh
   [net] setup mode: BLE name SEM1_A1B2C3
   [net] QR payload: {"ver":"v1","name":"SEM1_A1B2C3","pop":"k7m3x9qa","transport":"ble"}
   ```

5. For commands, set the Serial Monitor's line-ending drop-down to **"Newline"**, type `help` and press Enter.

For the **ESP32-C3** later:
- Board **"ESP32C3 Dev Module"**
- the same Partition Scheme
- **USB CDC On Boot: "Enabled"** (otherwise the Serial Monitor stays empty)
- **Flash Mode: "DIO"**

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

## Unit tests (optional, on a PC, no board needed)

The decoder, energy maths and flash log (including power cuts in the middle of a write) are covered by 15 tests. I run them after every change; you don't need to. If you want to:
1. Install a C++ compiler. On Windows: **MSYS2** with the package `mingw-w64-ucrt-x86_64-gcc`, or WSL.
2. Run `sh test/run_tests.sh`.

## Files

```
SEM1_Firmware/SEM1_Firmware.ino   open this in the Arduino IDE (instructions only)
SEM1_Firmware/partitions.csv      flash layout: 2 x 1.75 MB app slots (for safe OTA) + 392 KB history log
SEM1_Firmware/src/
  main.cpp          setup()/loop(): start-up, metering task, clock, history log, button
  board.h           pin maps + CT values for both boards
  config.h          timings and front-end coefficients
  hlw8032.cpp       HLW8032 packet decoder          (plain C++, unit tested)
  meter.cpp         1 s averages + energy counter   (plain C++, unit tested)
  datalog.cpp       history ring buffer in flash    (plain C++, unit tested)
  net.cpp           BLE WiFi setup + reconnect
  local_api.cpp     web page + JSON API
  rtc_ds1307.cpp    clock + energy backup in RTC RAM
  settings.cpp      calibration, identity (device ID, QR code, cloud secret)
  console.cpp       serial commands
  leds.cpp          LED patterns
test/               PC unit tests
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

- C3: 1.53 MB of its 1.75 MB slot (83%).
- DevKit: 1.64 MB (89%).
- The IDE shows a percentage of 1.9 MB; ignore that, the real limit is 1.75 MB. If the firmware ever grows past it, the meter prints a loud warning at start-up.
- Most of this is the Bluetooth stack used for WiFi setup.
- The cloud features of stage 2 should still fit on the C3. The DevKit is only for development.
