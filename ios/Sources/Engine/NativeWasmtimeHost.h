#ifndef GTA_IOS_NATIVE_WASMTIME_HOST_H
#define GTA_IOS_NATIVE_WASMTIME_HOST_H
#include <stddef.h>
#include "../Input/NativeGameInputABI.h"
#include "NativeHTTPFSManifestABI.h"
#include "NativeTextHostABI.h"
#include "NativeUserdataHostABI.h"
#ifdef __cplusplus
extern "C" {
#endif
/* 0 when real Wasmtime runtime can initialize. -100 on simulator; -1 error.
   This does not instantiate the GTA game engine. */
int gta_ios_wasmtime_engine_probe(void);

/* Registers fifteen verified GTA host imports (timing, capabilities and heap limit)
   and invokes the native Wasmtime monotonic-clock callback as a smoke test.
   The remaining imports are intentionally NOT stubbed or instantiated. */
int gta_ios_wasmtime_basic_host_probe(unsigned int *installed,
                                      char *error_message, size_t error_capacity);

/* Execute a tiny trusted, CI-generated AArch64 AOT test function in a signed
   iOS app. Returns 0 only when its real machine code returns add(20,22)=42.
   This is a hardware execution check, NOT GTA engine instantiation. */
int gta_ios_wasmtime_execute_smoke(const char *aot_path,
                                    char *message, size_t capacity);

/* Executes an actual iPhone ARM64 AOT module with an imported shared
   memory64 allocation of one 64KiB page. Verifies a guest store+load at
   i64 offset 16 against the host shared memory. The test does NOT allocate
   the GTA engine's 3GiB initial memory or run the game. */
int gta_ios_wasmtime_memory64_smoke(const char *aot_path,
                                    char *message, size_t capacity);

/* Only accepts a trusted SHA256-verified, version-matched Wasmtime AOT file.
   Returns 0 with 86 imports if deserialization succeeded (NOT gameplay).
   Returns a negative error code and a diagnostic string otherwise. */
#include <stddef.h>
int gta_ios_wasmtime_aot_probe(const char *path,
                              unsigned int *import_count, unsigned int *covered_count,
                              char *error_message, size_t error_capacity);
#ifdef __cplusplus
}
#endif
#endif
