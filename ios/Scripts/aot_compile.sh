#!/usr/bin/env bash
# Reproducible no-JIT ARM64 translation pipeline for an AUTHORIZED WASM module.
# The output is *unlinked* AOT object code until all host imports are fulfilled.
set -euo pipefail
wasm="$1"
out="$2"
: "$WABT_SOURCE_DIR"
: "$WABT_BIN_DIR"
[[ -f "$wasm" ]] || { echo "Missing WebAssembly module: $wasm" >&2; exit 66; }
mkdir -p "$out"
out="$(cd "$out" && pwd)"
wasm="$(cd "$(dirname "$wasm")" && pwd)/$(basename "$wasm")"
"$WABT_BIN_DIR/wasm-validate" --enable-threads "$wasm"
python3 "$(dirname "$0")/aot_import_audit.py" "$wasm" --json "$out/engine-imports.json"
# The real GTA V engine uses memory.atomic.wait32/notify. WABT's CWriter
# aborts on these; reject them BEFORE producing truncated proprietary C output.
python3 "$(dirname "$0")/aot_feature_gate.py" "$wasm" --objdump "$WABT_BIN_DIR/wasm-objdump"
"$WABT_BIN_DIR/wasm2c" --enable-threads --no-debug-names -n native_engine -o "$out/native_engine.c" "$wasm"
test -s "$out/native_engine.c"
test -s "$out/native_engine.h"
# Produce a real ARM64 Mach-O object with native CPU instructions.
# Undefined imports remain unresolved, not secretly replaced with no-ops.
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 \
  -std=c11 -O1 -fno-optimize-sibling-calls -frounding-math \
  -I"$WABT_SOURCE_DIR/wasm2c" \
  -I"$(dirname "$0")/../NativeRuntime" \
  -c "$out/native_engine.c" -o "$out/native_engine-arm64.o"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 \
  -std=c11 -O2 -I"$WABT_SOURCE_DIR/wasm2c" \
  -I"$(dirname "$0")/../NativeRuntime" \
  -c "$(dirname "$0")/../NativeRuntime/gta-native-atomics.c" \
  -o "$out/gta-native-atomics-arm64.o"
xcrun --sdk iphoneos ar -rcs "$out/libnative-engine-arm64.a" "$out/native_engine-arm64.o" "$out/gta-native-atomics-arm64.o"
file "$out/native_engine-arm64.o"
echo "ARM64 AOT compilation succeeded. Host imports are NOT yet linked."
echo "No claim of playable GTA: real host ABI, Metal shader bridge and physical device tests remain."
