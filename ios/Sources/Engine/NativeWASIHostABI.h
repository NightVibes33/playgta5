#ifndef GTA_NATIVE_WASI_HOST_ABI_H
#define GTA_NATIVE_WASI_HOST_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Exact wasi_snapshot_preview1 memory64 signatures from the supplied engine.
 * Requires a validated, live, externally owned shared Wasm memory mapping.
 * Caller MUST unbind before freeing/replacing that mapping.
 */
void gta_wasi_bind_memory(void *memory, uint64_t length);
void gta_wasi_unbind_memory(void);
int32_t gta_wasi_clock_time_get(uint32_t clock_id, uint64_t precision_ns,
                                 uint64_t out_pointer);
int32_t gta_wasi_environ_sizes_get(uint64_t count_pointer,
                                   uint64_t byte_count_pointer);
int32_t gta_wasi_environ_get(uint64_t environ_pointer,
                             uint64_t environ_buffer_pointer);
#ifdef __cplusplus
}
#endif
#endif
