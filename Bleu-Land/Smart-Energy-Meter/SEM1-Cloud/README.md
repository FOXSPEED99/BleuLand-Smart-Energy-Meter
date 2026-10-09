# BleuLand Energy cloud (Supabase)

| | |
|---|---|
| Project | **bleuland-energy** (`rmgzpxwpowwzqewmiyaw`), free plan |
| Region | eu-central-1 (Frankfurt), the closest region to Syria |
| URL | `https://rmgzpxwpowwzqewmiyaw.supabase.co` |
| Public key | `sb_publishable_2_MDRTqxogkVNA97djRs3Q_J3PrFZ7_` (safe to ship in the app and firmware; every table is protected by row-level security) |

Never put the **secret / service_role** key in the app or firmware.

## What's in the database

| Table | What it holds |
|---|---|
| `devices` | one row per meter: name, firmware, last seen, owner settings (time zone, currency, tariff, alerts, normal voltage range, default 200–230 V) |
| `device_members` | who can see a meter (`owner` or `member`) |
| `invites` | family sharing by e-mail |
| `device_live` | latest live values per meter, plus today's lowest/highest voltage (the app subscribes to changes) |
| `volt_days` | lowest and highest mains voltage per day, with the time each happened |
| `firmware_releases` | published firmware per board (`hw`), version, `beta`/`stable`, download URL, size, MD5. Written only by GitHub Actions (secret key); files live in the public `firmware` storage bucket |
| `readings` | 5-minute history: the meter's lifetime kWh counter, average/peak power, voltage |
| `alerts` | high-power, offline, low-voltage and high-voltage alerts (`severity` 2 = more than 10 V outside the range) |
| `private.device_keys` | SHA-256 hashes of each meter's secret and QR code; not reachable through the API |

## Functions

**Called by the meter** (public key, and it proves itself with its own 32-char secret):

| Function | When | Effect |
|---|---|---|
| `device_hello(p_id, p_secret, p_pop, p_fw, p_hw)` | at boot | registers a new meter, or updates the firmware version |
| `device_ota(p_id, p_secret, status, error)` | during an update | reports `downloading` / `installing` / `failed` |
| `device_push(p_id, p_secret, p_live, p_records)` | every 10 s (every 2 s while an app is watching) | live values (with the lowest/highest 1-s voltage since the last upload) plus a batch of 5-minute records; keeps the daily voltage extremes and raises voltage alerts; returns the highest record number stored and `fast` (an app is watching) |

**Called by the app** (logged-in user):

| Function | Purpose |
|---|---|
| `claim_device(p_id, p_pop, p_name)` | add a meter to my account; needs the QR code from the label |
| `accept_invites()` | join meters shared with my e-mail |
| `get_energy(p_id, from, to, 'hour'\|'day'\|'month')` | kWh per period, in the meter's local time |
| `firmware_status(p_id)` | installed version, newest one this meter may install, update progress |
| `request_update(p_id)` / `cancel_update(p_id)` | owner only: start an update / cancel one the meter hasn't picked up |
| `request_wifi_setup(p_id)` | owner: ask an online meter to open Bluetooth setup to change its WiFi (handed to it once, valid 2 min) |
| `get_setup_code(p_id)` | owner: the label code needed for Bluetooth setup (kept by `claim_device` in `private.device_setup_codes`) |
| `watch_device(p_id)` | "I'm looking at live values": the meter uploads every 2 s for the next 45 s (the app calls it every 25 s) |

**Voltage alerts:** outside the owner's range for 60 s → alert; more than 10 V outside → serious (high voltage at once, without waiting). An alert closes when the voltage is back inside with 2 V to spare, so it doesn't flap at the limit. Readings below 100 V (no mains, e.g. a bench supply) are ignored.

## Default tariff (Syria, households)

Source: Ministry of Energy decision of 30 Oct 2025, in force since 1 Nov 2025.

| Block (per 2-month billing cycle) | Price |
|---|---|
| first **300 kWh** | **6 SYP/kWh** |
| above 300 kWh | **14 SYP/kWh** |

- Prices are in **new Syrian pounds**, as published by SANA. 1 new pound = 100 old pounds, so the same prices are 600 and 1,400 in old pounds.
- Each owner can change all of it in the app.

## Migrations

- `supabase/migrations/` holds exactly what is applied, in order.
- `pending/release_device.sql` (the owner gives a meter away) is not applied yet. The migration tool refuses statements containing `DELETE`, so paste it into **Dashboard → SQL Editor → Run** when you need it.

**Updates over WiFi:** `device_push` hands the meter `{"ota": {version, url, size, md5}}` once the owner has requested an update. `device_hello` after the restart closes it: new version running → `done`; old version after `installing` → `failed` (the chip rolled back); restarted during the download → retried, 3 times at most. Meters have `fw_channel` `stable` (default) or `beta` (also sees test builds; Fox's SEM1-8B6204 is beta).

## Verified (9 Oct 2026, rolled back): changing the WiFi

Claim keeps the setup code; owner reads it, strangers get nothing; WiFi name stored and kept when a push doesn't send it; a request is handed to the meter exactly once; a request older than 2 minutes is ignored; strangers can't request.

## Verified (9 Oct 2026, rolled back): updates over WiFi

Stable meter on the newest stable → up to date, request refused; beta meter → sees 0.3.1; request → push hands over URL/size/MD5; while downloading → not handed again; restart on 0.3.1 → `done`; rollback → `failed` with a plain message; power cut mid-download → back to `requested`; cancel works; wrong secret and strangers refused.

## Verified (9 Oct 2026, rolled back): voltage and fast mode

Normal → no alert; app watching → `fast: true`; low under 60 s → no alert; low over 60 s → alert (severity 1); 184.5 V → same alert upgraded to severity 2; 201 V → still "low" (2 V margin); 215 V → alert closed; 245 V spike → serious high-voltage alert at once; 0.8 V → ignored; daily lowest/highest stored.

## Verified (8 Oct 2026, inside a rolled-back transaction)

- A new meter registers, and a wrong secret is rejected for both hello and push.
- An upload stores the records and returns the acked count.
- Anonymous visitors and logged-in strangers see **0** meters.
- A wrong QR code is rejected; the right one makes the user the owner, who then sees the meter and its live values.
- `get_energy` returns the correct kWh: 1600 × 0.1 Wh = 0.16 kWh.
