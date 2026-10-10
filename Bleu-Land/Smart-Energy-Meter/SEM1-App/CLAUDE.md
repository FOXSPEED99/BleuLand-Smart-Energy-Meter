# SEM-1 Smart Energy Meter: project brief

Read this file fully before doing anything. It is the hand-off from the hardware phase.

## Who you're working with

- **Fox** leads the project. He's a hardware person and new to app or cloud development.
  - He uses Windows, an Android phone, and the Arduino IDE.
  - He wants you to build the software end to end, and to explain each step in plain, simple language: what to install, what to click, what to run.
  - When he says "I want to learn", explain thoroughly instead of just doing it.
- Ask before anything that costs money or is hard to undo. That includes paid cloud plans, app-store accounts (Apple $99/yr, Google $25 once), domain names, and choosing a database or vendor.
- If an important detail is missing, ask. Use short multiple-choice questions where possible.

## The product

- SEM-1 is a single-phase **230 V / 50 Hz whole-house energy monitor**.
- A **split-core current transformer (CT)** clamps around the incoming live wire. It's non-invasive, so no cutting of cables.
- It's built for **production**, not a hobby one-off:

## Hardware (prototype, working and verified)

| Block | Part | Notes |
|---|---|---|
| MCU (prototype) | ESP32-WROOM-32 DevKit | Production plan: **ESP32-C3-WROOM-02** (RISC-V, single core, 4 MB flash). Firmware must target the C3. |
| Metering IC | **HLW8032** | Sends data over UART TX only. Its RX pin is unused. |
| Voltage sense | ZMPT101B 2 mA:2 mA + 4 × 47 k (188 k) + 100 Ω burden | Same ratio as the datasheet's 1.88 M / 1 k divider. |
| Current sense | SCT-013 CT → burden R14 → 1.5 k / C filter → HLW8032 IP/IN | |
| PSU | HLK-5M05 (5 V 1 A), T250 mA fuse, X2 cap, 10D471K MOV, common-mode choke | |
| RTC | DS1307 + 32.768 kHz crystal + CR2032 | I2C address 0x68 |
| LEDs | Blue, white | Active LOW: anode through 330 Ω to 5 V, cathode to GPIO |

**ESP32 DevKit pins:**

| Signal | GPIO |
|---|---|
| HLW8032 TX → 1 k/2 k divider → RX | **GPIO16** (Serial2) |
| LED blue | GPIO19 |
| LED white | GPIO18 |
| I2C SDA | **GPIO23** |
| I2C SCL | GPIO22 |

- There is **no user button** on the board yet, only the DevKit's BOOT (GPIO0).
- If WiFi setup or reset needs a button, flag it as a hardware change for the production PCB.

### HLW8032 protocol

The chip sends **4800 baud, 8E1**, in 24-byte packets that stream back-to-back.

| Byte(s) | Field |
|---|---|
| 0 | State: `0x55` = OK, `0xAA` = chip error, `0xFx` = overflow flags (bit3 V, bit2 I, bit1 P) |
| 1 | Check byte, always `0x5A` |
| 2–4 / 5–7 | Voltage parameter / voltage register |
| 8–10 / 11–13 | Current parameter / current register |
| 14–16 / 17–19 | Power parameter / power register |
| 20 | Data-update flags. bit7 = PF counter carry. |
| 21–22 | PF pulse counter (energy) |
| 23 | Checksum = low byte of the sum of bytes 2..22 |

**Formulas:**

```
V = VolPar / VolReg × KV × calV
I = CurPar / CurReg × KI × calI
P = PowPar / PowReg × KV × KI × calP
S = V × I
PF = P / S
```

- **Sync on packets with a sliding 24-byte window**, checking the 0x5A byte and the checksum. Gap-based sync doesn't work because the packets have no gaps between them.
- **Coefficients:**
  - `KV = 1.88`
  - `KI = 0.001 / (R_burden / CT_turns)`, because the HLW8032 coefficient is 1.0 for a 1 mΩ shunt.
  - Prototype: SCT-013-030 (30 A/1 V, 1800 turns, about 62 Ω internal burden) with R14 = 0.44 Ω → **KI ≈ 4.12**.
  - Production: SCT-013-000 (100 A:50 mA, 2000 turns), R14 = 0.5 Ω → **KI = 4.0**, full scale about 87 A.
- **Noise floor** is about 0.2 A of fake current with no load. If the power register overflows (no real power), report I = 0. Fox measured up to ~20 W of fake power with the clamp around nothing (Oct 2026), so firmware 0.4.1 reads anything under 25 W as 0 W / 0 A and counts no energy (stays on down to 20 W once a load is seen; `NO_LOAD_W` in config.h). Loads under ~25 W alone can't be measured with this CT and board.
- **Energy:** the test firmware integrates P·dt. For production, consider the PF pulse counter. The commonly used formula is pulses per kWh = 1e9 × 3600 / (PowPar × KV × KI). Verify it against the datasheet.
- **Direction:** the HLW8032 is assumed to give power **magnitude only** (no import/export sign). Verify before promising any solar or export features.

