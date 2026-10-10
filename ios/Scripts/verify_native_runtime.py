#!/usr/bin/env python3
"""Native-only regression contract for the iOS A18 foundation.

This is NOT a gameplay test: proprietary game.wasm and a native ARM64 RAGE
engine are not checked into the repository. Do not let a green CI build be
mistaken for native GTA V execution.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
read = lambda p: (root / p).read_text(encoding="utf-8")
native = read("ios/Sources/Engine/NativeEngineSupport.swift")
game = read("ios/Sources/UI/GameViewController.swift")
project = read("ios/project.yml")
workflow = read(".github/workflows/build-ios-ipa.yml")
ipa = read("ios/Scripts/check_ipa.sh")
input_source = read("ios/Sources/Input/ControllerManager.swift")
usb = read("ios/Sources/Storage/USBStorageManager.swift")
scene = read("ios/Sources/App/SceneDelegate.swift")
plist = read("ios/Config/Info.plist")

assert "import MetalKit" in native and "class NativeMetalSurface: MTKView, MTKViewDelegate" in native
assert "MTLCreateSystemDefaultDevice()" in native
assert "makeCommandQueue()" in native and "makeRenderCommandEncoder" in native
assert "import WebKit" not in game, "Game screen may not import WebKit"
assert "WKWebView" not in game.replace('Browser/WKWebView gameplay disabled', ''), "Native gameplay may not instantiate WebKit"
assert "AssetHTTPServer" not in game
assert "NativeEngineStatus.inspect" in game
assert "nativeEngineLinked = false" in native, "Absent linked engine must not claim playable"
probe_swift = read("ios/Sources/Engine/NativeAOTModuleProbe.swift")
probe_c = read("ios/Sources/Engine/NativeAOTModuleProbe.c")
probe_header = read("ios/Sources/Engine/NativeWasmtimeHost.h")
assert "NativeAOTModuleProbe.inspect" in game
assert "wasmtime_module_deserialize_file" in probe_c
assert "wasmtime_module_imports" in probe_c
assert "wasm_importtype_vec_delete" in probe_c
assert "wasmtime_config_wasm_threads_set" in probe_c
assert "wasmtime_config_wasm_memory64_set" in probe_c
assert "gta_ios_wasmtime_aot_probe" in probe_header
assert "NativeAOTModuleProbe" in probe_swift
assert "NSFileCoordinator" in probe_swift and "import CryptoKit" in probe_swift
assert "allowedSHA256" in probe_swift and "238_815_736" in probe_swift
assert "gta_ios_wasmtime_aot_probe" in probe_swift
assert "GameController" not in probe_c, "AOT import audit must not fake game input"
assert "wasmtime_instance_new" not in probe_c, "do not instantiate until all GTA host imports are supported"

assert "game.wasm" in native and "shaders/index.json" in native
assert "Data([0, 97, 115, 109, 1, 0, 0, 0])" in native
assert "memory64:" in native and "minimumPages:" in native and "maximumPages:" in native
assert "NativeUSBAssetReader" in native
assert "NSFileCoordinator" in native and "length <= 4 * 1024 * 1024" in native
assert "startAccessingSecurityScopedResource()" in usb
touch = read("ios/Sources/Input/NativeTouchControlsView.swift")
audio = read("ios/Sources/Engine/NativePCMOutput.swift")
save = read("ios/Sources/Engine/NativeGameSaveStore.swift")
launcher = read("ios/Sources/UI/LauncherViewController.swift")
splash = read("ios/Sources/Resources/LaunchScreen.storyboard")
assert "class NativeInputState" in touch and "class NativeTouchControlsView" in touch
assert 'NativeTouchStick(axis: "move")' in touch
assert 'NativeTouchStick(axis: "camera")' in touch
assert 'touchActive' in touch and 'onState' in touch
assert 'NativeInputState.shared.updateHardware(state)' in game
assert 'NativeInputState.shared.updateTouch(values)' in game
assert 'gtaios.touch.visible' in game and 'HIDE TOUCH' in game
assert 'NOT GAME FPS' in game and 'thermalState' in game
assert 'class NativeGameSaveStore' in save
assert '32 * 1024 * 1024' in save and 'Data(contentsOf:' in save
assert 'options: [.atomic, .completeFileProtectionUnlessOpen]' in save
assert 'class NativePCMOutput' in audio and 'scheduleStereoFloatPCM' in audio
assert 'AVAudioEngine()' in audio and 'AVAudioPlayerNode()' in audio
assert 'File picker troubleshooting' in launcher
assert 'Choose Game Folder' in launcher
assert 'NativeEngineStatus.nativeEngineLinked' in launcher
assert 'playButton.isEnabled = true' in launcher
assert 'if !NativeEngineStatus.nativeEngineLinked' in launcher
assert 'openGame() // Engine Checks is explicitly not a gameplay launch.' in launcher
assert 'content.addArrangedSubview(LosSantosHeroView())' in launcher
assert 'Select your GTA V folder on USB-C' in launcher
assert 'More options and diagnostics' in launcher
assert 'playGradient.colors' in launcher and 'GTATheme.neonBlue.cgColor' in launcher
assert launcher.index('launchRow.addArrangedSubview(playButton)') < launcher.index('playButton.widthAnchor.constraint(equalTo: launchRow.widthAnchor')
assert launcher.index('continueCard.addArrangedSubview(preview)') < launcher.index('preview.widthAnchor.constraint(equalTo: continueCard.widthAnchor')
assert 'NativeEngineStatus.inspect' in launcher and 'validateFiles()' in launcher
assert 'USBStorageManager.shared.missingStartupAssets()' in launcher
assert 'No FPS, save progress,' in launcher
assert 'Continue Playing' in launcher
assert 'GTA V ONLY' in launcher
assert 'STORY' not in launcher and 'FREE ROAM' not in launcher
assert 'TEST WORLD' not in launcher and 'Session profile' not in launcher
assert 'The local server runs inside the app' not in launcher
assert 'GTAiOS' in splash and 'LOS SANTOS  /  NATIVE PORT' in splash
art = read("ios/Sources/UI/LosSantosHeroView.swift")
assert "class LosSantosHeroView" in art
assert '"gtaios-reference-hero"' in art
assert 'heightAnchor.constraint(equalToConstant: 180)' in art
assert 'title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18)' in art
assert "class SunsetSkylineView" in art
assert "GRAND THEFT" in art and "AUTO V" in art
assert "PORT IN PROGRESS" not in art
assert "NATIVE iPHONE PROJECT" not in art
assert "GTATheme.neonPink" in launcher and "LosSantosHeroView()" in launcher
assert 'usbStatusLabel.text = !hasUSB ? "Not connected"' in launcher
assert "documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls:" in launcher
assert "hardwareStatusLabel.text = name ==" in launcher
reference = read("ios/Sources/UI/GTAFiveTabLauncher.swift")
assert "GTAFiveTabController()" in scene
assert "viewControllers = pages.map" in reference
for title in ['"Home"', '"Library"', '"Graphics"', '"Controls"', '"More"']:
    assert title in reference
assert "ControllerSettingsViewController()" in reference
assert "GTAReferenceLibraryController" in reference
assert "GTAReferenceGraphicsController" in reference
assert "NativeEngineStatus.inspect" in reference
assert "USBStorageManager.shared.chooseAsync" in reference
assert "EngineOptions.set" in reference and "EngineOptions.value" in reference
assert "LogStore.shared.exportURL()" in reference
assert "NativeEngineStatus.nativeEngineLinked" in reference
assert '"gtaios-reference-home"' in reference
assert '"gtaios-library-skyline"' in reference
assert '"gtaios-settings-hero"' in reference
assert "GTATheme.section" in read("ios/Sources/UI/SettingsViewController.swift")
assert "GTATheme.section" in read("ios/Sources/UI/ControllerSettingsViewController.swift")
assert "import GameController" in input_source
for control in ["leftThumbstick", "rightThumbstick", "leftTrigger", "rightTrigger",
                "buttonA", "buttonB", "buttonX", "buttonY", "buttonMenu",
                "buttonOptions", "leftThumbstickButton", "rightThumbstickButton"]:
    assert control in input_source, control
assert "UIImage(systemName:" in game
assert "GTAiOS-diagnostics.txt" in read("ios/Sources/Support/LogStore.swift")
assert "UIWindow(windowScene: windowScene)" in scene
assert "WebRuntime" not in project, "Do not bundle HTML/JS engine into native IPA"
assert "Engine/RuntimeDiagnostics.swift" in project and "Storage/AssetHTTPServer.swift" in project
assert "prepare_runtime.sh" not in workflow
assert "verify_native_runtime.py" in workflow
assert 'if [ -e "$app/WebRuntime/index.html" ]' in ipa
assert 'wasm_engine_new()' in read("ios/Sources/Engine/NativeWasmtimeHost.c")
assert 'wasm_engine_delete(engine)' in read("ios/Sources/Engine/NativeWasmtimeHost.c")
assert 'gta_ios_wasmtime_engine_probe()' in game
host = read("ios/Sources/Engine/NativeWasmHostBasics.c")
assert 'gta_ios_wasmtime_basic_host_probe' in host
input_abi = read("ios/Sources/Input/NativeGameInputABI.c")
input_header = read("ios/Sources/Input/NativeGameInputABI.h")
assert 'GTA_WASM_INPUT_BLOCK_BYTES 444' in input_header
assert 'gta_native_input_publish_block' in input_abi and 'gta_native_input_bind_memory' in input_abi
assert 'gta_native_input_apply' in input_abi and 'WORD_BUTTONS' in input_abi
assert 'gta_define_input_callback' in host and 'wasm_input_publish_js' in host
assert 'gta_native_input_apply(&pad)' in game
manifest_c = read("ios/Sources/Engine/NativeHTTPFSManifestABI.c")
manifest_h = read("ios/Sources/Engine/NativeHTTPFSManifestABI.h")
assert 'gta_httpfs_manifest_stage' in manifest_c
assert 'gta_httpfs_manifest_js' in manifest_c
assert 'gta_httpfs_manifest_js' in manifest_h
assert 'gta_define_manifest_callback' in host
assert 'wasm_httpfs_manifest_js' in host
assert 'stageHTTPFSManifest()' in native
assert 'data/manifest.json' in native
assert 'native-httpfs-manifest.test.c' in workflow
assert 'registered != 23' in game
assert 'native-input-abi.test.c' in workflow

assert 'wasmtime_linker_define_func' in host
assert 'wasmtime_linker_get' in host
assert 'wasmtime_func_call' in host
assert 'CLOCK_MONOTONIC' in host and 'CLOCK_REALTIME' in host
assert 'emscripten_num_logical_cores' in host
assert 'wasm_now_ms' in host
assert 'gta_ios_wasmtime_basic_host_probe' in game
assert 'registered != 23' in game
assert 'native-aot-smoke' in game
assert 'gta_ios_wasmtime_execute_smoke' in game
assert 'gta_ios_wasmtime_execute_smoke' in read("ios/Sources/Engine/NativeAOTExecutionProbe.c")
assert 'wasmtime_linker_instantiate' in read("ios/Sources/Engine/NativeAOTExecutionProbe.c")
assert 'wasmtime_instance_export_get' in read("ios/Sources/Engine/NativeAOTExecutionProbe.c")
assert 'WASMTIME_I32' in read("ios/Sources/Engine/NativeAOTExecutionProbe.c")
assert 'wasm_has_page_js' in host
assert 'wasm_userdata_page_js' in host
for name in ['wasm_print_line_js', 'wasm_hang_line_js', 'wasm_module_int_js']:
    assert name in host, name
assert 'gta_define_text_callbacks' in host
assert 'gta_text_host_next_log' in game
assert 'NativeTextHostABI.h' in read("ios/Sources/Engine/NativeWasmtimeHost.h")
assert 'NativeTextHostABI.c' in workflow
assert 'native-userdata-abi.test.c' in workflow
assert 'native-wasi-abi.test.c' in workflow
assert 'gta_define_userdata_callbacks' in host
assert 'gta_define_wasi_callbacks' in host
wasi=read('ios/Sources/Engine/NativeWASIHostABI.c')
for callback in ['gta_wasi_clock_time_get','gta_wasi_environ_sizes_get','gta_wasi_environ_get']:
    assert callback in wasi
assert 'gta_wasi_unbind_memory' in wasi
assert 'wasm_userdata_put_js' in host and 'wasm_userdata_delete_js' in host
assert 'NativeUserdataHostABI.h' in read('ios/Sources/Engine/NativeWasmtimeHost.h')
assert 'gta_userdata_set_root' in game
assert 'gta_userdata_take_error()' in game
assert 'native-text-abi.test.c' in workflow
assert 'GTA_TEXT_SOURCE_MAX 4096' in read("ios/Sources/Engine/NativeTextHostABI.c")
assert 'GTA_TEXT_QUEUE 32' in read("ios/Sources/Engine/NativeTextHostABI.c")
assert 'emscripten_check_blocking_allowed' in host
assert 'gta_define_void' in host
assert 'native-aot-smoke.cwasm' in workflow
assert workflow.count('-W gc-support=n,threads=y,shared-memory=y,memory64=y') == 2
assert '-W gc-support=n,threads=y,shared-memory=y,memory64=y' in read('ios/Scripts/aot_compile_wasmtime.sh')
for name in ['NativeAOTExecutionProbe.c', 'NativeAOTMemoryProbe.c', 'NativeAOTModuleProbe.c']:
    assert 'wasmtime_config_gc_support_set(' in read('ios/Sources/Engine/' + name)
assert 'setNeedsUpdateOfSupportedInterfaceOrientations()' in game
assert '.allButUpsideDown' in read('ios/Sources/UI/GameNavigationController.swift')
memory_probe = read("ios/Sources/Engine/NativeAOTMemoryProbe.c")
assert 'wasmtime_memorytype_new(1, true, 2, true, true, 16' in memory_probe
assert 'wasmtime_sharedmemory_new' in memory_probe
assert 'wasmtime_linker_define' in memory_probe
assert 'wasmtime_linker_instantiate' in memory_probe
assert 'wasmtime_sharedmemory_data_size(memory) != 65536' in memory_probe
assert 'answer.of.i32 != 42 || observed != 42' in memory_probe
assert 'gta_native_input_bind_memory(wasmtime_sharedmemory_data(memory)' in memory_probe
assert 'gta_native_input_publish_block(INPUT_BLOCK)' in memory_probe
assert 'gta_native_input_apply(&pad)' in memory_probe
assert 'key_pressed.of.i32 != 0x80' in memory_probe
assert 'key_released.of.i32 != 0' in memory_probe
assert 'gta_native_input_unbind()' in memory_probe
assert '(func (export "input_w")' in workflow
assert 'wasmtime_sharedmemory_delete(memory)' in memory_probe
assert 'gta_ios_wasmtime_memory64_smoke' in game
assert 'native-memory64-smoke.cwasm' in workflow
assert 'gta_ios_wasmtime_memory64_smoke' in read("ios/Sources/Engine/NativeWasmtimeHost.h")
assert '_gta_ios_wasmtime_memory64_smoke' in ipa
assert '4ed6a1261747212cc3413319db55c20f9ee48be72d6572dd4513f4febb318fd9' in read('ios/Sources/Engine/NativeAOTModuleProbe.swift')
assert 'case .deserialized(let imports, let linked, let details)' in game
assert 'gta_ios_wasmtime_register_host_basics' in host
assert 'emscripten_get_heap_max' in host
assert 'WASMTIME_I64' in host
assert 'INT64_C(17179869184)' in host
assert 'gta_types_match' in probe_c
assert 'wasmtime_linker_get' in probe_c
assert 'covered_count' in probe_c
assert 'wasmtime_instance_new' not in probe_c
assert 'wasmtime_linker_define_unknown_imports_as_default_values' not in host
assert 'wasmtime_linker_define_unknown_imports_as_traps' not in host

assert 'SWIFT_OBJC_BRIDGING_HEADER' in project
assert 'OTHER_LDFLAGS[sdk=iphoneos*]' in project
assert 'Resolve pinned Wasmtime iOS static runtime' in workflow
assert 'generate_wasmtime_conf.py' in workflow
assert 'conf.h.in' in workflow
assert 'xcrun nm "' in ipa
assert '_gta_ios_wasmtime_aot_probe' in ipa
assert "<key>CFBundleVersion</key><string>34</string>" in plist
assert '<key>CFBundleIconName</key><string>AppIcon</string>' in plist
assert "ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon" in project
assert "GTA V iOS icon metadata and compiled Assets.car: PASS" in ipa
import json
import struct
icon_root = root / "ios/Sources/Resources/Assets.xcassets/AppIcon.appiconset"
manifest = json.loads((icon_root / "Contents.json").read_text(encoding="utf-8"))
assert manifest["images"] == [{"filename": "AppIcon-1024.png",
    "idiom": "universal", "platform": "ios", "size": "1024x1024"}]
icon_data = (icon_root / "AppIcon-1024.png").read_bytes()
assert icon_data[:8] == b"\x89PNG\r\n\x1a\n"
assert struct.unpack(">II", icon_data[16:24]) == (1024, 1024)

print("PASS: native Metal/Wasmtime, shared memory64 AOT fixture with native controller press/release guest readback")
print("PASS: native USB module-header and imported memory inspection; 4MiB ranged I/O")
print("PASS: native Bluetooth and touch control capture, runtime controls, thermal/UI tick diagnostics")
print("PASS: atomic native saves and PCM audio output service present, not yet engine-bound")
print("PASS: no WebKit gameplay or embedded browser runtime; unlinked engine truthfully blocked")
print("NOT PLAYABLE: compiled ARM64 GTA engine, real Metal renderer/import ABI and on-device gameplay remain outstanding")
