# GTAiOS — USB-first native host

This branch adds a separate, unsigned iPhone host without replacing the original browser runtime.

## Build

Run the GitHub Actions workflow `Build GTAiOS Unsigned IPA` on `ios-usb-port`. The workflow generates a project with XcodeGen, compiles for a physical iPhone (arm64), packages `Payload/GTAiOS.app`, and uploads the unsigned IPA. The IPA must be signed by SideStore or a compatible signing service before installation.

Local Mac:
```sh
bash ios/Scripts/prepare_runtime.sh
xcodegen generate --spec ios/project.yml --project ios
xcodebuild -project ios/GTAiOS.xcodeproj -scheme GTAiOS -sdk iphoneos -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## USB layout

Select the directory containing `data/` (usually `mirror/playgta5.com`) through Files. The external storage layout expected by the original web runtime is:

```
playgta5.com/
├── data/                          # game content, large RPF archives
└── b/8b0b5899ed/
    ├── game.wasm                 # missing from this public repository
    ├── shaders/index.json
    ├── shaders/pack*.bin
    ├── title/                    # original artwork and loading assets
    └── ...
```

Web-facing JavaScript bootstrap files come from the repository and are copied into the small IPA. Game assets stay on the USB drive. A local Network.framework HTTP endpoint on 127.0.0.1 implements GET/HEAD file serving, byte ranges, and `/data/batch`.

## Diagnostic limitations

This is a **compile-target integration build**, not a verified playable GTA V port. The browser snapshot's gameplay was not verified in the repository. iOS WebKit compatibility must be measured on a real device:

* `crossOriginIsolated`, SharedArrayBuffer, worker and OffscreenCanvas support
* WebGPU/Metal adapter features and shader pipeline creation
* WebAssembly memory footprint, threading and optional JIT availability
* Range and batch reads from security-scoped USB folders
* First actual gameplay frame (not merely the title/loading animation)

ControllerManager reads native analog inputs from Apple's GameController framework at 30 Hz. The injected JavaScript currently **falls back to keyboard/mouse events** because the public engine input block does not expose a proven analog-controller ABI. Full native GTA V analog gameplay, haptics and complete touch controls are not yet implemented and must not be presented as passing tests.

For USB-constrained devices we start with low-memory settings and disable the web runtime's bulk browser data cache. Saves remain under the web origin's IndexedDB. Game assets and proprietary code must be supplied by someone with appropriate rights; this project does not fetch or redistribute them.

## Failure triage

The app exports `GTAiOS-diagnostics.txt` with boot, engine, renderer, shader, JIT probe, USB, controller and crash information. An IPA build passing CI proves native compilation and packaging only, not game execution.

## Exact portable mirror structure (README.md and Launch-Local.cmd)

The original Windows launcher runs `runtime\\python.exe serve_local.py --open`.
The Python server serves the `mirror/playgta5.com` tree at `http://localhost:8000/`,
including `data/`, `b/`, `index.html`, `favicon.ico` and `robots.txt`.

The iOS launcher cannot execute a Windows `.cmd` or Windows Python binary.
Instead, the Swift app starts an equivalent **127.0.0.1 local server** automatically.
WebKit loads a copy of the repository's audited `homepage.html` at the local
origin, while the source-level workers, shaders, `game.wasm`, loading-art assets
and the large GTA file tree are read from the selected external directory.

The iOS folder picker accepts any of:

- `mirror/`
- `mirror/playgta5.com/`
- a parent directory containing `mirror/playgta5.com/`

The startup validator checks `data/`, `b/8b0b5899ed/game.wasm`,
`b/8b0b5899ed/shaders/index.json`, `b/8b0b5899ed/title/`, and
`b/8b0b5899ed/audio-worklet.js`. It reports missing paths and permits a
diagnostic boot; it does not block on scanning or duplicating 20 GB of content.

The original repository's `data-manifest.json` is now bundled into the small
IPA and exposed to the engine as `/data/manifest.json` if the USB directory
has no corresponding manifest. `shader-index.json` has the same fallback
behavior. The manifest is an inventory, not a replacement for game bytes.

## Controller changes

