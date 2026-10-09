# Native Wasmtime runtime host: verified iPhone ARM64 library

## Verified results
- The user-supplied GTA game.wasm matches SHA256 11ca8d2c04c5e843d18ff4aea4899d72c86973c6b031df334e67c446b2ae83e0.
- Official Wasmtime 49.0.2 Cranelift successfully AOT-compiled the real engine for aarch64-apple-ios, with threads/shared memory/memory64 enabled. Private output: 238,815,736-byte Wasmtime serialized AArch64 ELF module, SHA256 b2fadd0881302505388104a0ff6b428db65106edd81a8e5a64fcfa905a4febb0. Exit 0; 30.34 sec; 2.39 GB peak RSS.
- GitHub Actions run 37863434334 successfully cross-compiled Wasmtime 49.0.2 C API for aarch64-apple-ios with threads and WITHOUT an on-device compiler. Static library libwasmtime.a is ~26 MB. SHA256 101b799436ab91dfe37785a6a85f7e4551355c67e3112173385611f35f159d20.
- Reproducible Rust build:
  rustup target add aarch64-apple-ios
  cargo build --locked --release -p wasmtime-c-api --target aarch64-apple-ios --no-default-features --features threads
- The GitHub Actions workflow ios-wasmtime-host.yml packages the open-source library, C API headers and provenance. Proprietary engine bytes and generated AOT code are never committed or uploaded to public artifacts.

## Important limits
- The 228 MB .cwasm is not a signed iOS Mach-O executable; the runtime library is not an IPA.
- The native Wasmtime iOS static library has NOT yet been linked into GTAiOS, run or tested for executable-page/JIT/code-signing policies on a real iPhone 16 with SideStore.
- The actual game still requires 85 correct Emscripten/WASI/project-specific host function implementations, a shared memory64 with minimum 49,152 pages (3 GiB), correct threading and file I/O.
- Wasmtime Pulley (no-JIT interpretation) rejects the real engine's threads feature; removing atomic waits/notifications would break engine behavior.
- The real Metal render/shader bridge, original loading sequence, game-audio integration, engine-level analog gamepad interface, save handling and stable gameplay are NOT implemented.

## Next verifiable milestone
Link the Wasmtime static library into an iOS smoke target, load and execute a SMALL precompiled ARM64 module via the C API on the user's physical iPhone 16, and report whether executable memory mapping works with that SideStore/JIT signing environment. Only after proving a working execution host can the real GTA engine be linked with its 85 host imports and Metal renderer.

Do not present the current native-readiness IPA or AOT output as playable GTA V.
