#include "NativeWASIHostABI.h"
#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <limits.h>
#include "NativeTextHostABI.h"

/* WASI preview1 errno values, not POSIX errno. */
enum { GTA_WASI_SUCCESS=0, GTA_WASI_BADF=8, GTA_WASI_FAULT=21,
       GTA_WASI_INVAL=28, GTA_WASI_IO=29, GTA_WASI_NOTSUP=58,
       GTA_WASI_OVERFLOW=61, GTA_WASI_SPIPE=70 };

static pthread_mutex_t wasi_mutex = PTHREAD_MUTEX_INITIALIZER;
static unsigned char *guest_memory;
static uint64_t guest_length;
/* The game's original browser process exposes 0/1/2 as standard streams.
 * File-backed descriptors must later be registered by the USB/fd-table ABI;
 * do not guess an app process POSIX fd or grant arbitrary filesystem access.
 */
static unsigned char stdio_open[3] = { 1, 1, 1 };
static int wasi_std_is_open(uint32_t fd) {
    return fd < 3 && stdio_open[fd];
}

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
    pthread_mutex_lock(&wasi_mutex);
    if ((fd!=1 && fd!=2) || !wasi_std_is_open(fd)) {
        pthread_mutex_unlock(&wasi_mutex);
        return GTA_WASI_BADF;
    }
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

/* WASI Preview1 FD services with the verified memory64 signatures:
 * fd_close(i32)->i32
 * fd_read(i32,i64,i64,i64)->i32
 * fd_seek(i32,i64,i32,i64)->i32
 * fd_pread(i32,i64,i64,i64,i64)->i32
 *
 * Correct standard-stream behavior only. Regular file descriptors (needed
 * for game archives) are NOT silently mapped to unrelated host OS fds.
 * A native virtual-fd table and USB-backed openat are still required.
 */
int32_t gta_wasi_fd_close(uint32_t fd) {
    pthread_mutex_lock(&wasi_mutex);
    if (!wasi_std_is_open(fd)) {
        pthread_mutex_unlock(&wasi_mutex);
        return GTA_WASI_BADF;
    }
    stdio_open[fd] = 0;
    pthread_mutex_unlock(&wasi_mutex);
    return GTA_WASI_SUCCESS;
}

/* iOS apps have no meaningful interactive WASI stdin. An open fd=0 returns
 * EOF (0 bytes) after verifying all 64-bit guest iovecs and nread pointer.
 * stdout/stderr cannot be read. No fabricated game/archive data is returned.
 */
int32_t gta_wasi_fd_read(uint32_t fd, uint64_t iovs,
                        uint64_t iovcnt, uint64_t nread) {
    pthread_mutex_lock(&wasi_mutex);
    if (fd != 0 || !wasi_std_is_open(fd)) {
        pthread_mutex_unlock(&wasi_mutex);
        return GTA_WASI_BADF;
    }
    if (iovcnt > 256 || iovcnt > UINT64_MAX/16 ||
        !span_valid(iovs, iovcnt*16) || !span_valid(nread, 8)) {
        pthread_mutex_unlock(&wasi_mutex);
        return GTA_WASI_FAULT;
    }
    for (uint64_t i=0; i<iovcnt; ++i) {
        uint64_t ptr = get_u64_le(iovs + i*16);
        uint64_t len = get_u64_le(iovs + i*16 + 8);
        if (!span_valid(ptr, len)) {
            pthread_mutex_unlock(&wasi_mutex);
            return GTA_WASI_FAULT;
        }
    }
    put_u64_le(nread, 0);
    pthread_mutex_unlock(&wasi_mutex);
    return GTA_WASI_SUCCESS;
}

int32_t gta_wasi_fd_seek(uint32_t fd, int64_t offset,
                        uint32_t whence, uint64_t new_offset) {
    (void)offset; (void)whence; (void)new_offset;
    pthread_mutex_lock(&wasi_mutex);
    int rc = wasi_std_is_open(fd) ? GTA_WASI_SPIPE : GTA_WASI_BADF;
    pthread_mutex_unlock(&wasi_mutex);
    return rc;
}
int32_t gta_wasi_fd_pread(uint32_t fd, uint64_t iovs,
                         uint64_t iovcnt, uint64_t offset,
                         uint64_t nread) {
    (void)iovs; (void)iovcnt; (void)offset; (void)nread;
    pthread_mutex_lock(&wasi_mutex);
    int rc = (fd==0 && wasi_std_is_open(fd)) ? GTA_WASI_SPIPE
             : GTA_WASI_BADF;
    pthread_mutex_unlock(&wasi_mutex);
    return rc;
}
