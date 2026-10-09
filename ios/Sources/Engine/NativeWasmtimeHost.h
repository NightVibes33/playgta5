#ifndef GTA_IOS_NATIVE_WASMTIME_HOST_H
#define GTA_IOS_NATIVE_WASMTIME_HOST_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
/* 0 when real Wasmtime runtime can initialize. -100 on simulator; -1 error.
   This does not instantiate the GTA game engine. */
int gta_ios_wasmtime_engine_probe(void);

/* Registers four non-memory GTA host imports (three clocks, CPU count)
   and invokes the native Wasmtime monotonic-clock callback as a smoke test.
   The remaining imports are intentionally NOT stubbed or instantiated. */
int gta_ios_wasmtime_basic_host_probe(unsigned int *installed,
                                      char *error_message, size_t error_capacity);

/* Only accepts a trusted SHA256-verified, version-matched Wasmtime AOT file.
   Returns 0 with 86 imports if deserialization succeeded (NOT gameplay).
   Returns a negative error code and a diagnostic string otherwise. */
#include <stddef.h>
int gta_ios_wasmtime_aot_probe(const char *path,
                              unsigned int *import_count,
                              char *error_message, size_t error_capacity);
#ifdef __cplusplus
}
#endif
#endif
