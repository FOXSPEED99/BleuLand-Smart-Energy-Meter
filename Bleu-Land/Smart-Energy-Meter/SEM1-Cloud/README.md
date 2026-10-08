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
| `devices` | one row per meter: name, firmware, last seen, owner settings (time zone, currency, tariff, alerts) |
| `device_members` | who can see a meter (`owner` or `member`) |
| `invites` | family sharing by e-mail |
| `device_live` | latest live values per meter (the app subscribes to changes) |
| `readings` | 5-minute history: the meter's lifetime kWh counter, average/peak power, voltage |
| `alerts` | high-power and offline alerts |
| `private.device_keys` | SHA-256 hashes of each meter's secret and QR code; not reachable through the API |

## Functions

**Called by the meter** (public key, and it proves itself with its own 32-char secret):

| Function | When | Effect |
|---|---|---|
| `device_hello(p_id, p_secret, p_pop, p_fw, p_hw)` | at boot | registers a new meter, or updates the firmware version |
| `device_push(p_id, p_secret, p_live, p_records)` | every 10 s | live values plus a batch of 5-minute records; returns the highest record number stored |

**Called by the app** (logged-in user):

| Function | Purpose |
|---|---|
| `claim_device(p_id, p_pop, p_name)` | add a meter to my account; needs the QR code from the label |
| `accept_invites()` | join meters shared with my e-mail |
| `get_energy(p_id, from, to, 'hour'\|'day'\|'month')` | kWh per period, in the meter's local time |

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

## Verified (8 Oct 2026, inside a rolled-back transaction)

- A new meter registers, and a wrong secret is rejected for both hello and push.
- An upload stores the records and returns the acked count.
- Anonymous visitors and logged-in strangers see **0** meters.
- A wrong QR code is rejected; the right one makes the user the owner, who then sees the meter and its live values.
- `get_energy` returns the correct kWh: 1600 × 0.1 Wh = 0.16 kWh.
