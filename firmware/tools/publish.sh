#!/bin/sh
# Publishes built firmware so meters can update over WiFi (run by GitHub Actions).
#
#   publish.sh <channel> <hw> <file.bin> [<hw> <file.bin> ...]
#
# channel: "beta" (test builds; only meters on the beta channel see them) or
#          "stable" (everyone). The version comes from config.h.
# Needs SUPABASE_SECRET_KEY (GitHub: Settings -> Secrets -> Actions).
#
# A version is published once. To publish a new build, raise SEM1_FW_VERSION
# in config.h. A beta version that later reaches main is promoted to stable
# as is (the exact tested file, not a rebuild).
set -eu

URL="https://rmgzpxwpowwzqewmiyaw.supabase.co"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHANNEL="$1"
shift
VER=$(sed -n 's/^#define SEM1_FW_VERSION "\(.*\)"/\1/p' "$DIR/SEM1_Firmware/config.h")
NOTES=$(git log -1 --format=%s -- "$DIR" | cut -c1-300)
SHA=$(git rev-parse --short HEAD)
KEY="${SUPABASE_SECRET_KEY:-}"

if [ -z "$KEY" ]; then
  echo "::notice::SUPABASE_SECRET_KEY is not set, so this build was not published (download it from Artifacts)."
  exit 0
fi
echo "Firmware $VER ($CHANNEL) from $SHA: $NOTES"

json_escape() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }

while [ $# -ge 2 ]; do
  HW="$1"
  BIN="$2"
  shift 2
  existing=$(curl -sS --fail-with-body "$URL/rest/v1/firmware_releases?hw=eq.$HW&version=eq.$VER&select=channel" \
    -H "apikey: $KEY")
  if [ "$existing" != "[]" ]; then
    if [ "$CHANNEL" = "stable" ] && echo "$existing" | grep -q '"beta"'; then
      curl -sS --fail-with-body -X PATCH "$URL/rest/v1/firmware_releases?hw=eq.$HW&version=eq.$VER" \
        -H "apikey: $KEY" -H "Content-Type: application/json" -d '{"channel":"stable"}'
      echo "$HW $VER: promoted from beta to stable"
    else
      echo "::notice::$HW $VER is already published. Raise SEM1_FW_VERSION in config.h to publish this build."
    fi
    continue
  fi

  SIZE=$(stat -c %s "$BIN")
  MD5=$(md5sum "$BIN" | cut -d' ' -f1)
  PATH_IN_BUCKET="$HW/$VER.bin"
  curl -sS --fail-with-body -X POST "$URL/storage/v1/object/firmware/$PATH_IN_BUCKET" \
    -H "apikey: $KEY" -H "Content-Type: application/octet-stream" -H "x-upsert: true" \
    --data-binary "@$BIN" >/dev/null
  curl -sS --fail-with-body -X POST "$URL/rest/v1/firmware_releases" \
    -H "apikey: $KEY" -H "Content-Type: application/json" -H "Prefer: return=minimal" \
    -d "{\"version\":\"$VER\",\"hw\":\"$HW\",\"channel\":\"$CHANNEL\",\"size\":$SIZE,\"md5\":\"$MD5\",
         \"url\":\"$URL/storage/v1/object/public/firmware/$PATH_IN_BUCKET\",
         \"git_sha\":\"$SHA\",\"notes\":$(json_escape "$NOTES")}"
  echo "$HW $VER: published ($SIZE bytes, md5 $MD5)"
done
