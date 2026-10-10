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


## Build 23 — additional real WASM game text/configuration imports

The uploaded game's exact WebAssembly signatures were checked against its
binary and the original `game.js`:
- `env.wasm_print_line_js(i64)` — engine UTF-8 diagnostics
- `env.wasm_hang_line_js(i64)` — engine hang diagnostics
- `env.wasm_module_int_js(i64,i32)->i32` — Module integer option/fallback

The iPhone host now registers these three exact-typed Wasmtime C API
callbacks in addition to the ten previously linked game functions (**13 of
85 real function imports**). A fixed-size pthread-protected ring passes
sanitized engine lines to Files-exportable `LogStore` diagnostics, with
NUL-termination and address bounds checks on all guest memory64 reads.
The integer configuration import returns the original game's supplied
fallback when the option is absent; native options can be staged explicitly.

A deterministic C host test verifies pointer validation, a real
memory-backed option override, fallback behavior, order-preserving log
extraction, and unbind safety. The iOS Wasmtime linker smoke test calls
`wasm_module_int_js` through the actual C API (not a simulated Swift
callback) and checks the returned fallback.

**Still not gameplay.** Native guest pointers cannot reference the original
GTA engine until its 3 GiB shared memory is safely instantiated and bound,
and the remaining host imports, renderer/shaders, actual game audio,
save lifecycle, and in-world input all exist. The real AOT module currently
undergoes deserialization and ABI coverage inspection only.


## Build 24 — actual GTA save/setting writes and deletes (15/85 imports)

The original `game.js` and the uploaded WebAssembly ABI agree on:
- `env.wasm_userdata_put_js(i64 path, i64 data, i64 size, f64 mtimeMs)->void`
- `env.wasm_userdata_delete_js(i64 path)->void`

These two callbacks previously went to the browser's IndexedDB
`gta5-userdata` store. They now call the native `NativeUserdataHostABI.c`
implementation through real Wasmtime linker registrations. Native code
resolves bounded string/data offsets from the externally owned guest shared
memory64 region and stores per-user files in the **app-private**
`Documents/GTAiOS-Userdata/` directory; the USB game archives are untouched.
Writes use restrictive permissions, per-directory `openat` with
`O_NOFOLLOW`, atomic rename, fsync and original mtime preservation.
Invalid guest pointers, traversal components, oversized files (>32 MiB),
symlinks and unbound memory fail safely, with errors exposed in Files logs.
Deleting a non-existent save is idempotent.

A separate pure-C regression test checks write, readback, timestamp,
directory traversal rejection, size/bounds enforcement, deletion and
unbinding. The native launcher also corrects a critical BUILD 23 logic
regression: it compared **13 registered host imports** to **10**, preventing
the rest of runtime verification from running even on a correct host.
Build 24 now expects exactly **15**.

This does **not** yet restore saved userdata into the GTA engine's in-memory
filesystem on startup. Nor does it instantiate the 3 GiB shared memory or
finish the other 70 function imports and true Metal graphics/loading/audio
interfaces. A successful IPA build is only host-ABI coverage, not gameplay.


## Build 25 — three ABI-accurate WASI memory64 host services (18/85 imports)

The actual uploaded engine imports the following WASI preview1 signatures:
- wasi_snapshot_preview1.clock_time_get(i32 id, i64 precisionNs, i64 timestampPtr)->i32
- wasi_snapshot_preview1.environ_sizes_get(i64 countPtr,i64 byteCountPtr)->i32
- wasi_snapshot_preview1.environ_get(i64 entriesPtr,i64 storagePtr)->i32

NativeWASIHostABI.c implements the actual WASI return-code semantics:
CLOCK_REALTIME / CLOCK_MONOTONIC nanoseconds are written as LE u64 to the
guest's *externally bound* memory64 region; optional CPU/thread clock IDs
are supported only if the iOS SDK exposes them. The precision parameter
is an advisory hint, not a delay or an allocation. Invalid guest pointers
return WASI EFAULT (21); invalid clock IDs return EINVAL (28). The
sandbox exposes an empty environment to the guest, deliberately NOT any
host process variables or credentials. environ_sizes_get writes two u64
zeros; environ_get validates the zero-length destinations.

The exact 3 signatures are now registered in the real Wasmtime C API linker
alongside the earlier 15 GTA host callbacks, for **18 of 85 functions**.
A C regression test covers clock output, empty environment, unbound guest
memory, overflow, out-of-bounds addresses and nonclobbering behavior.
A Wasmtime linker smoke calls clock_time_get without a bound heap and expects
EFAULT rather than fake success.

This does not allocate the GTA engine's required 3 GiB shared memory.
Until the Wasmtime embedding binds and maintains that memory while the
real engine executes, these callbacks correctly refuse memory writes.
The other 67 function imports, GTA Metal rendering and shader conversion,
actual original loading, in-world input, audio and end-to-end saves remain
unfinished. The app is still a native runtime test, not a playable game.


## Build 26: verified WASI fd_write and native diagnostics (19/85 imports)

