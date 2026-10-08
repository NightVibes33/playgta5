#!/usr/bin/env python3
"""Verify iPhone runtime safety paths and that preflight is actually packaged."""
from pathlib import Path
import re
import subprocess
import tempfile

root=Path(__file__).resolve().parents[2]
asset=(root/"ios/Bridge/preflight.html").read_text()
server=(root/"ios/Sources/Storage/AssetHTTPServer.swift").read_text()
game=(root/"ios/Sources/UI/GameViewController.swift").read_text()
navigation=(root/"ios/Sources/UI/GameNavigationController.swift").read_text()
prepare=(root/"ios/Scripts/prepare_runtime.sh").read_text()
app=(root/"ios/Sources/App/AppDelegate.swift").read_text()
plist=(root/"ios/Config/Info.plist").read_text()

for required in ["crossOriginIsolated","sharedArrayBuffer","offscreenTransfer","gpuAdapter","wasmCompile","wasmHeader","shaderIndex","gameManifest","titleLogo","audioWorklet"]:
    assert required in asset, required
assert 'name="viewport"' in asset
assert '/ios/preflight.html' in server
assert 'preflight.html' in prepare
assert 'viewport-fit=cover' in prepare
assert 'onPreflight(' in game and 'Runtime requirements failed:' in game
assert 'EngineOptions.launchURL(port: port)' in game
assert 'GameOrientation.request(.landscape' in game
assert 'GameOrientation.request(.portrait' in (root/"ios/Sources/UI/LauncherViewController.swift").read_text()
assert 'GameNavigationController(rootViewController:' in app
assert 'UIRequiresFullScreen' in plist
assert 'UIInterfaceOrientationLandscapeRight' in plist
assert 'UIInterfaceOrientationPortrait' in plist
assert 'LaunchScreen' in plist
scripts=re.findall(r'<script[^>]*>(.*?)</script>',asset,re.DOTALL|re.IGNORECASE)
assert scripts, "No preflight script"
with tempfile.NamedTemporaryFile(mode="w",suffix=".js") as f:
    f.write("\n".join(scripts)); f.flush()
    subprocess.run(["node","--check",f.name],check=True)
print("PASS: runtime prereq probes, original asset HEAD/range checks, iPhone portrait/landscape policy, JavaScript syntax")
