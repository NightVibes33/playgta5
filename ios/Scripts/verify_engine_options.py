#!/usr/bin/env python3
"""CI contract check: native settings must map to existing homepage.html controls."""
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
web = (repo / "homepage.html").read_text()
engine = (repo / "ios/Sources/Engine/EngineOptions.swift").read_text()
game = (repo / "ios/Sources/UI/GameViewController.swift").read_text()
host = (repo / "ios/Sources/UI/LauncherViewController.swift").read_text()
plist = (repo / "ios/Config/Info.plist").read_text()

params = ["mode", "map", "newgame", "fps", "scale", "low", "cores",
          "nocache", "nohints", "nopack", "syncpipelines", "verbose", "trace", "mem"]
flags = ["textureQuality", "shadowQuality", "reflectionQuality", "particleQuality",
         "grassQuality", "cityDensity", "lodScale", "pedVariety",
         "vehicleVariety", "pedLodBias", "vehicleLodBias"]
for p in params:
    assert f"q.get('{p}')" in web, f"unrecognized web runtime query: {p}"
    assert f'id: "{p}"' in engine or f'URLQueryItem(name: "{p}"' in engine, f"UI missing {p}"
for key in flags:
    assert f"-{key}=" in web, f"engine LOW_ARGS missing {key}"
    assert f'id: "{key}"' in engine, f"settings missing {key}"
assert 'EngineOptions.launchURL(port: port)' in game
assert 'UISupportedInterfaceOrientations' in plist and 'UILaunchStoryboardName' in plist
assert 'navigationController?.setNavigationBarHidden(true' in host
assert 'ControllerSettingsViewController' in host
assert '-frameLimit=' in web
print(f"PASS: {len(params)} query controls, {len(flags)} verified engine switches, game launch binding, full-screen launch storyboard")
