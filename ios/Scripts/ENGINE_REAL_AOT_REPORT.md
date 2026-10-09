# Real engine AOT feasibility — iPhone 16 / iOS 27 beta 4

**Result: the supplied GTA `game.wasm` cannot be converted unchanged using
our current WABT `wasm2c` compiler. GTA V is NOT natively playable.**

## Verified from the actual user-supplied engine

The user supplied `game.wasm` directly for private analysis. The binary
has **63,201,802 bytes**, SHA-256:
`11ca8d2c04c5e843d18ff4aea4899d72c86973c6b031df334e67c446b2ae83e0`.
That exactly matches the earlier repository investigation. The engine
file itself has **not** been committed to GitHub.

Direct import/type section parsing finds:
- 1,969 type signatures; **86 imports total**, comprising 85 host functions
  and one `env.memory` shared memory64 import.
- The imported memory requires 49,152 initial 64 KiB pages (**3 GiB**) and
  has a 262,144-page (**16 GiB**) declared maximum. Both requirements are
  embedded in the actual WASM import, not merely in JavaScript loader text.
- 91,026 locally defined function bodies.
- Code section: 48,192,941 bytes. Data section: 7,828,019 bytes.
- Browser-specific Emscripten/pthreads/WebGPU/HTTP paging/audio/input
  imports still require correct native replacements.

The real module passed pinned WABT 1.0.42
`wasm-validate --enable-threads` (about 5 seconds / 2.3 GB peak RSS).

**AOT conversion failed:** pinned WABT `wasm2c` generated approximately
81 MB of incomplete C source before aborting with SIGABRT (134). The
debug-symbol backtrace points to `src/c-writer.cc:4417`: the writer's
`UNIMPLEMENTED` branch for atomic wait/notify, call_ref, and other cases.
Real disassembly confirms `memory.atomic.notify` and
`memory.atomic.wait32` in the actual engine. Thus our earlier synthetic
memory64 AOT smoke pass **does not** establish real-engine compatibility.

New `aot_feature_gate.py` performs a true instruction disassembly and
exits with a clear `WASM2C_ENGINE_INCOMPATIBLE` error before `wasm2c`
would produce misleading, incomplete C output. The CI smoke test
explicitly verifies the failure on a tiny `memory.atomic.notify` module.

## Required next engineering work

A correct native implementation now requires one of:

1. **Extend the AOT converter/runtime** to implement shared-memory
   `memory.atomic.wait32`, `memory.atomic.wait64`, and
   `memory.atomic.notify` with WebAssembly's mandated semantics (waiter
   queues, alignment, memory ordering, timeouts, waking/notifications),
   plus all other unsupported instructions found thereafter; then verify
   full codegen, cross-compilation and host imports on the real binary.
2. **Use a different vetted WebAssembly AOT compiler/runtime** that
   supports this module's shared memory64 and threading operations,
   with an executable that iOS signing rules can load without needing
   unavailable JIT permissions. Evaluate actual compiler output on
   physical iPhone 16 hardware; generic WASM feature support is not proof.

After engine AOT succeeds, implement all 85 imported functions and the
browser-to-native platform interfaces, native Metal shader renderer, real
GameController engine ABI, USB archive streaming, audio and save handling.
A real loading sequence and world gameplay must be demonstrated on-device.

**No app updates or JIT settings can bypass these missing components.**
The previously built unsigned IPA only contains a native device/Metal/
USB readiness harness. It is not a playable GTA V port and should never
be marketed or described as one.
