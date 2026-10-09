# Native AOT conversion gate for GTAiOS

This is an actual WebAssembly-to-ARM64 compilation workflow, not a WebKit renderer.

## Implementation

- aot_import_audit.py parses the binary import table, including complete
  function signatures and shared memory64 minimum/maximum settings.
- aot_compile.sh runs WABT wasm2c on an authorized WebAssembly module and
  cross-compiles the result to an iPhone ARM64 Mach-O object.
- native-aot.yml verifies that conversion with a small test module using
  imported shared memory64. A manual run may also retrieve a game.wasm
  artifact named engine-input from an authorized earlier GitHub Actions run.
  Proprietary source and generated objects are never automatically published.

These are reproducible AOT tools. No JIT entitlement is required simply to
produce or execute precompiled, properly linked native code.

## Still required for actual GTA V gameplay

The game's approximately 63 MB WASM binary is NOT in the public repository.
The expected SHA-256 from the existing static audit is
11ca8d2c04c5e843d18ff4aea4899d72c86973c6b031df334e67c446b2ae83e0.

Converting the real WASM could fail if it uses unsupported instructions or if
the huge generated translation exceeds available build memory. Success would
only produce an UNLINKED ARM64 object. The roughly 85 Emscripten, WASI and
project-specific imported functions must be implemented correctly in native
code, along with shared memory/pthreads, original USB game archive access,
WebGPU-to-Metal commands and shader conversion, game audio, save support,
and a true GameController-to-game ABI.

The runtime must satisfy the module's real memory64 minimum (~3 GiB from
the browser host configuration) and be tested on a physical iPhone 16. No
simulator or Xcode compilation can establish actual playable GTA V.

The compiler is different from Madeira's FEX/Wine x86-to-ARM64 translation.
For WASM, AOT comes first; native JIT is optional only if required by a
supported runtime and permitted under the user's signing/debugging setup.

Never advertise this binary compiler, a black Metal surface, or the
native-foundation IPA as a finished game until the genuine GTA world renders,
loads its assets and accepts gameplay input.


## Real engine was received and tested

The authorized 63,201,802-byte `game.wasm` was privately uploaded and
its SHA-256 matched the existing investigation. WABT `wasm-validate`
succeeded. **But `wasm2c` is not yet compatible with this game**: it
aborts at `src/c-writer.cc:4417` on unsupported thread wait/notify
codegen. We confirmed `memory.atomic.notify` and
`memory.atomic.wait32` in the actual code. See
`ios/Scripts/ENGINE_REAL_AOT_REPORT.md`. `aot_feature_gate.py`
now rejects this unsupported path deterministically. Synthetic AOT
success is not real engine conversion.

A compatible AOT backend or semantics-correct atomic wait/notify
compiler/runtime implementation is necessary before compiling to ARM64.
The engine has not been linked or run on iPhone.
