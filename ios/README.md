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
