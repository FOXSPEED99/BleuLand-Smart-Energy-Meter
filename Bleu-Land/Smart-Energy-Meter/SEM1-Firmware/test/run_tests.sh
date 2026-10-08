#!/bin/sh
# Builds and runs the PC unit tests for the metering core (no board needed).
# Needs g++ (Linux/macOS, or MSYS2 / WSL on Windows).
set -e
cd "$(dirname "$0")"
SRC=../SEM1_Firmware
g++ -std=gnu++17 -Wall -Wextra -I. -I"$SRC" \
  "$SRC/hlw8032.cpp" "$SRC/meter.cpp" "$SRC/datalog.cpp" test_core.cpp -o test_core
./test_core
