#include "NativeWASIHostABI.h"
#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <limits.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
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

/* Guest fd values never alias POSIX descriptors. Registration duplicates a
 * caller-authorized regular-file descriptor while its security scope is live;
 * the guest cannot select arbitrary process fds or follow paths.
 * Guest reads use pread, with an independent serialized guest cursor.
 */
#define GTA_WASI_FILES 64
#define GTA_WASI_FILE_BASE 3
#define GTA_WASI_MAX_TRANSFER UINT64_C(1048576)
typedef struct {
    int owned_fd;
    uint64_t position;
} gta_wasi_file;
static gta_wasi_file wasi_files[GTA_WASI_FILES];
static pthread_once_t wasi_files_once = PTHREAD_ONCE_INIT;
static gta_wasi_openat_provider wasi_openat_provider;

static void gta_wasi_files_init(void) {
    for (size_t i = 0; i < GTA_WASI_FILES; ++i) wasi_files[i].owned_fd = -1;
}
static gta_wasi_file *gta_wasi_lookup(uint32_t fd) {
    if (fd < GTA_WASI_FILE_BASE || fd - GTA_WASI_FILE_BASE >= GTA_WASI_FILES)
        return NULL;
    gta_wasi_file *file = &wasi_files[fd - GTA_WASI_FILE_BASE];
    return file->owned_fd >= 0 ? file : NULL;
}
int32_t gta_wasi_register_readonly_fd(int host_fd) {
    pthread_once(&wasi_files_once, gta_wasi_files_init);
    if (host_fd < 0) return -1;
    struct stat info;
    if (fstat(host_fd, &info) || !S_ISREG(info.st_mode)) return -1;
    pthread_mutex_lock(&wasi_mutex);
    int32_t result = -1;
    for (size_t i = 0; i < GTA_WASI_FILES; ++i) {
        if (wasi_files[i].owned_fd >= 0) continue;
        int duplicate = dup(host_fd);
        if (duplicate >= 0) {
            wasi_files[i].owned_fd = duplicate;
            wasi_files[i].position = 0;
            result = (int32_t)(GTA_WASI_FILE_BASE + i);
        }
        break;
    }
    pthread_mutex_unlock(&wasi_mutex);
    return result;
}
void gta_wasi_reset_files(void) {
    pthread_once(&wasi_files_once, gta_wasi_files_init);
    pthread_mutex_lock(&wasi_mutex);
    for (size_t i = 0; i < GTA_WASI_FILES; ++i) {
        if (wasi_files[i].owned_fd >= 0) close(wasi_files[i].owned_fd);
        wasi_files[i].owned_fd = -1;
        wasi_files[i].position = 0;
    }
    stdio_open[0] = stdio_open[1] = stdio_open[2] = 1;
    pthread_mutex_unlock(&wasi_mutex);
}


static int span_valid(uint64_t at, uint64_t length);

/* Imported Emscripten __syscall_openat(i32, i64, i32, i64) -> i32.
 * No arbitrary host filesystem access: guest paths resolve under the
 * previously authorized USB game root through a Swift file coordinator.
 * We explicitly deny writes, creation and truncation. The caller's mode
 * varargs are unused because writing is not supported.
 */
