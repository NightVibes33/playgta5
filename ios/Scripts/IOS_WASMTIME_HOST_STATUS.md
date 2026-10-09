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


## Build 13: first real native host functions

The signed-side Wasmtime host now defines four genuine, ABI-matched
`env` imports from the actual game:
`wasm_now_ms() -> f64`, `emscripten_get_now() -> f64`,
`emscripten_date_now() -> f64`, and
`emscripten_num_logical_cores() -> i32`.

Both monotonic-time imports use `clock_gettime(CLOCK_MONOTONIC)`,
the date import uses `CLOCK_REALTIME`, and the CPU query uses
`sysconf(_SC_NPROCESSORS_ONLN)`. These are registered in the actual
Wasmtime C API linker, with a device-side `wasmtime_linker_get` /
`wasmtime_func_call` smoke test that invokes the native callback.

Unsupported game functions remain **unresolved**. The app does not
register fake zero-returning callbacks or instantiate the GTA game.
Only 4 of 85 imported functions are implemented. Importing a large
3 GiB shared memory, the complete WebGPU/Metal bridge, asset paging,
threads, input, audio and the remaining WASI/Emscripten imports are
still necessary before genuine gameplay. A green ARM64 build checks
linkability, not actual on-device callback operation.


## Build 14: typed host import coverage and real heap-limit callback

A fifth GTA import, `env.emscripten_get_heap_max() -> i64`, is implemented
using the actual engine's declared maximum 262144 * 65536 = 17179869184
bytes. This is a **logical WASM heap maximum**, not physically available RAM.
The runtime invokes the callback via the Wasmtime linker and checks its
64-bit result, as well as the existing monotonic-clock smoke test.

For an SHA256-verified `real-gta-ios.cwasm` file on the USB drive, native
deserialization now enumerates all 86 actual imports, registers the known
callbacks with the real Wasmtime C API linker, and compares each resolved
function's complete input/output value kinds against the module. Reports
include the number of compatible host imports, unresolved imports and the
first missing symbol (typically `env.memory`). It **does not** allocate
the 3 GiB heap, register fake defaults or instantiate the GTA engine.

A green build means the code compiles and links on arm64; the 5/86 coverage
must still be observed on physical iPhone after supplying the private AOT.
All remaining host imports, memory, input, WebGPU-to-Metal renderer, original
loading, native game audio and saves are unfinished. No gameplay claim.


## Build 15: sideload-native UI quality and input/audio/save foundations

- Polished launcher: branded launch storyboard, simpler GTAV hero, live USB
  readiness, engine status, controller tools and a collapsed advanced diagnostics
  panel. Main action is explicitly **CHECK NATIVE RUNTIME**, not fake gameplay.
- Real native landscape touch-input overlay: two draggable analog joysticks,
  multi-touch-capable held buttons for aim/fire/jump/cover/reload/enter, a
  driving/on-foot profile flag and persistent visibility toggle. GameController
  analog and touch input merge into NativeInputState. The source engine input
  ABI is still unimplemented; this is staging hardware and UI input only.
- Native UI refresh/FPS tick statistics (explicitly **NOT GAME FPS**),
  device thermal status and battery level. This does not measure GTA gameplay.
- AVAudioEngine stereo float PCM scheduling adapter and app-private atomic
  32-MiB-bounded save slots. Neither is wired to GTA's original audio/save
  Emscripten imports yet.
- Native AOT introspection remains the same as Build 14: game is NOT
  instantiated, original engine loading and shader rendering remain missing.
- Intended for SideStore unsigned IPA distribution only; no App Store release
  workflow, subscriptions, storefront, or App Review entitlement assumptions.

The advanced controls, dashboard and save/audio components can all compile
and run without the proprietary engine. They are prerequisites, not evidence
of playable GTA V. No game frames, game soundtrack, original loading sequence,
or in-world controller response have been verified.

## Build 16: first real iPhone AOT **execution** probe (separate from GTA)

- CI now compiles an original, tiny WebAssembly function `add(i32,i32)->i32`
  into Wasmtime 49.0.2 AArch64-Apple-iOS serialized AOT code, and bundles it
  as `native-aot-smoke.cwasm` in the unsigned IPA.
- New `NativeAOTExecutionProbe.c` uses the real Wasmtime C API to deserialize,
  **instantiate and execute** this signed-bundle fixture on a physical
  iPhone, checking that `add(20,22)` returns `42`. This is a test of
  executable-page availability, not a fake rendering scene.
- On-device results (success or entitlement/code-signing failure) are logged
  in native diagnostics. CI can only prove the test code compiles and links;
  until device testing, the execution result is **not verified**.
- Three additional real GTA imports are registered: `wasm_has_page_js()->i32`
  and `wasm_userdata_page_js()->i32` correctly report 0 because the
  original browser page / JS ioWorker services are unavailable in the native
  runtime, and `emscripten_check_blocking_allowed()->void` matches the
  original JavaScript no-op check. These are feature probes, **not** full
  implementations of browser paging, persistence, or threading.
- With 8/85 function imports registered, 77 host functions and the required
  imported 3GiB shared memory remain missing. The game is still not
  instantiated. No real GTA shader, loading screen, audio, saves, or gameplay
  has been tested.

The actual GTA `real-gta-ios.cwasm` is still an external/private AOT engine
whose host ABI cannot currently be satisfied; do not call this build playable.


## Build 17: signed AArch64 shared memory64 import and data-coherence smoke

Before allocating the real GTA engine's 3 GiB shared memory, exercise the
exact Wasmtime 49 C API on-device with a tiny 64 KiB 64-bit shared memory:

- CI compiles a synthetic `(import "env" "memory" (memory i64 1 2 shared))`
  module to `aarch64-apple-ios` via the pinned Wasmtime CLI.
- Native C calls `wasmtime_memorytype_new(1, true, 2, true, true, 16)`,
  `wasmtime_sharedmemory_new`, and
  `wasmtime_linker_define("env","memory")`; then deserializes the
  signed-bundle AOT fixture, instantiates it and runs `touch(i64)`.
- The guest stores `42` at address 16 and loads the value back. Native code
  independently reads bytes 16–19 via `wasmtime_sharedmemory_data` and
  requires both results to equal 42. A plain AOT deserialization is not enough.
- Detailed native logs identify store/instantiation errors and distinguish
  code-signing problems from unsupported shared-memory limits. Simulator
  continues to omit device-only Wasmtime runtime.
- CI verifies the fixture's presence and the real Wasmtime sharedmemory
  symbols in the final unsigned IPA.

This demonstrates only an iOS-capable path *once tested on the real phone*.
No device execution is claimed based on CI alone. It is intentionally a
64 KiB **test**, not a truncated or fake implementation of the GTA engine's
49152-page (3 GiB) minimum. The remaining unimplemented 77 host imports,
memory-size validation on hardware, native Metal shader bridge, audio, save
and input binding still block actual gameplay.
