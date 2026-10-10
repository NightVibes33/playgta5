#include "NativeWASIHostABI.h"
#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <limits.h>
#include "NativeTextHostABI.h"

/* WASI preview1 errno values, not POSIX errno. */
enum { GTA_WASI_SUCCESS=0, GTA_WASI_FAULT=21, GTA_WASI_INVAL=28,
       GTA_WASI_IO=29, GTA_WASI_NOTSUP=58, GTA_WASI_OVERFLOW=61 };

static pthread_mutex_t wasi_mutex = PTHREAD_MUTEX_INITIALIZER;
static unsigned char *guest_memory;
static uint64_t guest_length;

void gta_wasi_bind_memory(void *memory, uint64_t length) {
    pthread_mutex_lock(&wasi_mutex);
    guest_memory = (unsigned char *)memory;
    guest_length = memory ? length : 0;
    pthread_mutex_unlock(&wasi_mutex);
}
void gta_wasi_unbind_memory(void) { gta_wasi_bind_memory(NULL, 0); }

static int span_valid(uint64_t at, uint64_t length) {
    return guest_memory && at <= guest_length && length <= guest_length - at &&
           at <= (uint64_t)SIZE_MAX && length <= (uint64_t)SIZE_MAX - (size_t)at;
}
static void put_u64_le(uint64_t at, uint64_t v) {
    for (size_t i=0; i<8; ++i) guest_memory[(size_t)at+i]=(unsigned char)(v>>(i*8));
}

int32_t gta_wasi_clock_time_get(uint32_t clock_id, uint64_t precision_ns,
                                 uint64_t out_pointer) {
    (void)precision_ns; /* Hint only; never weaken timestamp precision. */
    pthread_mutex_lock(&wasi_mutex);
    if (!span_valid(out_pointer, 8)) {
        pthread_mutex_unlock(&wasi_mutex);
        return GTA_WASI_FAULT;
    }
    clockid_t clock;
    switch (clock_id) {
        case 0: clock=CLOCK_REALTIME; break;
        case 1: clock=CLOCK_MONOTONIC; break;
#if defined(CLOCK_PROCESS_CPUTIME_ID)
        case 2: clock=CLOCK_PROCESS_CPUTIME_ID; break;
#endif
#if defined(CLOCK_THREAD_CPUTIME_ID)
        case 3: clock=CLOCK_THREAD_CPUTIME_ID; break;
#endif
        default:
            pthread_mutex_unlock(&wasi_mutex);
            return GTA_WASI_INVAL;
    }
    struct timespec now;
    if (clock_gettime(clock, &now)!=0) {
        pthread_mutex_unlock(&wasi_mutex);
        return GTA_WASI_IO;
    }
    if (now.tv_sec<0 || (uint64_t)now.tv_sec > UINT64_MAX / UINT64_C(1000000000) ||
        now.tv_nsec<0 || now.tv_nsec>=1000000000L ||
        (uint64_t)now.tv_sec > (UINT64_MAX-(uint64_t)now.tv_nsec)/UINT64_C(1000000000)) {
        pthread_mutex_unlock(&wasi_mutex);
        return GTA_WASI_OVERFLOW;
    }
    const uint64_t ns=(uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
    put_u64_le(out_pointer, ns);
    pthread_mutex_unlock(&wasi_mutex);
    return GTA_WASI_SUCCESS;
}

/* Deliberately expose an empty environment, as is normal for an isolated
 * sandboxed game process. No credentials, device variables or app secrets.
 * The memory64 libc ABI uses 64-bit size_t output cells.
 */
int32_t gta_wasi_environ_sizes_get(uint64_t count_pointer,
                                   uint64_t byte_count_pointer) {
    pthread_mutex_lock(&wasi_mutex);
    if (!span_valid(count_pointer, 8) || !span_valid(byte_count_pointer, 8)) {
        pthread_mutex_unlock(&wasi_mutex);
        return GTA_WASI_FAULT;
    }
    put_u64_le(count_pointer, 0);
    put_u64_le(byte_count_pointer, 0);
    pthread_mutex_unlock(&wasi_mutex);
    return GTA_WASI_SUCCESS;
}
int32_t gta_wasi_environ_get(uint64_t environ_pointer,
                             uint64_t environ_buffer_pointer) {
    pthread_mutex_lock(&wasi_mutex);
    const int ok=span_valid(environ_pointer, 0) && span_valid(environ_buffer_pointer, 0);
    pthread_mutex_unlock(&wasi_mutex);
    return ok ? GTA_WASI_SUCCESS : GTA_WASI_FAULT;
}


/* WASI preview1, memory64 ABI: fd_write(i32 fd, i64 iovs, i64 count,
 * i64 bytes_written) -> i32 errno. iovec is two little-endian uint64
 * fields, pointer then length, not the wasm32 8-byte layout.
 *
 * Only stdout/stderr are supported; file descriptors for game archives
 * need the independent USB/file-table backend. Validate the complete write
 * before queuing output, so bad late iovecs produce no partial effects.
 */
static uint64_t get_u64_le(uint64_t at) {
    uint64_t v = 0;
    for (unsigned i=0;i<8;i++)
        v |= (uint64_t)guest_memory[(size_t)at+i] << (i*8);
    return v;
}
int32_t gta_wasi_fd_write(uint32_t fd, uint64_t iovs,
                          uint64_t iovcnt, uint64_t nwritten) {
    if (fd != 1 && fd != 2) return 8; /* WASI EBADF */
    pthread_mutex_lock(&wasi_mutex);
    if (iovcnt > 256 || iovcnt > UINT64_MAX / 16 ||
        !span_valid(iovs, iovcnt*16) || !span_valid(nwritten, 8)) {
        pthread_mutex_unlock(&wasi_mutex);
        return GTA_WASI_FAULT;
    }
    uint64_t total = 0;
    for (uint64_t i=0;i<iovcnt;i++) {
        uint64_t ptr = get_u64_le(iovs + i*16);
        uint64_t size = get_u64_le(iovs + i*16 + 8);
        if (!span_valid(ptr, size) || size > UINT64_C(1048576) - total) {
            pthread_mutex_unlock(&wasi_mutex);
            return GTA_WASI_INVAL;
        }
        total += size;
    }
    /* The text diagnostic queue is bounded; writes are acknowledged in
     * full but only printable previews are retained in the app logs.
     * Host callbacks never copy megabytes of guest data to Swift.
     */
    unsigned char preview[200];
    size_t preview_n=0;
    for (uint64_t i=0;i<iovcnt;i++) {
        uint64_t ptr = get_u64_le(iovs + i*16);
        uint64_t len = get_u64_le(iovs + i*16 + 8);
        size_t take = len > sizeof(preview)-preview_n
            ? sizeof(preview)-preview_n : (size_t)len;
        if (take) memcpy(preview+preview_n, guest_memory+(size_t)ptr, take);
        preview_n += take;
    }
    put_u64_le(nwritten,total);
    pthread_mutex_unlock(&wasi_mutex);
    if (preview_n) gta_text_host_enqueue_bytes(
        fd==1 ? "[wasi-stdout]" : "[wasi-stderr]", preview, preview_n);
    return GTA_WASI_SUCCESS;
}
