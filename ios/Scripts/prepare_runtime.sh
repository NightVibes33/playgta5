#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
dest="ios/WebRuntime"
mkdir -p "$dest"
cp homepage.html "$dest/index.html"
cp game.js loader.js io_worker.js wgpu_worker.js "$dest/"
cp shader-index.json "$dest/shader-index.json"
cat > "$dest/runtime-version.json" <<'EOF'
{"source":"NightVibes33/playgta5","build":"8b0b5899ed","assets":"external-usb","engineBundled":false}
EOF
# This script intentionally does not download proprietary game binaries, shaders or assets.
# The user selects an independently provided mirror/playgta5.com folder in Files.
test -s "$dest/index.html" && test -s "$dest/game.js"
echo "Prepared iOS web host from repository runtime sources; game data remains external."
