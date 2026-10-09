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


## Build 18: verified native GTA keyboard/mouse input ABI (not gameplay)

The actual game.wasm imports `env.wasm_input_publish_js(i64)->void`
(type 1). The original homepage installer documents a **444-byte**
shared-memory WasmInputBlock: 256 virtual-key bytes, 10 int32 words,
64 UTF-16 queue entries and debug/viewport/start-mode fields.
The native app now registers the ninth signature-correct Wasmtime callback
for this real engine import and tests it with a 64-bit block offset.

`NativeGameInputABI.c` binds a user-provided shared-memory base and safely
writes only inside the 444-byte region, using atomic key/mouse writes and
bounds/alignment validation. It maps merged GameController + touch controls
into the engine's actual keyboard/mouse ABI, including movement keys, camera
delta, mouse fire/aim, menu, foot/vehicle/air mapping and release on disconnect.
The native frame loop sends a staged frame every display-link tick.
A deterministic 1024-byte memory fixture tests the original layout, camera
deltas, buttons, driving input, bounds and key release; it never allocates
the GTA engine's 3GiB memory.

The engine is **not instantiated**: the real `env.memory` import remains
unprovided, so the native writer correctly returns "pending guest memory"
until its bind/publish contract is satisfied. This is tangible engine-level
input ABI implementation, not analog GTA controller support. The binary
only exposes keyboard/mouse controls, so true analog steering/throttles
still require a new engine interface or adaptation.

GTA V gameplay, original loading, native Metal shaders, original audio and
saves remain unverified and unfinished. CI passing means the host ABI code
compiles, not that an in-world engine received these inputs.


## Build 19: compiled ARM64 guest reads actual native game input block

Extend the **existing** signed-bundle Wasmtime memory64 AOT fixture with
an exported `input_w(i64)->i32` memory load. After successfully validating
shared-memory host/guest coherence, the native iPhone runtime binds
`wasmtime_sharedmemory_data` to `NativeGameInputABI`, publishes the
444-byte input block at aligned offset 512 and applies a movement frame.
It then calls the AOT-compiled `input_w` function at the W-key address
and requires the result to be 0x80 (pressed). On release it requires
a second guest readback of 0x00. The host unbinds its pointer **before**
the shared memory is freed on every path, including failures.

This is a much stronger end-to-end test than C unit tests: native iOS
GameController/touch-frame format → real shared memory64 memory → compiled
AArch64 WASM guest instruction → readback, plus release. The unsigned IPA
packages the augmented AOT fixture and logs success or the precise failing
phase on the actual iPhone. **CI verifies compilation and packaging only.**

This is deliberately a synthetic one-page module. The real 3 GiB GTA shared
memory has NOT been allocated; none of the remaining game imports, in-world
controls, genuine game loading, graphics, shaders, audio or saves are
operational. Physical device run is still needed to verify that iOS permits
AOT executable pages, even for this signed fixture.


## Build 20: real USB HTTPFS manifest import (10th host binding)

- Implemented the exact `env.wasm_httpfs_manifest_js(i64 buffer, i32 capacity)->i32`
  from the original `game.js`. It reads the externally selected
  `data/manifest.json` through `NSFileCoordinator`, stages at most 32 MiB
  of JSON in the native host, and returns the required byte length. A second
  call with sufficient capacity writes bytes plus a terminating NUL into
  a bound shared WASM memory view. This reproduces the original browser
  implementation's `cap > length` condition, rather than simulating HTTP.
- Strict bounds checks protect untrusted memory64 destination pointers; the
  real 20 GB archive data stays on USB. A pure C regression test exercises
  length querying, exact-size non-write behavior, successful copy,
  NUL termination, overflow, out-of-bounds rejection, and unbinding.
- The Wasmtime linker now registers **10 of 85** verified game imports,
  with the correct `i64,i32 -> i32` signature. Game engine import
  validation remains non-instantiating until all 86 imports (including
  shared memory64) and the Metal renderer are implemented.
- This is not engine execution or gameplay. It only provides a genuine
  prerequisite for loading the original game archives.


## Build 21 — iPhone 16 / iOS 27 beta 4: compatibility corrections

Real user logs from BUILD 20 confirm the USB folder was granted and passed
validation. Metal A18 GPU creation and native host C-API initialization both
succeeded, along with a 10/85 genuine host-function registration smoke.

Two signed-bundle native AOT fixtures failed Wasmtime deserialization:
`module was compiled with GC however GC is disabled in the host`.
The v49.0.2 host was built with `--no-default-features --features threads`.
The v49.0.2 CLI defaults to GC-enabled support even for basic modules.
Build 21 therefore compiles both iOS fixtures with
`-W gc-support=n,threads=y,shared-memory=y,memory64=y` and explicitly
sets `wasmtime_config_gc_support_set(false)` in the three deserializing
C-API engines. This aligns serialized artifact configuration with the
actual installed runtime rather than enabling a missing runtime feature.

The same compatible flag is set in `aot_compile_wasmtime.sh` for a
user-authorized private GTA engine build. The original
`real-gta-ios.cwasm` SHA allowlist is NOT updated speculatively: an
actual newly compiled engine would have a different digest and size,
which must be verified before the app can deserialize it. No GTA
engine instantiation or actual gameplay is claimed.

A separate `None of the requested orientations are supported` diagnostic
indicates a race during portrait-launcher to landscape-native-view navigation.
Build 21 refreshes UIKit orientation support during the navigation
transition and schedules geometry selection after presentation.

The remaining GTA engine work includes at least 75 additional host functions,
real 3 GiB shared-memory management, native Metal shader/graphics command
translation, host/guest controller ABI, genuine game audio, saves and gameplay.
A green IPA build does NOT establish that any of those exist.

## Build 22 — real private GTA AOT profile rebuilt and authenticated

The exact uploaded 63,201,802-byte engine was recompiled *privately*
with Wasmtime 49.0.2 using:
`-W gc-support=n,threads=y,shared-memory=y,memory64=y`,
`--target aarch64-apple-ios -O opt-level=0 -C parallel-compilation=n`.

Result: success in 87.94 seconds (peak RSS ~2.12 GiB).
Generated AArch64 serialized Wasmtime module: 238,815,736 bytes.
New verified SHA-256:
`4ed6a1261747212cc3413319db55c20f9ee48be72d6572dd4513f4febb318fd9`.

The app's AOT content allowlist is updated to **this verified new digest**;
the previous `b2fadd...` GC-enabled engine file was incompatible with the
threads-only host. The regenerated binary remains a separate, private
user deliverable, not a GitHub source or CI artifact.

Native iOS AOT deserialization and 86-import ABI inspection now have a
compiler profile consistent with the host. **The full game is NOT yet
instantiable**: only 10 of 85 function imports are implemented, the
real 3 GiB shared memory and graphics host ABI are not, and GTA V
cannot yet load its true shaders, render its world or execute gameplay.
