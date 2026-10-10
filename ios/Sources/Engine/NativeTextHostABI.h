#ifndef GTA_NATIVE_TEXT_HOST_ABI_H
#define GTA_NATIVE_TEXT_HOST_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Host ABI of the uploaded game.wasm:
 *  env.wasm_print_line_js(i64) -> void
 *  env.wasm_hang_line_js(i64) -> void
 *  env.wasm_module_int_js(i64, i32) -> i32
 *
 * Pointers address an externally owned shared Wasm memory. Bind only while
 * the Wasmtime allocation is alive; unbind before deleting it.
 */
void gta_text_host_bind_memory(const void *base, uint64_t size);
void gta_text_host_unbind_memory(void);
int gta_text_host_set_int(const char *name, int32_t value);
int32_t gta_text_host_module_int_js(uint64_t name, int32_t fallback);
void gta_text_host_print_line_js(uint64_t text);
void gta_text_host_hang_line_js(uint64_t text);
/* FIFO diagnostics extraction for Swift's Files-exported log channel.
 * Writes NUL-terminated data; returns 1 when a message was dequeued.
 */
int gta_text_host_next_log(char *destination, size_t capacity);
#ifdef __cplusplus
}
#endif
#endif
