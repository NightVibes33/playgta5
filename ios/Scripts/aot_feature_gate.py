#!/usr/bin/env python3
"""Fail-fast WABT wasm2c compatibility gate.

Use real decoded instructions, not raw-byte matches that could occur in
immediates or data. No proprietary engine bytes are printed or copied.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

# WABT CWriter at src/c-writer.cc handles these by UNIMPLEMENTED/abort.
UNSUPPORTED = re.compile(
    r"\b(memory\.atomic\.(?:wait32|wait64|notify)|return_call_ref|call_ref)\b"
)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("wasm", type=Path)
    p.add_argument("--objdump", type=Path, required=True)
    args = p.parse_args()
    command = [str(args.objdump), "--disassemble", str(args.wasm)]
    process = subprocess.Popen(command, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True,
                               encoding="utf-8", errors="replace", bufsize=1)
    first = None
    try:
        assert process.stdout is not None
        for line in process.stdout:
            match = UNSUPPORTED.search(line)
            if match:
                first = (match.group(), line.strip())
                break
    finally:
        if first:
            process.terminate()
        try:
            _, errors = process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            _, errors = process.communicate()
    if first:
        print("WASM2C_ENGINE_INCOMPATIBLE: " + first[0], file=sys.stderr)
        print("First occurrence: " + first[1], file=sys.stderr)
        print("WABT's C writer cannot generate wait/notify or call_ref operations.", file=sys.stderr)
        print("Do not compile incomplete C output or claim an ARM64 game engine.", file=sys.stderr)
        return 10
    if process.returncode:
        print("WABT disassembler failed: " + errors[-800:], file=sys.stderr)
        return 2
    print("Known WABT codegen incompatibilities not detected; other limits may remain.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
