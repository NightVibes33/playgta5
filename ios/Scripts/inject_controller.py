#!/usr/bin/env python3
"""Integrate iOS native controller bridge with the repository's existing WASM input ABI."""
from pathlib import Path
import sys

html = Path(sys.argv[1])
page = html.read_text(encoding="utf-8")

def change_once(original, new):
    global page
    if page.count(original) != 1:
        raise SystemExit(f"Expected exactly one controller integration marker: {original[:80]}")
    page = page.replace(original, new, 1)

change_once(
    '<script type="module">',
    '<script src="/b/8b0b5899ed/ios_controller.js"></script>\n<script type="module">'
)
mark = 'const w = new Int32Array(memory.buffer, block + 256, 10);'
change_once(
    mark,
    mark + '\n\t// Defer until the existing keyboard and mouse listeners are installed.\n'
    '\tsetTimeout(() => window.GTAInputBridge?.attach(keys, w), 0);'
)
html.write_text(page, encoding="utf-8")
print("iOS native controller bridge injected into browser engine input loop")
