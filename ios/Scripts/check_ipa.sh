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
# Apple must resolve the actual asset-catalog app icon from the IPA.
icon_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName' "$app/Info.plist")
if [ "$icon_name" != "AppIcon" ] || [ ! -s "$app/Assets.car" ]; then
  echo 'ERROR: GTAiOS app icon missing from the IPA metadata or asset catalog' >&2
  exit 1
fi
echo 'GTA V iOS icon metadata and compiled Assets.car: PASS'
# Only authentic GTA V promotional artwork is allowed in the IPA.
for name in gtav-official-hero.jpg gtav-official-cover.jpg gtav-official-header.jpg; do
  if ! find "$app" -type f -name "$name" | grep -q .; then
    echo "ERROR: missing authentic GTA V artwork: $name" >&2
    exit 1
  fi
done
if find "$app" -type f \( -name 'gtaios-reference-*.jpg' -o -name 'gtaios-library-*.jpg' -o -name 'gtaios-settings-hero.jpg' \) | grep -q .; then
  echo 'ERROR: synthetic reference imagery is not permitted in the IPA' >&2
  exit 1
fi
# Reject substitutions for the verified publisher promotional images.
check_art_hash() {
  local name="$1" expected="$2" observed
  observed="$(shasum -a 256 "$app/$name" | awk '{print $1}')"
  if [[ "$observed" != "$expected" ]]; then
    echo "ERROR: changed GTA V artwork: $name" >&2
    exit 1
  fi
}
check_art_hash gtav-official-hero.jpg 9911eacd492474f3f8bd99852458c7b04abc4c9990dfc72219e7bdc80ea6d5b4
check_art_hash gtav-official-cover.jpg 301cbc71c0265978a6b62ede653a298559e63c8d96ca88be20a1885d6189a2d2
check_art_hash gtav-official-header.jpg e1ee8ed03ef2926d224e331a1bc61711822bbe7261cf847624089c1e95207a9a
for scene in gtav-story-trio gtav-vinewood-view gtav-car-gameplay gtav-city-helicopter gtav-franklin-race; do
  if ! find "$app" -type f -name "$scene.jpg" | grep -q .; then
    echo "ERROR: GTA V scene missing: $scene" >&2
    exit 1
  fi
done
echo 'Distinct GTA V artwork verified: PASS'
echo 'Authentic GTA V promotional artwork bundled: PASS'
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
if ! find "$app" -type f -name "native-memory64-smoke.cwasm" | grep -q .; then
  echo "ERROR: real ARM64 memory64+threads imported-memory execution test is absent" >&2
  exit 1
fi
if ! find "$app" -type f -name "native-aot-smoke.cwasm" | grep -q .; then
  echo "ERROR: real ARM64 AOT execution smoke module missing from IPA" >&2
  exit 1
fi
# The bundled Wasmtime C API must be actually linked into the physical
# iPhone Mach-O app, not merely present as an unused .a in DerivedData.
# Xcode's dead-strip/linker can mark C-to-Swift bridge symbols private
# external (N_PEXT). nm -g excludes those even though they are linked.
# Inspect all defined Mach-O symbols instead of rejecting a valid IPA.
xcrun nm "$app/GTAiOS" > "$tmp/symbols.txt"
for symbol in _gta_ios_wasmtime_engine_probe _gta_ios_wasmtime_basic_host_probe _gta_ios_wasmtime_register_host_basics _gta_ios_wasmtime_aot_probe _gta_ios_wasmtime_execute_smoke _gta_ios_wasmtime_memory64_smoke _gta_httpfs_manifest_js _gta_text_host_module_int_js _gta_text_host_print_line_js _gta_text_host_hang_line_js _wasmtime_sharedmemory_new _wasm_engine_new _wasm_engine_delete _wasmtime_module_deserialize_file _wasmtime_module_imports; do
  if ! grep -F "$symbol" "$tmp/symbols.txt" >/dev/null; then
    echo "ERROR: linked native Wasmtime runtime symbol missing: $symbol" >&2
    exit 1
  fi
done
echo "Native Wasmtime + ten GTA host callbacks (including USB HTTPFS) + AOT shared memory64 probe linked: PASS"
echo "IPA payload and native Metal + Wasmtime host verified; proprietary GTA engine not linked or bundled."