The native reader samples extended Bluetooth/wired gamepads at 60 Hz,
including analog sticks, triggers, L3/R3, Menu and available Options, with
deadzone and vertical-axis inversion. A native controller setup/test screen
shows the live state, supports button remapping, and can request haptics on
devices that advertise controller vibration support. The launcher supports
D-pad/stick focus and A-button activation.

The gameplay bridge now writes right-stick deltas and aiming/firing buttons to
the existing WASM mouse input buffer. It also supports on-foot, vehicle and
aircraft digital-key profiles and remapped buttons. It cannot provide true
analog steering/throttle or guarantee full in-game controller-only navigation
without the compiled game engine exposing a native gamepad ABI; that limitation
remains and must be tested on device. No engine-side XInput interface was
available in the repository to compile or patch.


## Launcher and real engine settings refresh

The fullscreen native dashboard no longer displays the default UINavigationBar above a second giant title. It provides Story Mode, GTA V Sandbox and env_test Sandbox selections, plus a USB data health panel, Game Files, Settings, Controller, and diagnostics. Original GTA loading art is read from the selected external mirror where present. A LaunchScreen.storyboard opts into native full-screen sizing on modern iPhones.

Settings are **only the actual switches present in this repository's homepage.html**: start mode/new game, frame limiter, render scale, low-memory worker behavior, shader packs/synchronous pipeline mode, game data prefetch/cache and trace/verbose/memory diagnostics, and engine quality flags -textureQuality, -shadowQuality, -reflectionQuality, -particleQuality, -grassQuality, -cityDensity, -lodScale, -pedVariety, -vehicleVariety, -pedLodBias and -vehicleLodBias. Higher numeric quality values are explicitly marked experimental, not claimed to be benchmarked, and shader configuration does not imply a native Metal renderer.

EngineOptions.builds the actual runtime URL before each launch; changing settings never requires spoofed on-screen controls. The 60 FPS setting correctly uses ?fps=60 (which homepage.html translates to -frameLimit=1), not ?fps=0 (uncapped). The settings verification script asserts all parameter names exist in the repository's engine entrypoint and CI runs it before the device build.


## iPhone 16 runtime hardening

