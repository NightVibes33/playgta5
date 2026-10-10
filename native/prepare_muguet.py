#!/usr/bin/env python3
"""Apply the external-folder adapter to the pinned, GPL-licensed Muguet source."""
from pathlib import Path
import subprocess
import sys

base = Path(__file__).resolve().parent
source = base / 'Muguet'
revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
if revision != '75d3576bc4e53f514d75f19f2d397c2b7adc9d05':
    sys.exit('Unsupported Muguet revision; review the adapter before updating the pin')

def replace(path, old, new):
    p = source / path
    text = p.read_text(encoding='utf-8')
    if new in text:
        return
    if text.count(old) != 1:
        sys.exit(f'Upstream adapter context mismatch: {path}')
    p.write_text(text.replace(old, new), encoding='utf-8')

replace('src/config.rs', 'pub fn game_dir() -> PathBuf {\n    support_dir().join("game")\n}', '''static EXTERNAL_GAME: std::sync::Mutex<Option<PathBuf>> = std::sync::Mutex::new(None);

pub fn game_dir() -> PathBuf {
    EXTERNAL_GAME.lock().unwrap().clone().unwrap_or_else(|| support_dir().join("game"))
}

// Read-only mount: never extract, prune, write, or copy the selected library.
pub fn mount_external(selected: &Path) -> anyhow::Result<()> {
    for relative in ["", "playgta5.com", "mirror/playgta5.com", "mirror/mirror/playgta5.com"] {
        let root = selected.join(relative);
        let build = root.join("b/8b0b5899ed");
        if root.join("data/manifest.json").is_file() && build.join("shaders/index.json").is_file() {
            // Validate the manifest before changing the active root.
            let bytes = std::fs::read(root.join("data/manifest.json"))?;
            let manifest: serde_json::Value = serde_json::from_slice(&bytes)?;
            anyhow::ensure!(manifest["files"].is_array(), "Game manifest has no files array");
            let canonical = root.canonicalize()?;
            *EXTERNAL_GAME.lock().unwrap() = Some(canonical);
            return Ok(());
        }
    }
    anyhow::bail!("Select the playgta5.com folder containing data/manifest.json and b/8b0b5899ed/shaders/index.json. Keep the external drive connected.")
}''')
replace('src/import.rs', '    #[no_mangle]\n    pub extern "C" fn muguet_import_error()', '''    #[no_mangle]
    pub extern "C" fn muguet_mount_external(path: *const c_char) -> bool {
        if path.is_null() { return false; }
        let path = unsafe { CStr::from_ptr(path) }.to_string_lossy().into_owned();
        match crate::config::mount_external(std::path::Path::new(&path)) {
            Ok(()) => { *ERROR.lock().unwrap() = None; true },
            Err(e) => { *ERROR.lock().unwrap() = CString::new(format!("{e:#}")).ok(); false }
        }
    }

    #[no_mangle]
    pub extern "C" fn muguet_import_error()''')

swift = (source / 'ios/Launcher.swift').read_text(encoding='utf-8')
start = swift.index('@_silgen_name("muguet_mount_external")') if '@_silgen_name("muguet_mount_external")' in swift else swift.index('@_silgen_name("muguet_import")')
end = swift.index('\nstruct LauncherView: View', start)
adapter = (base / 'ExternalImporter.swift').read_text(encoding='utf-8')
swift = swift[:start] + adapter + swift[end:]
swift = swift.replace('Text("Muguet").font', 'Text("GTAiOS").font')
swift = swift.replace('allowedContentTypes: [.zip]', 'allowedContentTypes: [.folder]')
swift = swift.replace('Text("ImportingÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ \\(Int(p * 100)) %")', 'Text("Checking external game folderÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦")')
swift = swift.replace('Button("Import game data .zip")', 'Button("Select external game folder")')
swift = swift.replace('Button("Import other game dataâ€¦")', 'Button("Choose another game folderâ€¦")')
swift = swift.replace('ProgressView(value: p)', 'ProgressView().accessibilityLabel("Checking game folder")')
swift = swift.replace('This build has no game code: build it with ./make-ios.sh <game.zip>.', 'Compiled engine missing. Install the GTAiOS native engine build.')
(source / 'ios/Launcher.swift').write_text(swift, encoding='utf-8')
replace('ios/Info.plist', '<key>CFBundleDisplayName</key><string>Muguet</string>', '<key>CFBundleDisplayName</key><string>GTAiOS Native</string>')
# Avoid the large optional optimization pass. Original engine input is never changed.
replace('make-ios.sh', 'if command -v wasm-opt >/dev/null; then', 'if [ "${GTAIOS_OPTIMIZE:-0}" = 1 ] && command -v wasm-opt >/dev/null; then')
print('Applied pinned native runtime + external security-scoped folder adapter')

replace('ios/project.yml', '- path: ../assets/muguet.icon', '- path: ../../../ios/Sources/Resources/Assets.xcassets\n      - path: ../../../ios/Sources/Resources/gtav-story-trio.jpg')
replace('ios/project.yml', 'ASSETCATALOG_COMPILER_APPICON_NAME: muguet', 'ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon')
replace('ios/project.yml', 'TARGETED_DEVICE_FAMILY: "1,2"', 'TARGETED_DEVICE_FAMILY: "1"')

replace('ios/Launcher.swift', '            VStack(spacing: 16) {\n                Text("GTAiOS").font(.largeTitle.weight(.bold))', '            ScrollView {\n            VStack(spacing: 16) {\n                Text("GTAiOS").font(.largeTitle.weight(.bold))\n                Image("gtav-story-trio").resizable().scaledToFill()\n                    .frame(height: 100).clipped().accessibilityHidden(true)')
replace('ios/Launcher.swift', '            .padding(24)\n            .frame(maxWidth: .infinity)\n            Form {', '            .padding(24)\n            }\n            .frame(maxWidth: .infinity)\n            Form {')
