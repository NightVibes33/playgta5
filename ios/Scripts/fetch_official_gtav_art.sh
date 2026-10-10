#!/usr/bin/env bash
set -euo pipefail
# Real GTA V marketing imagery: original Rockstar game artwork on Steam's CDN.
# Steam app 271590, NOT GTA VI. Bundled at build time, never fetched by the app.
resources="$(cd "$(dirname "$0")/.." && pwd)/Sources/Resources"
mkdir -p "$resources"
download_asset() {
  local key="$1" target="$2" tmp="/tmp/gtav-$1-$$.jpg" success=0
  for base in \
    "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/271590" \
    "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/271590" \
    "https://cdn.akamai.steamstatic.com/steam/apps/271590"; do
    if curl --fail --location --silent --show-error --retry 1 \
        --connect-timeout 8 --max-time 40 "$base/$key" -o "$tmp"; then
      if sips -g pixelWidth -g pixelHeight "$tmp" 2>/dev/null | grep -q 'pixelWidth:'; then
        mv "$tmp" "$resources/$target"
        success=1
        break
      fi
    fi
  done
  if [[ "$success" -ne 1 ]]; then
    echo "ERROR: could not retrieve authentic GTA V promotional artwork $key" >&2
    rm -f "$tmp"
    exit 1
  fi
  echo "Official GTA V Steam artwork: $key -> $target"
}
download_asset "library_hero.jpg" "gtav-official-hero.jpg"
download_asset "library_600x900.jpg" "gtav-official-cover.jpg"
download_asset "header.jpg" "gtav-official-header.jpg"