The real uploaded engine imports
`wasi_snapshot_preview1.fd_write(i32 fd,i64 iovs,i64 count,i64 nwritten)->i32`,
using 16-byte memory64 iovecs. The C host now validates every source span and
destination pointer, supports stdout/stderr, writes the exact completed byte
count, rejects unsupported FDs, and passes bounded printable output into the
existing Files-exportable native log queue. The source output is capped to a
200-byte preview, while total write size is limited to 1 MiB, so a malicious
guest cannot force uncontrolled allocations or log output.

Build 25's three WASI calls (clock_time_get, environ_sizes_get, environ_get)
are retained. A native C regression test exercises real guest iovec layouts,
the stdout and stderr callbacks, bad FDs, malformed pointers, overflow,
unbinding and diagnostic log delivery. The Wasmtime linker now registers
**19 of 85** actual typed function imports. The remaining **66** functions
and env.memory are not implemented.

This is not GTA gameplay, game audio, original loading, shaders or an actual
Metal world renderer. The true GTA 3 GiB shared memory import is still
unallocated and the Wasmtime engine is not instantiated; full GameController
signals cannot be passed to gameplay until that exists.


## Build 27 — four more verified WASI file-descriptor imports (23/85)

Using the exact uploaded real `game.wasm` type section, this adds:
- `fd_close(i32)->i32` (WASI preview1 standard stream lifecycle)
- `fd_read(i32,i64,i64,i64)->i32` (64-bit guest iovecs; stdin EOF)
- `fd_seek(i32,i64,i32,i64)->i32` (ESPIPE for nonseekable standard streams)
- `fd_pread(i32,i64,i64,i64,i64)->i32` (ESPIPE for standard input)

The native Wasmtime linker registers these four signatures exactly; total
coverage is **23 of 85 function imports**, with 62 function imports and the
3 GiB shared memory still unimplemented. Actual native C regression tests
check guest memory64 iovec validity, overflows, zero-byte EOF, non-mutating
seek errors, EBADF handling, closure/repeat closure, and rejection of arbitrary
host process file descriptors.

These callbacks currently implement only standard streams (0, 1, 2).
**No USB-backed virtual file descriptor table has been implemented**;
`openat`, archive paging, ordinary `fd_read` of game files, and startup
filesystem restoration remain blockers. Standard FD functionality is not
equivalent to functioning GTA archive I/O. The original engine is still
not instantiated; there are no real in-game frames, textures, shaders, input,
audio playback or completed loading sequence. Signed-device testing remains
necessary for the native Wasmtime runtime.

## Build 28 — real read-only file-backed WASI descriptors (23/85 maintained)

The existing verified `fd_read`, `fd_pread`, `fd_seek`, and `fd_close`
imports now support bounded **real file bytes**, in addition to standard
streams. A native API duplicates an explicitly authorized regular-file
descriptor into a 64-slot **guest-only** fd table, separate from POSIX fd
numbers. Sequential reads have their own cursor; pread does not change it.
Reads validate all memory64 iovecs up front and cap each operation at 1 MiB.
Seek supports SET/CUR/END, overflow checks, and actual file sizes; close and
reset release every owned descriptor. Native tests write a temporary real
file and assert its bytes pass through memory64 ABI reads and seeks.

**This does not increment 23/85 import coverage.** It replaces incomplete
standard-stream-only behavior for four already-registered imports. An
engine-aware `__syscall_openat` bridge and a security-scoped USB root are
still needed to register GTA archives; no GTA asset is invented or embedded.
The private GTA engine AOT is not in this repo and cannot be instantiated or
declared playable by these unit tests.

## Build 29 — actual USB-to-WASI memory64 readback on iPhone

When the external `data/manifest.json` is available, the native game
preflight coordinates its existing security-scoped URL, opens the actual
regular file, registers a separate guest-only descriptor, and compares a
32-byte prefix from genuine `fd_pread` and `fd_read` through a 128-byte
memory64 test buffer against the original USB file. It also checks sequential
seek position and guarantees unbinding/closing after the probe. Logs
differentiate verified USB bytes from errors; removing or changing the USB
folder closes any outstanding guest descriptor duplicates.

This verifies a native device filesystem path only *after physical iPhone
execution*. It is not GTA engine instantiation, game archive openat, original
loading, graphics, audio, or gameplay. ABI import coverage stays **23/85**.

## Build 30 — full private AOT import audit

For the SHA256-verified, version-matched private GTA AOT module, the device
now records every unresolved or type-mismatched import and the true Wasm
function signature (params and results) in the Files-exportable diagnostics,
not only the first missing name. The import inventory is derived from the
actual serialized module, not the broader `game.js` JS shim (which contains
functions not necessarily imported by the 63 MiB binary). The compact UI
shows only the summary; the native log retains the complete ABI report.
No fake host callbacks, engine instantiation, or playable-game claim.

## Build 30 — game archive path-open ABI (24/85 native imports)

