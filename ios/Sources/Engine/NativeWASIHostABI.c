#include "NativeWASIHostABI.h"
#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <limits.h>

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