void gta_wasi_set_openat_provider(gta_wasi_openat_provider provider) {
    pthread_mutex_lock(&wasi_mutex);
    wasi_openat_provider = provider;
    pthread_mutex_unlock(&wasi_mutex);
}
int32_t gta_wasi_syscall_openat(int32_t dirfd, uint64_t path_pointer,
                                int32_t flags, uint64_t varargs_pointer) {
    (void)varargs_pointer;
    if ((flags & O_ACCMODE) != O_RDONLY ||
        (flags & (O_CREAT | O_TRUNC | O_APPEND | O_EXCL)) != 0)
        return -13; /* EACCES, read-only game archives */
    char name[1024];
    gta_wasi_openat_provider provider = NULL;
    pthread_mutex_lock(&wasi_mutex);
    if (!span_valid(path_pointer, 1)) {
        pthread_mutex_unlock(&wasi_mutex);
        return -14; /* EFAULT */
    }
    size_t i = 0;
    for (; i < sizeof(name) - 1; ++i) {
        if (!span_valid(path_pointer + i, 1)) {
            pthread_mutex_unlock(&wasi_mutex);
            return -14;
        }
        name[i] = (char)guest_memory[(size_t)(path_pointer + i)];
        if (!name[i]) break;
    }
    if (i == sizeof(name) - 1) {
        pthread_mutex_unlock(&wasi_mutex);
        return -36; /* ENAMETOOLONG */
    }
    provider = wasi_openat_provider;
    pthread_mutex_unlock(&wasi_mutex);
    if (dirfd != -100 && name[0] != '/') return -9; /* EBADF */
    const char *relative = name;
    while (*relative == '/') relative++;
    if (strncmp(relative, "data/", 5) != 0 &&
        strncmp(relative, "b/", 2) != 0) return -2; /* ENOENT */
    /* Do not trust the embedding provider alone to reject path escape,
     * doubled separators or dot segments. Never normalize a malicious
     * path into an unintended file outside the authorized archive root. */
    for (const char *part = relative; *part;) {
        size_t len = strcspn(part, "/");
        if (!len || (len == 1 && part[0] == '.') ||
            (len == 2 && part[0] == '.' && part[1] == '.'))
            return -13; /* EACCES */
        part += len;
        if (*part == '/') {
            ++part;
            if (!*part) return -13;
        }
    }
    if (!provider) return -2;
    return provider(relative);
}

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


