#!/usr/bin/env bash
set -euo pipefail
# Five distinct original Grand Theft Auto V assets from PlayStation media.
# Genuine publisher key art and screenshots; no generated backgrounds.
root="$(cd "$(dirname "$0")/.." && pwd)/Sources/Resources"
mkdir -p "$root"
asset() {
  local name="$1" source="$2" dest="$root/$1.jpg"
  if [ -s "$dest" ]; then return; fi
  local temp="$dest.download"
  echo "Downloading authentic GTA V scene: $name"
  curl --fail --location --retry 3 --retry-delay 3 --connect-timeout 12 --max-time 90 \
    --silent --show-error "https://gmedia.playstation.com/is/image/SIEPDC/$source?wid=1600&fmt=jpg" -o "$temp"
  sips -g pixelWidth -g pixelHeight "$temp"
  local width
  width="$(sips -g pixelWidth "$temp" | awk '/pixelWidth:/ { print $2 }')"
  if [ -z "$width" ] || [ "$width" -lt 600 ]; then
    echo "ERROR: invalid GTA V promotional artwork: $name" >&2
    exit 1
  fi
  mv "$temp" "$dest"
}
asset gtav-story-trio GTAV-product-gen9-01-en-3mar22
asset gtav-vinewood-view grand-theft-auto-v-screen-12-ps4-30jun20-en
asset gtav-car-gameplay grand-theft-auto-v-screen-05-ps4-en-22jul20
asset gtav-city-helicopter grand-theft-auto-v-screen-01-ps4-en-22jul20
asset gtav-franklin-race grand-theft-auto-v-screen-03-ps4-en-22jul20
# Five image hashes must be unique.
actual="$(shasum -a 256 "$root"/gtav-{story-trio,vinewood-view,car-gameplay,city-helicopter,franklin-race}.jpg | awk '{print $1}' | sort -u | wc -l | tr -d ' ')"
if [ "$actual" != 5 ]; then
  echo "ERROR: expected five unique GTA V assets; found $actual" >&2
  exit 1
fi
echo "Five distinct GTA V screenshots/key art verified."
