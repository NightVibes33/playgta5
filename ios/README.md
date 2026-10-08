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
