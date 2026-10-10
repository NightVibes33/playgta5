#ifndef GTA_NATIVE_USERDATA_HOST_ABI_H
#define GTA_NATIVE_USERDATA_HOST_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Actual engine ABI from game.wasm and game.js:
 * env.wasm_userdata_put_js(i64 path, i64 data, i64 bytes, f64 mtime_ms) -> void
 * env.wasm_userdata_delete_js(i64 path) -> void.
 * Guest pointers are offsets into externally-owned shared memory64.
 * Engine must bind memory and then unbind before releasing its allocation.
 */
enum { GTA_USERDATA_MAX_FILE = 32 * 1024 * 1024, GTA_USERDATA_MAX_PATH = 512 };
int gta_userdata_set_root(const char *sandbox_directory);
void gta_userdata_bind_memory(const void *memory, uint64_t length);
void gta_userdata_unbind_memory(void);
int gta_userdata_put_js(uint64_t guest_path, uint64_t guest_data,
                        uint64_t length, double mtime_ms);
int gta_userdata_delete_js(uint64_t guest_path);
/* Read and clear the most recent nonzero failure for exportable diagnostics. */
int gta_userdata_take_error(void);
#ifdef __cplusplus
}
#endif
#endif