**Bench results (uncalibrated):**

- Voltage was within 0.3% of a multimeter.
- A 33 W phone charger read 27 W at PF 0.50.
- A 400 W blower read 324 W at PF 0.995.
- Fine calibration against a reference meter is still to do.

## Existing firmware (reference only)

`reference/SEM1_Test.ino` is the Arduino IDE test firmware. It's proven on the prototype and does the following:

- HLW8032 parser
- 1 s averaging
- Calibration factors `calV`/`calI`/`calP` saved in NVS (namespace `sem1`)
- DS1307 read/write with a battery-backup test (RAM marker at 0x08)
- A web page that polls `/data` JSON
- An always-on AP `SEM1-Test` / `sem1test` at 192.168.4.1
- ArduinoOTA (host `sem1`, password `sem1ota`)

**Lessons learned:**

1. **ESP32 AP+STA freezes:** when the station can't find its network, the ESP32 keeps scanning channels and the AP freezes. Stop STA retries when it fails, or use proper provisioning.
2. **Browser polling must be chained**, with `setTimeout` after each response plus a timeout. Never use `setInterval`, or requests pile up against the single-threaded WebServer.

The production firmware should be a proper rewrite. PlatformIO or ESP-IDF is acceptable, but explain the choice to Fox.

## What Fox asked for

> "Build a full app that works on every device for our actual product."

Expected features for this product category:

- Live power, voltage, current and PF
- Today / week / month / year energy, with history charts
- Cost in local currency with a tariff setting
- Alerts: high usage, device offline
- Several devices per account, and sharing with family
- Easy WiFi onboarding from the phone (no hard-coding SSIDs)
- OTA firmware updates pushed to devices
- Data kept when the internet is down; the RTC and flash buffer exist for this
- Optional: Home Assistant / MQTT integration, which is a big selling point

Platforms: **Android, iOS and web/desktop**, ideally from **one codebase**.

## Decisions and status (updated by Claude)

Fox chose (Oct 2026):

