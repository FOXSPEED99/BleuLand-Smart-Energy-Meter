// Product constants. Values marked "per unit" are overridden by calibration.
#pragma once
#include <stdint.h>

#include "board.h"

#ifndef SEM1_FW_VERSION
#define SEM1_FW_VERSION "0.1.0"
#endif

// ---------- current transformer + burden (R14) ----------
// KI = 0.001 / (R_burden / CT_turns); the HLW8032 coefficient is 1.0 for a 1 mOhm shunt.
//   Production: SCT-013-000 (100 A : 50 mA, 2000 turns), R14 = 0.5 R  -> KI = 4.0
//   Prototype : SCT-013-030 (30 A / 1 V, 1800 turns, ~62 R inside), R14 = 0.44 R -> KI ~= 4.12
// The values for each board are in board.h:
//   SEM1_CT_TURNS, SEM1_CT_INT_BURDEN (ohms inside the CT, 0 = current-output CT),
//   SEM1_R14_OHMS

// Voltage: 4 x 47k = 188k into ZMPT101B (2 mA:2 mA), 100 R burden -> same
// ratio as the datasheet's 1.88 M / 1 k divider.
constexpr float KV = 1.88f;

constexpr float burdenOhms() {
  return SEM1_CT_INT_BURDEN > 0
             ? (SEM1_R14_OHMS * SEM1_CT_INT_BURDEN) / (SEM1_R14_OHMS + SEM1_CT_INT_BURDEN)
             : SEM1_R14_OHMS;
}
constexpr float KI = 0.001f / (burdenOhms() / SEM1_CT_TURNS);

// ---------- timing ----------
constexpr uint32_t LOG_INTERVAL_S = 300;          // one history record every 5 minutes
constexpr uint32_t ENERGY_BACKUP_MS = 10000;      // energy total -> DS1307 RAM
constexpr uint32_t ENERGY_NVS_BACKUP_MS = 900000; // fallback when no RTC: every 15 min
constexpr uint32_t BUTTON_WIFI_RESET_MS = 5000;   // hold: forget WiFi, start setup
constexpr uint32_t BUTTON_FACTORY_RESET_MS = 15000;  // hold: also forget owner/settings

// Anything before this is treated as "clock not set" (2024-01-01).
constexpr uint32_t MIN_VALID_UNIX = 1704067200;
