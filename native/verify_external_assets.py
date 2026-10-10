#!/usr/bin/env python3
"""Read-only validation of the user library and asset-free native IPA."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import sys
import zipfile

BUILD = '8b0b5899ed'
ENGINE_HASH = '11ca8d2c04c5e843d18ff4aea4899d72c86973c6b031df334e67c446b2ae83e0'

def library(selected):
    candidates = [selected / suffix for suffix in ('', 'playgta5.com', 'mirror/playgta5.com', 'mirror/mirror/playgta5.com')]
    root = next((p for p in candidates if (p / 'data/manifest.json').is_file()), None)
    if root is None:
        raise ValueError('No data/manifest.json found beneath the supplied game folder')
    manifest = json.loads((root / 'data/manifest.json').read_text(encoding='utf-8'))
    failures = []
    total = 0
    for entry in manifest['files']:
        name, expected = entry[:2]
        relative = PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts or '\\' in name:
            raise ValueError(f'Unsafe manifest path: {name}')
        path = root / 'data' / name
        if not path.is_file():
            failures.append(f'Missing {name}')
        elif path.stat().st_size != expected:
            failures.append(f'Size mismatch {name}: {path.stat().st_size} != {expected}')
        total += expected
    engine = root / 'b' / BUILD / 'game.wasm'
    digest = hashlib.file_digest(engine.open('rb'), 'sha256').hexdigest()
    if digest != ENGINE_HASH:
        failures.append('Engine SHA-256 does not match the pinned build input')
    if not (root / 'b' / BUILD / 'shaders/index.json').is_file():
        failures.append('Shader index missing')
    result = {'root': str(root), 'manifest_files': len(manifest['files']), 'manifest_bytes': total, 'engine_sha256': digest, 'failures': failures, 'read_only': True}
    print(json.dumps(result, indent=2))
    if failures:
        raise ValueError(f'External library validation failed: {len(failures)} missing or mismatched files')

def package(ipa):
    with zipfile.ZipFile(ipa) as archive:
        entries = archive.infolist()
        plists = [e for e in entries if len(PurePosixPath(e.filename).parts) == 3 and e.filename.startswith('Payload/') and e.filename.endswith('.app/Info.plist')]
        if len(plists) != 1:
            raise ValueError('IPA must contain exactly one application')
        app = str(PurePosixPath(plists[0].filename).parent) + '/'
        info = plistlib.loads(archive.read(plists[0]))
        executable = app + info['CFBundleExecutable']
        if executable not in archive.namelist():
            raise ValueError('Application executable is missing')
        banned = []
        for entry in entries:
            path = PurePosixPath(entry.filename)
            if any(part.lower() in {'data', 'shaders'} for part in path.parts[2:]) or path.suffix.lower() in {'.rpf', '.wasm', '.cwasm'} or path.name.lower() == 'game.zip':
                banned.append(entry.filename)
        if banned:
            raise ValueError('Game data found in IPA: ' + ', '.join(banned[:20]))
        print(json.dumps({'ipa': str(ipa), 'bytes': ipa.stat().st_size, 'bundle_id': info['CFBundleIdentifier'], 'executable_bytes': archive.getinfo(executable).file_size, 'external_game_assets': True, 'gameplay_verified': False}, indent=2))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-root', type=Path)
    parser.add_argument('--ipa', type=Path)
    args = parser.parse_args()
    if not args.game_root and not args.ipa:
        parser.error('Supply --game-root or --ipa')
    try:
        if args.game_root: library(args.game_root)
        if args.ipa: package(args.ipa)
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        sys.exit(str(error))
