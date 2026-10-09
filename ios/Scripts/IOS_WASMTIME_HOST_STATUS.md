# Native Wasmtime host — ARM64 iPhone integration

## Verified

- The user-supplied 63,201,802-byte GTA game.wasm matches repository SHA-256
  11ca8d2c04c5e843d18ff4aea4899d72c86973c6b031df334e67c446b2ae83e0.
- Wasmtime 49.0.2 AOT-compiled the real engine to an AArch64-Apple-iOS
  serialized ELF module (238,815,736 bytes, SHA-256
  b2fadd0881302505388104a0ff6b428db65106edd81a8e5a64fcfa905a4febb0).
  It is not a linkable signed Mach-O executable.
- An iOS arm64 Wasmtime 49.0.2 C-API static runtime was built with
  --no-default-features --features threads (runtime-only, no on-device compiler).
- The native GTAiOS IPA now links wasm_engine_new, wasm_engine_delete,
  wasmtime_module_deserialize_file and app-owned engine/AOT probes; the latter
  are present as private-external (__TEXT,__text) Mach-O symbols. The
  packaging verifier checks defined symbols, including hidden/local ones.
- Wasmtime conf.h is generated from the pinned upstream v49 conf.h.in template
  using threads-only feature selection, not a manually invented header.
- iPhone ARM64 build + IPA packaging CI was green on run 37865828055,
  and the symbol verifier fix passed on run 37865641009.

## What happens on the iPhone

1. The native Metal/USB/engine header checks run without WKWebView.
2. A Wasmtime C-API engine initialization probe runs on iPhone hardware.
3. If an exact SHA-256 allowlisted real-gta-ios.cwasm is present on the USB
   drive, the app can attempt native Wasmtime deserialization and count the 86
   expected imported host bindings. The module is never instantiated.
4. Failures are written to the native diagnostics for user-device evaluation.

These are compiled/device-ready code paths, NOT verified runtime behavior.
An iPhone 16 running iOS 27 beta 4 still needs to execute them; signing,
code-page permissions and Wasmtime artifact compatibility can fail on-device.

## Still missing before GTA V is playable

- Full 85-function Emscripten/WASI/project-specific native host import ABI
- Real GTA host threading/shared-memory64 initial 3 GiB management
- WebGPU-facing command and shader translation into complete Metal pipelines
- Correct engine-bound Bluetooth/wired controller and touchscreen gameplay
- Original engine audio/loading sequence, saves, stable rendering and gameplay
- Physical iPhone 16 device execution, FPS/thermal/memory and stability tests

Never claim GTA V gameplay has launched simply because the Wasmtime static
library linked, the AOT artifact deserialized, or a Metal diagnostic frame
was presented. The proprietary game engine/AOT blobs remain outside GitHub.
