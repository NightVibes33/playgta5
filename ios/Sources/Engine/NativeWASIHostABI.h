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
/* Duplicates only a caller-authorized regular-file FD. Returns guest FD >=3
 * or -1; closes all owned duplicates on reset, never the original FD. */
int32_t gta_wasi_register_readonly_fd(int host_fd);
void gta_wasi_reset_files(void);
/* Real Emscripten __syscall_openat import. The iOS provider must authorize
 * file access under the user-selected USB root and register a guest-only fd. */
typedef int32_t (*gta_wasi_openat_provider)(const char *relative_path);
void gta_wasi_set_openat_provider(gta_wasi_openat_provider provider);
int32_t gta_wasi_syscall_openat(int32_t dirfd, uint64_t path_pointer,
                                int32_t flags, uint64_t varargs_pointer);
int32_t gta_wasi_clock_time_get(uint32_t clock_id, uint64_t precision_ns,
                                 uint64_t out_pointer);
int32_t gta_wasi_environ_sizes_get(uint64_t count_pointer,
                                   uint64_t byte_count_pointer);
int32_t gta_wasi_environ_get(uint64_t environ_pointer,
                             uint64_t environ_buffer_pointer);
/* Real game.wasm memory64 signature: i32,i64,i64,i64 -> i32 */
int32_t gta_wasi_fd_write(uint32_t fd, uint64_t iovs, uint64_t count,
                          uint64_t written_pointer);
/* Verified memory64 game.wasm imports: standard streams plus guest-only
 * regular-file descriptors registered from authorized USB-backed handles.
 */
int32_t gta_wasi_fd_close(uint32_t fd);
int32_t gta_wasi_fd_read(uint32_t fd, uint64_t iovs,
                         uint64_t iovcnt, uint64_t nread);
int32_t gta_wasi_fd_seek(uint32_t fd, int64_t offset,
                         uint32_t whence, uint64_t new_offset);
int32_t gta_wasi_fd_pread(uint32_t fd, uint64_t iovs,
                          uint64_t iovcnt, uint64_t offset, uint64_t nread);
#ifdef __cplusplus
}
#endif
#endif
