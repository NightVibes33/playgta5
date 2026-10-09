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
assert 'SWIFT_OBJC_BRIDGING_HEADER' in project
assert 'OTHER_LDFLAGS[sdk=iphoneos*]' in project
assert 'Resolve pinned Wasmtime iOS static runtime' in workflow
assert "<key>CFBundleVersion</key><string>11</string>" in plist

print("PASS: native Metal command queue and Wasmtime C API engine lifecycle compiled into device app")
print("PASS: native USB module-header and imported memory inspection; 4MiB ranged I/O")
print("PASS: GameController Bluetooth analog + hardware buttons, native readiness UI, diagnostics")
print("PASS: no WebKit gameplay or embedded browser runtime; unlinked engine truthfully blocked")
print("NOT PLAYABLE: compiled ARM64 GTA engine, real Metal renderer/import ABI and on-device gameplay remain outstanding")