- The source-controlled homepage now receives a real viewport meta tag in \`prepare_runtime.sh\`; its original 1280×720 GTA loading artwork remains unchanged and scales to the iPhone's display.
- The native launcher requests portrait orientation; gameplay requests landscape through \`UIWindowScene.requestGeometryUpdate\` and a navigation controller that forwards supported orientations.
- Before starting the approximately 63MB \`game.wasm\`, WebKit loads a tiny \`/ios/preflight.html\` page from the same local server. It checks cross-origin isolation, SharedArrayBuffer/Atomics, OffscreenCanvas, WebAssembly compilation, GPU adapter/device access, and lightweight HEAD/range requests for the engine, shader index, game manifest, title artwork and audio worklet.
- Failures show a detailed message with **Export diagnostics**, **Attempt engine anyway** and **Back**; the app does not silently load an incompatible game. Preflight logs report detected WebKit capabilities, no ungrounded JIT entitlement claims.
- Runtime tool controls (input profile and debug export) are hidden behind the small ellipsis control during the original loading screen. The diagnostics banner disappears when the game publishes its world-ready message.
- Hardware controllers still use Apple's GameController API; the input bridge is *not* a native GTA V gamepad ABI and analog gameplay remains unverified. No game files are downloaded or bundled. This commit cannot itself prove GPU compatibility or the game reaching a playable frame on a real iPhone 16.

CI runs \`ios/Scripts/verify_runtime_preflight.py\` and compiles the iPhone ARM64 IPA without signing. A green run is only proof that the native app compiles and the IPA packages.


## iPhone 16 display and USB picker bugfix

The original launcher was observed letterboxed in screenshots, with UIKit button text wrapped vertically. The app now uses a real `UIWindowScene`-owned `UIWindow(windowScene:)` on iPhone rather than creating a window from `UIScreen.main.bounds`, and declares the scene in Info.plist. This is the correct modern iOS window lifecycle; actual full-screen appearance must still be confirmed on an iPhone 16.

The Files/Settings/Controller row now stacks icons above one-line captions. Launch is no longer an inert disabled button when there is no USB folder: pressing it opens Files for selection. The USB status panel is tappable as well.

**External drive selection:** Navigate inside your external drive in the Files picker to `mirror/playgta5.com`. Tap **Open** to select that actual folder (tapping the drive name just opens the drive). The picker also accepts a parent folder or the disk root if iOS grants access to that directory. Root detection checks both `data/` and `b/` and searches up to three folder levels without scanning the 20 GB contents. Rejected selections produce a visible error and `usb-storage.txt` entries with the selected path and reason.

Only a physically installed iPhone build can establish whether the Files provider allows an external folder bookmark to be restored across launches. This update does not claim the GTA runtime itself is playable.

## Root cause of iPhone 16 letterboxing (verified from actual built IPA)

The prior XcodeGen `info.path` generated a new minimal Info.plist and overwrote
the repository's custom `Config/Info.plist`. Inspection of the *built IPA*
showed **no** `UILaunchStoryboardName`, **no** `UIApplicationSceneManifest`, and
a target family of `[1,2]` (iPhone + iPad), despite the source code claiming
an iPhone-only full-screen UI.

The fixed project deliberately disables generated Info.plists and sets
`INFOPLIST_FILE: "$(SRCROOT)/Config/Info.plist"` directly in the target.
`ios/Scripts/check_ipa.sh` now rejects packaging whenever the built app
lacks the modern launch screen, UIWindowSceneDelegate declaration,
UIRequiresFullScreen, or an iPhone-only UIDeviceFamily. Native simulator
screenshots still require review, and a SideStore installation on the
physical iPhone 16 is the final test.

## External USB folder picker rescue (iPhone 16 / iOS 27)

If Open in the Files directory picker stays stuck, the app cannot assume a directory access grant was returned. The launcher now offers two explicit choices:

1. **Select playgta5.com folder:** Apple's documented folder picker. Navigate to mirror/playgta5.com and tap Open. The app validates both the folder and actual game.wasm access before saving its bookmark.
2. **Select index.html instead (USB fallback):** The ordinary HTML file picker. Navigate to mirror/playgta5.com, choose index.html and tap Open. A file selection does not necessarily grant access to sibling files. The app independently coordinates a game.wasm read and checks the data directory. Only a successful verification is accepted.

A file provider may decline folder permission or restrict selected-file scope. There is no supported app-side bypass for such a restriction. When a picker delegate returns, its URL and the outcome are recorded in usb-storage.txt; if the provider never invokes the delegate, the app can only log picker presentation or cancellation.

All assets remain on the external drive; nothing is copied into the IPA. CI tests both selection modes and the file-coordinator validation. A real iPhone and USB drive are still required to test provider access.


## iPhone 16 USB picker freeze / no-response fix

Both Files folder selection and index.html fallback previously invoked synchronous FileManager, security-scoped bookmark and NSFileCoordinator operations inside UIKit's document picker callback. On an external USB drive these operations can block the main thread indefinitely (Apple's Foundation guidance explicitly warns about this). Worse, loading a saved bookmark in USBStorageManager.init and fetching a logo from USB during view refresh could stall the app even before a selection.

The corrected implementation:
- returns immediately from documentPicker(didPickDocumentsAt:) and queues validation on gtaios.usb.files;
- performs bookmark restore and read coordination off the main thread, using an NSLock-protected root/status snapshot and a notification for the launcher;
- avoids recursively listing thousands of data/ entries and reading USB artwork while laying out buttons;
- immediately displays 'Verifying drive permissions…', then provides specific success/permission/asset errors;
- reports an 18-second verification timeout to the UI with exportable log markers FILES CALLBACK RECEIVED, USB_VALIDATION_BEGIN, USB_VALIDATION_OK, USB_VALIDATION_FAILED, USB_VALIDATION_TIMEOUT.

If the system picker itself does not deliver a URL (does not invoke didPickDocumentsAt), the app cannot fabricate permission. In that case usb-storage logs show Files picker presented without a callback; changing the USB file provider or system-side folder selection will be necessary. A physical iPhone/USB test is still required.