This registers `env.__syscall_openat(i32,i64,i32,i64)->i32` from the
original Emscripten `game.js` with a **real read-only iOS file-provider
bridge**. Guest UTF-8 paths are bounded and read from bound memory64;
absolute /data/* and /b/* or matching relative paths are routed through
the user's approved USB game root. NSFileCoordinator opens the real file
and the native 64-slot guest descriptor table duplicates its handle.
The guest receives a virtual WASI fd supporting read, pread, seek and
close. Write/create/truncate attempts are rejected, and traversal paths
are rejected independently by USBStorageManager. No assets are fabricated.

This increases real linker registrations from **23/85 to 24/85**.
The native engine cannot yet be instantiated: other imports, true
3 GiB guest memory, pthread scheduling, WebGPU/Metal shaders and
audio remain outstanding. On-device execution of the actual game
is still unverified.

## Build 31 — Emscripten openat source-path regression

The memory64 host test now drives the real `__syscall_openat` C ABI through
an explicitly registered read-only descriptor provider. It verifies normal
authorized open and close, denial of write flags, invalid guest pointers and
dirfds, and native rejection of dot-segment traversal and doubled separators
before calling the Swift security-scoped file provider. This test does not
contain or synthesize actual GTA assets.


## Build 31 — batch platform imports (29 of 85 registered)

The ARM64 linker now registers five additional original-game imports: `__syscall_fstat64`, `__syscall_stat64`, `__syscall_lstat64`, `_gmtime_js`, and `_localtime_js`. The stat ABI copies the real authorized archive descriptor metadata into the exact original 104-byte guest layout instead of casting Darwin struct stat. Native time services populate the game.js tm offsets and timezone seconds. Tests check real file sizes and bounds. Directory/symlink/pseudo-filesystem semantics remain incomplete; path stat only works for authorized archive files. The 3 GiB memory import and original gameplay are NOT operational, and these registered callbacks have not been verified against a real on-device GTA module instantiation.


## Build 32 — grouped Emscripten syscall implementations (32/85)

Implements three actual game.js host imports with the ABI-accurate
Wasmtime callback types:

- \`env.__syscall_getcwd(i64,i64)->i32\`: obtains the original Emscripten
  bootstrap currentPath "/" and writes the real NUL-terminated result into
  bounded guest memory64; preserves short-buffer return behavior
- \`env._emscripten_system(i64)->i32\`: reproduces the browser runtime's
  explicit refusal to spawn a shell (null command succeeds, others return
  -52) rather than running commands on iOS
- \`env.__syscall_fcntl64(i32,i32,i64)->i32\`: handles the original
  virtual-descriptor duplication, status flags and advisory lock cases,
  keeping the authorized guest fd table separate from POSIX process fds

These are actual guest-visible native services, not linker placeholders;
unit tests check guest pointers and independent descriptor lifetimes.
The source still requires the other 53 imported functions, 3 GiB shared
memory, thread lifecycle, native WebGPU-to-Metal rendering and physical
iPhone world-play testing. Do not describe the IPA as playable.


## Build 33 — real guest PCM stereo ring -> native AVAudioEngine (33/85)

The exact original \`env.wasm_audio_publish_js(i64 ring,i32 capacity)->void\`
is registered in the Wasmtime linker. A separately compiled C bridge
implements the original browser \`audio-worklet.js\` header and interleaved
float32 stereo ring, atomically reading published PCM and advancing the guest
read cursor. Native output only schedules actual guest frames through
AVAudioEngine; it does not emit test tones or fake gameplay audio.

Safety: bounds-check the entire ring against an externally bound live
Wasmtime memory64 mapping; require a power-of-two capacity; handle uint32
sequence wrap and producer overrun; unbind before the guest memory is
released/replaced; remain silent when no real guest audio exists. An
independent native unit test covers stereo, cursor increments, wraparound
and no-bound-memory behavior.

No real GTA audio can occur until the **actual game** is instantiated with
its required 3 GiB shared memory and invokes this callback. Native Metal
world rendering, threading, and engine startup remain missing.


## Build 34 — verified-on-source native filesystem & timezone import batch (36/85)

Three more typed Wasmtime registrations reproduce original game.js ABI:

- \`env.__syscall_newfstatat(i32,i64,i64,i32)->i32\`, including
  AT_FDCWD archive path queries and AT_EMPTY_PATH for a live guest FD
- \`env.__syscall_statfs64(i64,i64,i64)->i32\`, writing the actual
  filesystem's statfs block counts, availability and name length to
  original guest memory64 offsets; no synthetic capacity values
- \`env._tzset_js(i64,i64,i64,i64)->void\`, supplying the current
  system's standard timezone offset, DST flag and Emscripten-compatible
  UTC±HHMM display names into bounded memory

These services remain limited to the selected read-only USB archive root,
not a complete Emscripten virtual filesystem. They do not solve the original
3 GiB guest shared-memory import, engine threading, WebGPU/Metal rendering or
real-world GTA V launch. ABI registration is not proof of gameplay.
