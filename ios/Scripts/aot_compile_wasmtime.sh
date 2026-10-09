#!/usr/bin/env bash
# AOT compile authorized WASM for a Wasmtime iOS ARM64 runtime.
# Output is Wasmtime-specific ELF, not a standalone Mach-O iOS app.
set -euo pipefail
wasm="$1"
out="$2"
: "$WASMTIME_BIN"
test -s "$wasm"
mkdir -p "$(dirname "$out")"
python3 "$(dirname "$0")/aot_import_audit.py" "$wasm" \
  --json "$(dirname "$out")/aot-imports.json"
# Match the iPhone's threads-only Wasmtime C host. Without gc-support=n,
# serialized AOT deserialization fails: "module was compiled with GC however
# GC is disabled in the host", even for modules that never use WebAssembly GC.
"$WASMTIME_BIN" compile --target aarch64-apple-ios \
  -W gc-support=n,threads=y,shared-memory=y,memory64=y \
  -O opt-level=0 -C parallel-compilation=n -o "$out" "$wasm"
python3 - "$out" <<'PY'
from pathlib import Path
import struct,sys
p=Path(sys.argv[1])
with p.open("rb") as f: h=f.read(64)
assert len(h)==64 and h[:4]==b"\x7fELF", "Not ELF"
assert h[4]==2 and h[5]==1, "Expected 64-bit little-endian ELF"
assert struct.unpack_from("<H",h,18)[0]==183, "Expected ARM AArch64 machine code"
assert p.stat().st_size>1024, "AOT output empty"
print("PASS: AArch64 machine code in Wasmtime serialized ELF artifact")
print("Output bytes:",p.stat().st_size)
print("NOT A PLAYABLE GAME: requires Wasmtime iOS runtime, executable-memory")
print("permissions, 85 host functions, Metal renderer and gamepad ABI.")
PY