/* Original game.js SYSCALLS.writeStat: 104-byte memory64 little-endian layout. */
static void gta_put_u32(uint64_t at,uint32_t x) {
    for(unsigned i=0;i<4;i++)guest_memory[(size_t)at+i]=(unsigned char)(x>>(8*i));
}
static int32_t gta_stat_guest(uint64_t at,const struct stat *s) {
    if(!span_valid(at,104))return -21;
    memset(guest_memory+(size_t)at,0,104);
    gta_put_u32(at,(uint32_t)s->st_dev);
    gta_put_u32(at+4,(uint32_t)s->st_mode);
    put_u64_le(at+8,(uint64_t)s->st_nlink);
    gta_put_u32(at+16,(uint32_t)s->st_uid);
    gta_put_u32(at+20,(uint32_t)s->st_gid);
    gta_put_u32(at+24,(uint32_t)s->st_rdev);
    put_u64_le(at+32,(uint64_t)s->st_size);
    gta_put_u32(at+40,(uint32_t)s->st_blksize);
    gta_put_u32(at+44,(uint32_t)s->st_blocks);
#if defined(__APPLE__)
    const struct timespec *a=&s->st_atimespec,*m=&s->st_mtimespec,*ct=&s->st_ctimespec;
#else
    const struct timespec *a=&s->st_atim,*m=&s->st_mtim,*ct=&s->st_ctim;
#endif
    put_u64_le(at+48,(uint64_t)a->tv_sec);
    put_u64_le(at+56,(uint64_t)a->tv_nsec);
    put_u64_le(at+64,(uint64_t)m->tv_sec);
    put_u64_le(at+72,(uint64_t)m->tv_nsec);
    put_u64_le(at+80,(uint64_t)ct->tv_sec);
    put_u64_le(at+88,(uint64_t)ct->tv_nsec);
    put_u64_le(at+96,(uint64_t)s->st_ino);
    return 0;
}
int32_t gta_wasi_syscall_fstat64(int32_t fd,uint64_t at) {
    pthread_once(&wasi_files_once,gta_wasi_files_init);
    pthread_mutex_lock(&wasi_mutex);
    gta_wasi_file *f=fd<0?NULL:gta_wasi_lookup((uint32_t)fd);
    int32_t rc;
    if(!f)rc=-8; /* Emscripten EBADF */
    else if(!span_valid(at,104))rc=-21; /* EFAULT */
    else {
        struct stat st;
        rc=fstat(f->owned_fd,&st)?-29:gta_stat_guest(at,&st);
    }
    pthread_mutex_unlock(&wasi_mutex);
    return rc;
}
int32_t gta_wasi_syscall_stat64(uint64_t path,uint64_t at) {
    int32_t fd=gta_wasi_syscall_openat(-100,path,O_RDONLY,0);
    if(fd<0)return fd;
    int32_t rc=gta_wasi_syscall_fstat64(fd,at);
    (void)gta_wasi_fd_close((uint32_t)fd);
    return rc;
}
int32_t gta_wasi_syscall_lstat64(uint64_t path,uint64_t at) {
    /* Restricted archive root prohibits symlink traversal, so the only
     * supported objects are regular files with the same stat/lstat data. */
    return gta_wasi_syscall_stat64(path,at);
}
static void gta_put_tm(uint64_t at,const struct tm *t) {
    const int values[]={t->tm_sec,t->tm_min,t->tm_hour,t->tm_mday,
        t->tm_mon,t->tm_year,t->tm_wday,t->tm_yday};
    for(unsigned i=0;i<8;i++)gta_put_u32(at+i*4,(uint32_t)values[i]);
}
int32_t gta_wasi_gmtime_js(int64_t seconds,uint64_t at) {
    pthread_mutex_lock(&wasi_mutex);
    time_t v=(time_t)seconds;
    struct tm t;
    int32_t rc=!span_valid(at,32) || (int64_t)v!=seconds ||
        !gmtime_r(&v,&t);
    if(!rc)gta_put_tm(at,&t);
    pthread_mutex_unlock(&wasi_mutex);
    return rc;
}
int32_t gta_wasi_localtime_js(int64_t seconds,uint64_t at) {
    pthread_mutex_lock(&wasi_mutex);
    time_t v=(time_t)seconds;
    struct tm t;
    int32_t rc=!span_valid(at,48) || (int64_t)v!=seconds ||
        !localtime_r(&v,&t);
    if(!rc) {
        gta_put_tm(at,&t);
        gta_put_u32(at+32,(uint32_t)t.tm_isdst);
#if defined(__APPLE__) || defined(__linux__)
        put_u64_le(at+40,(uint64_t)(int64_t)t.tm_gmtoff);
#else
        put_u64_le(at+40,0);
#endif
    }
    pthread_mutex_unlock(&wasi_mutex);
    return rc;
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
/* Lifetime is owned by the virtual fd table, never the caller's host fd. */
int32_t gta_wasi_fd_close(uint32_t fd) {
    pthread_once(&wasi_files_once, gta_wasi_files_init);
    pthread_mutex_lock(&wasi_mutex);
    gta_wasi_file *file = gta_wasi_lookup(fd);
    if (file) {
        close(file->owned_fd);
        file->owned_fd = -1;
        file->position = 0;
    } else if (wasi_std_is_open(fd)) {
        stdio_open[fd] = 0;
    } else {
        pthread_mutex_unlock(&wasi_mutex);
        return GTA_WASI_BADF;
    }
    pthread_mutex_unlock(&wasi_mutex);
    return GTA_WASI_SUCCESS;
}

/* Validate every guest iovec before doing filesystem IO; never read outside
 * the externally bound shared memory and cap each call to 1 MiB.
 * pread does not modify the underlying OS file offset. */
static int gta_wasi_validate_read_iovecs(uint64_t iovs, uint64_t count,
                                         uint64_t nread) {
    if (count > 256 || count > UINT64_MAX / 16 ||
        !span_valid(iovs, count * 16) || !span_valid(nread, 8))
        return 0;
    uint64_t total = 0;
    for (uint64_t i = 0; i < count; ++i) {
        uint64_t ptr = get_u64_le(iovs + i * 16);
        uint64_t len = get_u64_le(iovs + i * 16 + 8);
        if (!span_valid(ptr, len) || len > GTA_WASI_MAX_TRANSFER - total)
            return 0;
        total += len;
    }
    return 1;
}
static int32_t gta_wasi_file_read(gta_wasi_file *file, uint64_t iovs,
    uint64_t count, uint64_t at, uint64_t nread, int advance) {
    if (!gta_wasi_validate_read_iovecs(iovs, count, nread))
        return GTA_WASI_FAULT;
    uint64_t consumed = 0;
    for (uint64_t i = 0; i < count; ++i) {
        uint64_t ptr = get_u64_le(iovs + i * 16);
        uint64_t len = get_u64_le(iovs + i * 16 + 8);
        if (!len) continue;
        if (at > INT64_MAX || consumed > (uint64_t)INT64_MAX - at)
            return GTA_WASI_OVERFLOW;
        ssize_t nr;
        do {
            nr = pread(file->owned_fd, guest_memory + (size_t)ptr,
                       (size_t)len, (off_t)(at + consumed));
        } while (nr < 0 && errno == EINTR);
        if (nr < 0) return GTA_WASI_IO;
        consumed += (uint64_t)nr;
        if ((uint64_t)nr != len) break; /* EOF or short read */
    }
    put_u64_le(nread, consumed);
    if (advance) file->position = at + consumed;
    return GTA_WASI_SUCCESS;
}
int32_t gta_wasi_fd_read(uint32_t fd, uint64_t iovs,
                        uint64_t iovcnt, uint64_t nread) {
    pthread_once(&wasi_files_once, gta_wasi_files_init);
    pthread_mutex_lock(&wasi_mutex);
    gta_wasi_file *file = gta_wasi_lookup(fd);
    if (file) {
        int32_t result = gta_wasi_file_read(file, iovs, iovcnt,
                                           file->position, nread, 1);
        pthread_mutex_unlock(&wasi_mutex);
        return result;
    }
    if (fd != 0 || !wasi_std_is_open(fd)) {
        pthread_mutex_unlock(&wasi_mutex);
        return GTA_WASI_BADF;
    }
    if (!gta_wasi_validate_read_iovecs(iovs, iovcnt, nread)) {
        pthread_mutex_unlock(&wasi_mutex);
        return GTA_WASI_FAULT;
    }
    put_u64_le(nread, 0); /* native iOS stdin EOF, not fabricated game data */
    pthread_mutex_unlock(&wasi_mutex);
    return GTA_WASI_SUCCESS;
}
int32_t gta_wasi_fd_seek(uint32_t fd, int64_t offset,
                        uint32_t whence, uint64_t new_offset) {
    pthread_once(&wasi_files_once, gta_wasi_files_init);
    pthread_mutex_lock(&wasi_mutex);
    gta_wasi_file *file = gta_wasi_lookup(fd);
    if (!file) {
        int result = wasi_std_is_open(fd) ? GTA_WASI_SPIPE : GTA_WASI_BADF;
        pthread_mutex_unlock(&wasi_mutex);
        return result;
    }
    if (!span_valid(new_offset, 8)) {
        pthread_mutex_unlock(&wasi_mutex);
        return GTA_WASI_FAULT;
    }
    uint64_t base = 0;
    if (whence == 1) base = file->position;
    else if (whence == 2) {
        struct stat info;
        if (fstat(file->owned_fd, &info) || info.st_size < 0) {
            pthread_mutex_unlock(&wasi_mutex);
            return GTA_WASI_IO;
        }
        base = (uint64_t)info.st_size;
    } else if (whence != 0) {
        pthread_mutex_unlock(&wasi_mutex);
        return GTA_WASI_INVAL;
    }
    if (base > INT64_MAX ||
        (offset < 0 && (uint64_t)(-(offset + 1)) + 1 > base) ||
        (offset > 0 && (uint64_t)offset > (uint64_t)INT64_MAX - base)) {
        pthread_mutex_unlock(&wasi_mutex);
        return GTA_WASI_INVAL;
    }
    uint64_t next = offset < 0 ? base - ((uint64_t)(-(offset + 1)) + 1)
                               : base + (uint64_t)offset;
    file->position = next;
    put_u64_le(new_offset, next);
    pthread_mutex_unlock(&wasi_mutex);
    return GTA_WASI_SUCCESS;
}
int32_t gta_wasi_fd_pread(uint32_t fd, uint64_t iovs,
                         uint64_t iovcnt, uint64_t offset,
                         uint64_t nread) {
    pthread_once(&wasi_files_once, gta_wasi_files_init);
    pthread_mutex_lock(&wasi_mutex);
    gta_wasi_file *file = gta_wasi_lookup(fd);
    if (file) {
        int32_t result = gta_wasi_file_read(file, iovs, iovcnt,
                                           offset, nread, 0);
        pthread_mutex_unlock(&wasi_mutex);
        return result;
    }
    int result = (fd == 0 && wasi_std_is_open(fd)) ? GTA_WASI_SPIPE : GTA_WASI_BADF;
    pthread_mutex_unlock(&wasi_mutex);
    return result;
}
