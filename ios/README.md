# GTAiOS — native ARM64 bring-up (iPhone 16 / iOS 27 beta 4)

**Status: NATIVE FOUNDATION ONLY. GTA V IS NOT YET PLAYABLE.**

This branch now builds a native Metal/UIKit application rather than packaging a
WKWebView browser runtime. It verifies game files on a user-selected USB-C
drive, introspects real WASM memory imports and captures full GameController
hardware state, without pretending that these operations execute RAGE.

## What has been implemented

- UIKit iPhone launcher and native Metal-backed landscape diagnostic view.
- Apple A18 GPU detection, a real Metal command queue and drawable submission.
  The surface intentionally clears to black; it does *not* render fake GTA.
- Security-scoped folder picker, bookmark restore and read-only USB-C asset
  handling. The engine and game assets stay on the user-selected drive.
- USB byte-range access with NSFileCoordinator and a 4 MiB per-read bound.
- Native WebAssembly binary-header and import-section inspection of
  \`b/8b0b5899ed/game.wasm\` (only tiny sections are inspected). It reports the
  engine's actual minimum/maximum imported memory, shared-memory flag and
  memory64 requirements.
- Native GameController polling at 60 Hz, analog stick/triggers/buttons,
  connect/disconnect, remapping settings and supported controller haptic test.
  Gameplay-controller ABI wiring is not present yet.
- Native AVAudioSession setup (no game sound synthesis yet), exported diagnostic
  logs, physical-device unsigned IPA pipeline and simulator smoke screenshot.
- CI rejects the WebRuntime/browser resource bundle and verifies the native
  runtime source contracts.

**There is no ARM64 GTA game engine linked.** \`NativeEngineStatus.nativeEngineLinked\`
is intentionally false, and the screen displays that fact. Passing the iOS
ARM64 compile is not evidence that GTA executes.

## What is needed to finish the actual native port

1. **Engine binary & rights:** Supply the authorized
   \`mirror/playgta5.com/b/8b0b5899ed/game.wasm\` to a controlled macOS build.
   The GitHub repo deliberately does not contain this binary. The recorded
   snapshot describes a 63,201,802-byte Emscripten memory64/pthread module
   with 86 imported functions, a large code section, and a 3 GiB initial
   shared memory requirement. Preserve the upstream binary unchanged.
2. **AOT feasibility:** Validate this exact module against a specific compiler
   that supports shared memory, pthread imports and memory64. Produce/link
   real ARM64 object code and reproduce thread/TLS/init semantics, or document
   a specific feature incompatibility. Do not claim wasm2c/LLVM portability
   merely because an SDK can open a .wasm header.
3. **Native host ABI:** Implement all imported WASI/Emscripten platform calls,
   engine-specific USB paging, graphics command submission, audio, pthread
   lifecycle, clock and save handling. An import-by-import harness must
   distinguish implemented from unsupported functions.
4. **Metal graphics:** Adapt WebGPU/D3D-facing command and resource semantics to
   Metal; translate the actual shader blobs, implement pipelines/textures/
   depth/render passes, and verify correct in-world frames. A Metal clear pass
   alone does not make a native renderer.
5. **Controller mapping:** Bind GameController analog/buttons to the actual
   engine's native gamepad ABI. Driving analog pedals/steering, gameplay
   menus, touch controls and haptic events need functional engine testing.
6. **Original loading and gameplay:** Launch RAGE, load original assets and
   shader data directly from USB, present only actual engine loading progress
   and genuine frames, and confirm audio, saves, stable gameplay on the actual
   iPhone 16. No mocked "game started" screen.
7. **JIT policy:** AOT is preferred and requires no executable-page allocation.
   Use Madeira's JIT allocations only if a chosen translation runtime genuinely
   needs dynamic code and the user's iOS signing/debugger environment permits
   it. Wine/FEX translates x86 instructions and does not execute WASM modules.

## How to build

Run **Build GTAiOS Unsigned IPA** on branch \`ios-usb-port\`, or on macOS:

\`\`\`sh
python3 ios/Scripts/verify_native_runtime.py
brew install xcodegen
xcodegen generate --spec ios/project.yml --project ios
xcodebuild -project ios/GTAiOS.xcodeproj -scheme GTAiOS \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
\`\`\`

Only after a real engine implementation reaches a controllable world frame can
the deliverable be described as playable GTA V. Until then, this build is a
native device/storage/graphics-readiness harness. This is deliberate: no
WebKit loading-screen illusion, no remote streaming, no duplicated game
archives, no unsupported claims of completed conversion.


## Native WASM → ARM64 AOT tooling (tested separately)

The `ios/Scripts/aot_compile.sh` and `aot_import_audit.py` tools now
offer a reproducible native code-generation path for an authorized WASM
module. `.github/workflows/native-aot.yml` has successfully cross-compiled
a synthetic shared-memory64 WASM module into an iPhone ARM64 Mach-O object
in GitHub Actions (run 37860594587). See `ios/Scripts/AOT_README.md`.

This CI success tests the toolchain only. The actual 63 MB GTA `game.wasm`
is not in this repository or CI, has not been converted, and cannot yet be
linked to native Emscripten/WASI host functions or the real Metal renderer.
No JIT executor or playable engine is included. The native IPA remains a
hardware/USB/format readiness harness, NOT a GTA V port.


## Real uploaded game.wasm — engine conversion check

The exact uploaded 63,201,802-byte game binary passed WABT WASM
validation but **failed native C translation**. WABT `wasm2c`
aborted when it encountered `memory.atomic.notify` /
`memory.atomic.wait32`, which the C writer does not implement.
The new `aot_feature_gate.py` prevents truncated C output and
documents the blocker in `ios/Scripts/ENGINE_REAL_AOT_REPORT.md`.
The game is still not playable; the native IPA remains a hardware/USB
readiness harness.


## Genuine GTA engine compiled into ARM64 code (not playable yet)

Wasmtime 49.0.2 compiled the uploaded real engine to an AArch64
serialized ELF artifact targeting `aarch64-apple-ios`.
This output is not a standalone iOS Mach-O or a functioning game.
An iOS Wasmtime runtime/executable mapping, the 85 host imports, native
WebGPU-to-Metal rendering, gamepad game ABI, audio and actual-world
verification remain required. See `ios/Scripts/ENGINE_REAL_AOT_REPORT.md`.