- **Cloud:** Supabase (org "BLEU LAND"), free plan. Project **bleuland-energy** (ref `rmgzpxwpowwzqewmiyaw`, eu-central-1 Frankfurt, closest to Syria). An empty project "sem1" (ref `qzebqybpcjcuownytabd`, Mumbai) was created by mistake and is paused; Fox can delete it. Schema applied and verified; see `../SEM1-Cloud/README.md` (URL, publishable key, functions). The Supabase MCP `apply_migration` cancels any statement containing DELETE even when Fox approves, so keep DELETE out of migrations (`../SEM1-Cloud/pending/` holds SQL for Fox to paste in the dashboard). This sandbox can't reach supabase.co (proxy 403); Fox confirmed it's reachable from Syria without a VPN. Default tariff: 300 kWh at 6, then 14 new SYP/kWh per 2-month cycle. Ask before any paid plan.
- **Market:** **Syria** first (not the Gulf): currency SYP, time zone Asia/Damascus, tariff brackets entered by the user (no guessed prices). App **English only** for now. App name **BleuLand Energy**, **dark theme only**.
- **Scope (Fox):** the meter measures the whole house's consumption from the city grid, i.e. what's on the electricity bill. No generator/solar features.
- **App:** Flutter (Android, iOS, web, desktop from one codebase).
- **Firmware:** built with the **Arduino IDE** (Fox's choice, replacing PlatformIO) on board package esp32 **3.x** (tested 3.3.12; Fox has 3.x; 2.0.17 also compiles via the `ESP_ARDUINO_VERSION_MAJOR` shims in net.cpp; verified builds on 2.0.17, 3.3.4, 3.3.12). net.cpp defines `extern "C" bool btInUse(){return true;}` (plus `esp32-hal-alloc-ble-mem.h` only when it exists, 3.3.9+) so no core version frees BLE memory at boot; without it the 2.0.17 DevKit build linked the core's weak `false` version and BLE setup would have failed, + ArduinoJson 7.x. Sketch: `../SEM1-Firmware/SEM1_Firmware/SEM1_Firmware.ino` (only setup()/loop() calling sem1Setup()/sem1Loop() in main.cpp); all code files sit flat in the sketch folder so Fox sees them as IDE tabs (keep it that way); board and CT are picked automatically from `CONFIG_IDF_TARGET_*`; the sketch-folder `partitions.csv` is used automatically; its app slots (2 x 0x1F0000) equal the IDE's "No FS 4MB (2MB APP x2)" scheme (Fox must select it) so the IDE size check is exact; no coredump partition (dropped for room) and no mDNS (removed, ~37 KB). Stage 2 overflowed "Minimal SPIFFS" on Fox's 3.x core (1,985,389 > 1,966,080), hence this layout. Sizes on 3.3.12: C3 1.57 MB (77%), DevKit 1.92 MB (94%) of 2,031,616 bytes. PC tests: `sh test/run_tests.sh`.
- **Order:** firmware first, then cloud, then app.

Firmware stage 1 is done (see `../SEM1-Firmware/README.md`):

- metering task
- energy counter backed up in DS1307 RAM
- 5-min history ring in a raw flash partition (64 KB, ~11 days)
- NTP + RTC clock (UTC)
- ESP BLE provisioning (security 1, PoP from the QR) with the `sem1-claim` endpoint for account linking
- LEDs per the front label: white = ENERGY 1000 imp/kWh, blue = WiFi
- button 5 s / 15 s reset
- local API (`/api/live`, `/api/info`, `/api/cal`)
- serial console
- WiFi saved by other firmware is ignored: NVS flag `wifiok` is set only on PROV_CRED_SUCCESS; without it the stored STA config is erased and BLE setup starts (Fox's DevKit had the test sketch's network saved and never entered setup)
- core 3.x: net::begin() must call `WiFi.STA.begin(false)` (not `wifiLowLevelInit`) or the sketch never gets ARDUINO_EVENT_WIFI_STA_GOT_IP and the hostname stays "espressif" (seen on Fox's DevKit: joined the hotspot, firmware kept retrying); loop() also falls back to WiFi.status()
- 15 PC unit tests
- stage 2 (cloud): `cloud.cpp` task: device_hello at boot, device_push every 10 s (live + up to 48 log records; upload cursor `uploadedSeq` kept in DS1307 RAM), TLS with 11 pinned root CAs in `cloud_certs.h`, backoff to 5 min, AuthError retries every 10 min, LED CloudDown. Sizes: C3 1.61 MB (82%), DevKit on core 3.3.12 1.96 MB (99.5%; recommend Fox moves dev to an ESP32-C3 DevKit before OTA)

App: `../BleuLand-Energy-App` (Flutter 3.47.6, Riverpod 3, go_router, supabase_flutter, fl_chart, universal_ble + esp_provisioning_ble). Demo mode (simulated Syrian home) + cloud mode. 14 tariff tests. Web build screenshotted in headless Chromium for design review (`flutter build web --no-web-resources-cdn`). Do NOT use flutter_blue_plus (paid licence for companies). APK built by `.github/workflows/app-android.yml`. Chart colours validated with the dataviz validator (series #139C7C on #171B20; brand #1FC8A0 for highlights; amber #FAB219 only for over-tier with icon+label).

Next stages:

1. Supabase schema + device ingest (device authenticates with its per-unit secret, records keyed by device + timestamp) + upload of the flash log.
2. Flutter app with BLE onboarding (QR → WiFi → claim code), live view, history, tariff/cost, alerts, sharing.
3. ~~OTA from the cloud~~ done (fw 0.3.0): GitHub Actions `firmware.yml` builds both boards with core 3.3.12 and publishes via `SEM1-Firmware/tools/publish.sh` (needs repo secret `SUPABASE_SECRET_KEY`; main → stable, other branches → beta; a version is published once, so bump `SEM1_FW_VERSION`). Owner taps Update in the app (`request_update`); `device_push` returns `ota`; meter downloads into the spare slot (Update lib + MD5), reports via `device_ota`, restarts; `verifyRollbackLater()` keeps it on probation until cloud hello succeeds (10-min timeout → bootloader rollback). Fox chose: updates only when the owner taps, also for his own (beta-channel) meter.
4. ~~Changing the WiFi~~ done (fw 0.4.0): "setup window" = restart into the normal BLE provisioning with the working WiFi backed up in NVS (`wbs`/`wbp`) and restored if no new WiFi succeeds in time or the power fails mid-window. Opened by the app (`request_wifi_setup` → `device_push` returns `wifi_setup`), by 2 min without the saved WiFi (auto, 4-min window, repeats), or the button held 5 s / console `wifi-setup` (10 min). App: Settings → WiFi (`wifi_screen.dart`), "Changed your WiFi?" on the offline Home card; BLE code from `get_setup_code` (stored at claim; Fox's stored) or typed once. Shared BLE pieces: `MeterLink` in ble_setup.dart, `setup_widgets.dart`.
5. MQTT / Home Assistant.

Open hardware items for the C3 PCB:

- user button on GPIO9
- USB pins
- I2C pull-ups to 3.3 V
- per-unit QR on the label
