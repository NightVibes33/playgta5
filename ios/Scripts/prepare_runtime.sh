#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
dest="ios/WebRuntime"
mkdir -p "$dest"
cp homepage.html "$dest/index.html"
cp game.js loader.js io_worker.js wgpu_worker.js "$dest/"

# The source site's memory64+pthreads build requests a 16GiB maximum.
# WebKit in iOS 27 developer beta 4 can reject this declaration before the
# game even allocates memory. Patch only the iOS packaged copy, NOT game.js in
# the upstream web sources. Keep the engine's original 3GiB initial pages:
# reducing it blindly can make the imported memory incompatible with game.wasm.
python3 - "$dest/game.js" <<'PYIOSMEM'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = 'var INITIAL_MEMORY=3221225472;wasmMemory=new WebAssembly.Memory({initial:BigInt(INITIAL_MEMORY/65536),maximum:262144n,shared:true,address:"i64"})'
new = ('var INITIAL_MEMORY=3221225472;'
       'console.log("[GTAiOS] memory64 compatibility: initial 3 GiB, maximum 4 GiB (65536 pages); original declared maximum 16 GiB");'
       'try{wasmMemory=new WebAssembly.Memory({initial:BigInt(INITIAL_MEMORY/65536),maximum:65536n,shared:true,address:"i64"})}'
       'catch(e){console.error("[GTAiOS] WebKit could not allocate the 3 GiB initial shared memory64 heap: "+e);throw e}')
if s.count(old) != 1:
    raise SystemExit('ERROR: upstream WASM memory initialization changed; review before packaging')
p.write_text(s.replace(old, new, 1))
print('iOS-only memory64 maximum patched: 262144 -> 65536 pages; initial 49152 pages unchanged')
PYIOSMEM

cp shader-index.json "$dest/shader-index.json"
cp data-manifest.json "$dest/data-manifest.json"
cp ios/Bridge/controller-bridge.js "$dest/controller-bridge.js"
cp ios/Bridge/preflight.html "$dest/preflight.html"
python3 ios/Scripts/inject_controller.py "$dest/index.html"
python3 - "$dest/index.html" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
viewport='<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">'
assert "<head>" in s
p.write_text(s.replace("<head>", "<head>\n"+viewport, 1))
PY
cat > "$dest/runtime-version.json" <<'EOF'
{"source":"NightVibes33/playgta5","build":"8b0b5899ed","assets":"external-usb","engineBundled":false}
EOF
# This script intentionally does not download proprietary game binaries, shaders or assets.
# The user selects an independently provided mirror/playgta5.com folder in Files.
test -s "$dest/index.html" && test -s "$dest/game.js"
echo "Prepared iOS web host from repository runtime sources; game data remains external."
