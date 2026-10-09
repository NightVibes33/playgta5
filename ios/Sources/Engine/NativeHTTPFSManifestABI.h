#ifndef GTA_NATIVE_HTTPFS_MANIFEST_ABI_H
#define GTA_NATIVE_HTTPFS_MANIFEST_ABI_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
/* The real GTA game.js host function:
 * env.wasm_httpfs_manifest_js(i64 buffer, i32 capacity) -> i32 bytes.
 * Called twice: to query the needed UTF-8 byte count, then to copy.
 * The web host copies bytes plus NUL only when capacity > byte count.
 * This implementation never makes network requests or copies the 20 GB game.
 */
enum { GTA_HTTPFS_MAX_MANIFEST = 32 * 1024 * 1024 };
int gta_httpfs_manifest_stage(const void *bytes, size_t size);
void gta_httpfs_manifest_clear(void);
size_t gta_httpfs_manifest_length(void);
void gta_httpfs_manifest_bind_memory(void *guest_memory, uint64_t guest_capacity);
void gta_httpfs_manifest_unbind_memory(void);
int32_t gta_httpfs_manifest_js(uint64_t dst, int32_t cap);
#ifdef __cplusplus
}
#endif
#endif
