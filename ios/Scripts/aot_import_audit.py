#!/usr/bin/env python3
"""Verify a real WASM module and emit an exact, typed native-host import ABI.

No game bytes or proprietary assets are copied into this repository.
Unlike a generic import-name list, this resolves function parameter/result
types, including i64 pointers from a memory64 Emscripten module.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path

V = {0x7f: "i32", 0x7e: "i64", 0x7d: "f32", 0x7c: "f64", 0x7b: "v128",
     0x70: "funcref", 0x6f: "externref"}
MAX_IMPORTS = 100000
MAX_SECTION = 128 * 1024 * 1024

class WasmError(Exception):
    pass

class Reader:
    def __init__(self, data: bytes):
        self.buf = data
        self.i = 0

    def u8(self):
        if self.i >= len(self.buf):
            raise WasmError("truncated binary")
        x = self.buf[self.i]
        self.i += 1
        return x

    def leb(self):
        v = 0
        for k in range(10):
            b = self.u8()
            if k == 9 and b > 1:
                raise WasmError("LEB overflow")
            v |= (b & 127) << (7 * k)
            if not b & 128:
                return v
        raise WasmError("LEB too long")

    def take(self, count):
        if count > len(self.buf) - self.i:
            raise WasmError("truncated section")
        x = self.buf[self.i:self.i + count]
        self.i += count
        return x

    def name(self):
        n = self.leb()
        if n > 65536:
            raise WasmError("oversized import name")
        return self.take(n).decode("utf8")

    def value(self):
        x = self.u8()
        if x not in V:
            raise WasmError(f"unsupported function value type 0x{x:02x}")
        return V[x]

    def limits(self):
        flags = self.leb()
        if flags & ~0x0f:
            raise WasmError("unsupported memory/table flags")
        minimum = self.leb()
        maximum = self.leb() if flags & 1 else None
        return {"initial_pages": minimum, "maximum_pages": maximum,
                "shared": bool(flags & 2), "memory64": bool(flags & 4),
                "flags": flags}

def parse_sections(data):
    if data[:8] != b"\0asm\x01\0\0\0":
        raise WasmError("not a WebAssembly 1 module")
    r = Reader(data)
    r.i = 8
    sections = {}
    while r.i < len(data):
        kind = r.u8()
        n = r.leb()
        if n > MAX_SECTION:
            raise WasmError(f"section {kind} exceeds audit size limit")
        body = r.take(n)
        if kind in (1, 2) and kind in sections:
            raise WasmError(f"duplicate section {kind}")
        if kind in (1, 2):
            sections[kind] = Reader(body)
    return sections

def audit(data):
    sections = parse_sections(data)
    types = []
    if 1 in sections:
        r = sections[1]
        n = r.leb()
        if n > 100000:
            raise WasmError("function type count too large")
        for _ in range(n):
            if r.u8() != 0x60:
                raise WasmError("unsupported function type marker")
            pc = r.leb()
            if pc > 1000:
                raise WasmError("function parameter count too large")
            ps = [r.value() for _ in range(pc)]
            rc = r.leb()
            if rc > 1000:
                raise WasmError("function result count too large")
            rs = [r.value() for _ in range(rc)]
            types.append({"params": ps, "results": rs})
    imports = []
    if 2 in sections:
        r = sections[2]
        count = r.leb()
        if count > MAX_IMPORTS:
            raise WasmError("import count too large")
        for _ in range(count):
            module = r.name()
            name = r.name()
            kind = r.u8()
            entry = {"module": module, "name": name}
            if kind == 0:
                type_index = r.leb()
                if type_index >= len(types):
                    raise WasmError("invalid function type index")
                entry.update({"kind": "function", "type_index": type_index,
                              "signature": types[type_index]})
            elif kind == 2:
                entry.update({"kind": "memory", "limits": r.limits()})
            elif kind == 1:
                entry.update({"kind": "table", "element_type": r.value(), "limits": r.limits()})
            elif kind == 3:
                entry.update({"kind": "global", "value_type": r.value(), "mutable": bool(r.u8())})
            elif kind == 4:
                entry.update({"kind": "tag", "attribute": r.leb(), "type_index": r.leb()})
            else:
                raise WasmError(f"unsupported import kind {kind}")
            imports.append(entry)
    return {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
            "function_types": len(types), "import_count": len(imports), "imports": imports}

def main():
    p = argparse.ArgumentParser()
    p.add_argument("wasm", type=Path)
    p.add_argument("--json", type=Path)
    p.add_argument("--expected-sha256", default="")
    args = p.parse_args()
    result = audit(args.wasm.read_bytes())
    if args.expected_sha256 and result["sha256"] != args.expected_sha256.lower():
        raise WasmError("binary checksum mismatch; refusing unknown engine")
    memory = [x for x in result["imports"] if x["kind"] == "memory"]
    if args.wasm.name == "game.wasm":
        if len(memory) != 1 or not memory[0]["limits"]["memory64"] or not memory[0]["limits"]["shared"]:
            raise WasmError("GTA engine does not have the expected shared memory64 import")
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(result, indent=2) + "\n")
    print("SHA256:", result["sha256"])
    print("WASM bytes:", result["bytes"])
    print("Imports:", result["import_count"], "functions:",
          sum(x["kind"] == "function" for x in result["imports"]))
    for m in memory:
        print("Imported memory:", m["module"] + "." + m["name"], m["limits"])
    print("Host ABI audit written:", str(args.json) if args.json else "(not requested)")
    print("NOTE: Import ABI inventory is not proof that any host functions are implemented.")

if __name__ == "__main__":
    try:
        main()
    except (WasmError, OSError, UnicodeError) as e:
        raise SystemExit(f"ENGINE ABI AUDIT FAILED: {e}")
