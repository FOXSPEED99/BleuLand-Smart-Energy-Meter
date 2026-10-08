# BleuLand Energy: the SEM-1 app

One Flutter codebase builds the **Android**, **iOS** and **web** versions. It has a dark design, with the teal and charcoal colours of the meter's front label.

## Screens

| Screen | What it shows |
|---|---|
| **Welcome** | Create account · Sign in · **Try the demo** (a simulated Syrian home; no meter needed) |
| **Home** | Live power with a usage ring; voltage, current and power factor; **this bill** in SYP with the cheap-block progress bar and an *"at this pace"* forecast; today's kWh and cost vs yesterday; power over the last 24 h |
| **History** | Day / Week / Month / Year charts; total, average and peak; tap a bar for its value |
| **Alerts** | High-usage alert (slider), offline alert, and the list of past alerts |
| **Settings** | Meter info, name, **electricity price** (blocks, 1- or 2-month bills, billing day, currency), **share with family** by e-mail, add a meter, sign out |
| **Add a meter** | Scan the QR on the label → the app sends your WiFi to the meter over Bluetooth → links it to your account → name it |

**Default price (Syria, households):** the first 300 kWh of each 2-month bill cost 6 SYP/kWh, and everything above costs 14 SYP/kWh (new Syrian pounds, Ministry of Energy, Nov 2025). Each owner can change it.

## Get it on your Android phone (no tools needed)

1. On GitHub, open the repository → **Actions** tab → **"App: Android APK"** → the newest green run.
2. At the bottom, under **Artifacts**, download **BleuLand-Energy-APK** (a .zip), and unzip it to get `app-release.apk`.
3. Copy it to your phone and open it. Android asks to allow *"install unknown apps"* for your file manager: allow it once.

GitHub builds a new APK automatically whenever the app code changes.

> This APK is signed with a development key, which is fine for testing. Publishing on Google Play needs a proper upload key and a developer account ($25 once); we'll set that up together when you're ready.

## Change the code on your PC (optional)

1. Install Flutter: https://docs.flutter.dev/get-started/install/windows (choose **Android**). It also installs Android Studio and the SDK.
2. In a terminal, inside this folder:

   ```
   flutter pub get
   flutter run          # with your phone connected by USB (developer mode on)
   flutter test         # 14 bill-calculation tests
   flutter build apk    # makes build/app/outputs/flutter-apk/app-release.apk
   ```

## How it's built

```
lib/
  main.dart, app.dart         start-up, navigation (bottom tabs), login redirect
  theme/                      design tokens (colours, spacing, type) + Material theme
  core/tariff.dart            tiered bill maths and billing periods (unit tested)
  core/format.dart            how numbers are written (W/kW, kWh, SYP)
  data/                       models, cloud repository (Supabase), demo repository, app state
  widgets/                    cards, status pills, bill progress bar, charts
  features/                   one folder per screen
test/tariff_test.dart         bill calculation tests
```

- **Cloud:** Supabase project `bleuland-energy` (Frankfurt). See `../SEM1-Cloud/README.md`. Live values arrive by real-time subscription, about every 10 s.
- **Bluetooth setup:** `esp_provisioning_ble` (Espressif's protocol, MIT licence) over `universal_ble` (BSD licence, free for companies).
  - `flutter_blue_plus` was **not** used: it needs a paid licence for companies.
- **Charts:** `fl_chart`. Colours were checked with a colour-blindness and contrast validator:
  - chart teal `#139C7C` on card `#171B20`;
  - amber only for "above the cheap block", always with an icon and a label.
- **Font:** Poppins (the label's typeface), bundled, so it works offline.

## Still to do

- Push notifications for alerts (needs Firebase; free).
- Arabic language.
- Over-the-air firmware updates from the app.
- E-mail delivery: Supabase's built-in e-mail service only sends a few messages per hour. Before launch, connect a mail provider (e.g. Resend, which has a free tier).
