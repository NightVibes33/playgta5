#!/usr/bin/env python3
"""Render pinned Wasmtime v49.0.2 C-API conf.h.in for Cargo threads-only.

The device static archive is built with:
  cargo build -p wasmtime-c-api --no-default-features --features threads
or the matching CMake options WASMTIME_DISABLE_ALL_FEATURES=ON and
WASMTIME_FEATURE_THREADS=ON.

Unlike a hand-written 3-line header, this consumes upstream's exact template,
leaving all non-threads macros undefined. The derived COMPILER guard in the
upstream template remains intact.
"""
from pathlib import Path
import argparse
import re

FEATURE = re.compile(r"^#cmakedefine\s+(WASMTIME_FEATURE_[A-Z0-9_]+)\s*$")

def render(template: str) -> str:
    selected = {"WASMTIME_FEATURE_THREADS"}
    all_features: set[str] = set()
    lines: list[str] = []
    for line in template.splitlines(keepends=True):
        match = FEATURE.fullmatch(line.rstrip("\r\n"))
        if match:
            feature = match.group(1)
            if feature in all_features:
                raise ValueError(f"duplicate upstream macro {feature}")
            all_features.add(feature)
            suffix = "\n" if line.endswith("\n") else ""
            if feature in selected:
                lines.append(f"#define {feature} 1{suffix}")
            else:
                lines.append(f"/* #undef {feature} */{suffix}")
        else:
            lines.append(line)
    if len(all_features) < 20 or selected - all_features:
        raise ValueError("unexpected Wasmtime conf.h.in: incomplete feature list")
    result = "".join(lines)
    if "#cmakedefine" in result:
        raise ValueError("unhandled upstream CMake directive")
    if "WASMTIME_FEATURE_CRANELIFT" not in result or "WASMTIME_FEATURE_COMPILER" not in result:
        raise ValueError("compiler feature guard missing in upstream template")
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_template", type=Path)
    parser.add_argument("generated_header", type=Path)
    args = parser.parse_args()
    content = render(args.upstream_template.read_text(encoding="utf-8"))
    args.generated_header.parent.mkdir(parents=True, exist_ok=True)
    args.generated_header.write_text(content, encoding="utf-8")
    print("Wasmtime 49 conf.h generated from upstream template: THREADS on, other features off")
