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
assert 'ADVANCED  ·  FILE PICKER TESTS' in launcher
assert 'CHECK NATIVE RUNTIME' in launcher
assert 'The local server runs inside the app' not in launcher
assert 'GTAiOS' in splash and 'NATIVE RUNTIME  /  SIDELOADED' in splash
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
assert 'registered != 10' in game
assert 'native-input-abi.test.c' in workflow

assert 'wasmtime_linker_define_func' in host
assert 'wasmtime_linker_get' in host
assert 'wasmtime_func_call' in host
assert 'CLOCK_MONOTONIC' in host and 'CLOCK_REALTIME' in host
assert 'emscripten_num_logical_cores' in host
assert 'wasm_now_ms' in host
assert 'gta_ios_wasmtime_basic_host_probe' in game
assert 'registered != 10' in game
assert 'native-aot-smoke' in game
assert 'gta_ios_wasmtime_execute_smoke' in game
assert 'gta_ios_wasmtime_execute_smoke' in read("ios/Sources/Engine/NativeAOTExecutionProbe.c")
assert 'wasmtime_linker_instantiate' in read("ios/Sources/Engine/NativeAOTExecutionProbe.c")
assert 'wasmtime_instance_export_get' in read("ios/Sources/Engine/NativeAOTExecutionProbe.c")
assert 'WASMTIME_I32' in read("ios/Sources/Engine/NativeAOTExecutionProbe.c")
assert 'wasm_has_page_js' in host
assert 'wasm_userdata_page_js' in host
assert 'emscripten_check_blocking_allowed' in host
assert 'gta_define_void' in host
assert 'native-aot-smoke.cwasm' in workflow
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
assert "<key>CFBundleVersion</key><string>20</string>" in plist

print("PASS: native Metal/Wasmtime, shared memory64 AOT fixture with native controller press/release guest readback")
print("PASS: native USB module-header and imported memory inspection; 4MiB ranged I/O")
print("PASS: native Bluetooth and touch control capture, runtime controls, thermal/UI tick diagnostics")
print("PASS: atomic native saves and PCM audio output service present, not yet engine-bound")
print("PASS: no WebKit gameplay or embedded browser runtime; unlinked engine truthfully blocked")
print("NOT PLAYABLE: compiled ARM64 GTA engine, real Metal renderer/import ABI and on-device gameplay remain outstanding")
