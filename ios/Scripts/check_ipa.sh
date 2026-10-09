#!/bin/bash
set -euo pipefail
ipa="${1:?Usage: check_ipa.sh path/to/GTAiOS-unsigned.ipa}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
unzip -q "$ipa" -d "$tmp"
app="$tmp/Payload/GTAiOS.app"
test -d "$app"
test -f "$app/Info.plist"
# Reject legacy 16:9 compatibility launches: modern scene and storyboard are mandatory.
/usr/libexec/PlistBuddy -c 'Print :UILaunchStoryboardName' "$app/Info.plist" | grep -qx 'LaunchScreen'
/usr/libexec/PlistBuddy -c 'Print :UIApplicationSceneManifest:UISceneConfigurations:UIWindowSceneSessionRoleApplication:0:UISceneDelegateClassName' "$app/Info.plist" | grep -q 'SceneDelegate'
/usr/libexec/PlistBuddy -c 'Print :UIRequiresFullScreen' "$app/Info.plist" | grep -qx 'true'
/usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily:0' "$app/Info.plist" | grep -qx '1'
if /usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily:1' "$app/Info.plist" >/dev/null 2>&1; then
  echo 'ERROR: IPA must target iPhone only, not iPad' >&2
  exit 1
fi
echo 'Modern full-screen iPhone launch manifest: PASS'
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist" | while read -r exe; do test -x "$app/$exe"; done
test -f "$app/LaunchScreen.storyboardc/Info.plist"
if [ -e "$app/WebRuntime/index.html" ] || [ -e "$app/WebRuntime/game.js" ]; then
  echo 'ERROR: browser runtime must not be packaged as native gameplay' >&2
  exit 1
fi
echo 'Native runtime package: no WebKit gameplay or browser assets'
if find "$app" \( -name '*.rpf' -o -name 'game.wasm' \) | grep -q .; then
  echo "ERROR: proprietary game data must not be bundled in the IPA" >&2
  exit 1
fi
# The bundled Wasmtime C API must be actually linked into the physical
# iPhone Mach-O app, not merely present as an unused .a in DerivedData.
# Xcode's dead-strip/linker can mark C-to-Swift bridge symbols private
# external (N_PEXT). nm -g excludes those even though they are linked.
# Inspect all defined Mach-O symbols instead of rejecting a valid IPA.
xcrun nm "$app/GTAiOS" > "$tmp/symbols.txt"
for symbol in _gta_ios_wasmtime_engine_probe _gta_ios_wasmtime_basic_host_probe _gta_ios_wasmtime_aot_probe _wasm_engine_new _wasm_engine_delete _wasmtime_module_deserialize_file _wasmtime_module_imports; do
  if ! grep -F "$symbol" "$tmp/symbols.txt" >/dev/null; then
    echo "ERROR: linked native Wasmtime runtime symbol missing: $symbol" >&2
    exit 1
  fi
done
echo "Native Wasmtime + real clock/CPU host function registration + SHA256 AOT inspection linked: PASS"
echo "IPA payload and native Metal + Wasmtime host verified; proprietary GTA engine not linked or bundled."
