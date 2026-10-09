#ifndef GTA_NATIVE_ATOMICS_H
#define GTA_NATIVE_ATOMICS_H
#include <stdint.h>
#include "wasm-rt.h"
#ifdef __cplusplus
extern "C" {
#endif
/* Native thread wait/notify for wasm2c imported shared linear memory.
 * - wait returns 0 notified, 1 mismatched value, 2 timeout
 * - notify returns the number of waiters woken
 * - bounds and alignment trap according to WASM atomic rules
 * The host must initialize and maintain wasm_rt_shared_memory_t correctly.
 */
uint32_t gta_wasm_atomic_wait32(wasm_rt_shared_memory_t *mem, uint64_t address,
                                uint32_t expected, int64_t timeout_ns);
uint32_t gta_wasm_atomic_wait64(wasm_rt_shared_memory_t *mem, uint64_t address,
                                uint64_t expected, int64_t timeout_ns);
uint32_t gta_wasm_atomic_notify(wasm_rt_shared_memory_t *mem, uint64_t address,
                                uint32_t count);
#ifdef __cplusplus
}
#endif
#endif
