#define _POSIX_C_SOURCE 200809L
#include "NativeUserdataHostABI.h"
#include <pthread.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

/* Native implementation of the REAL game's IndexedDB user-data messages.
 * Files are saved under the application's separate Documents/GTAiOS-Userdata
 * sandbox. Do not write to the game's USB-C archives.
 *
 * The caller owns the shared-memory64 allocation. No pointer remains valid
 * after gta_userdata_unbind_memory(). A single mutex serializes all operations,
 * including guest reads and atomic, fsync-backed persistence.
 */
static pthread_mutex_t gta_userdata_guard = PTHREAD_MUTEX_INITIALIZER;
static const unsigned char *gta_guest;
static uint64_t gta_guest_bytes;
static char gta_userdata_root[1024];
static unsigned long gta_temp_counter;
static int gta_recent_error;

static int remember(int rc) {
    if (rc < 0) gta_recent_error = rc;
    return rc;
}

int gta_userdata_set_root(const char *path) {
    pthread_mutex_lock(&gta_userdata_guard);
    gta_userdata_root[0] = 0;
    if (!path || path[0] != '/' || strlen(path) >= sizeof(gta_userdata_root)) {
        pthread_mutex_unlock(&gta_userdata_guard);
        return -1;
    }
    memcpy(gta_userdata_root, path, strlen(path) + 1);
    pthread_mutex_unlock(&gta_userdata_guard);
    return 0;
}

void gta_userdata_bind_memory(const void *memory, uint64_t length) {
    pthread_mutex_lock(&gta_userdata_guard);
    gta_guest = memory;
    gta_guest_bytes = memory ? length : 0;
    pthread_mutex_unlock(&gta_userdata_guard);
}

void gta_userdata_unbind_memory(void) {
    gta_userdata_bind_memory(NULL, 0);
}

int gta_userdata_take_error(void) {
    pthread_mutex_lock(&gta_userdata_guard);
    int rc = gta_recent_error;
    gta_recent_error = 0;
    pthread_mutex_unlock(&gta_userdata_guard);
    return rc;
}

static int guest_path(uint64_t offset, char path[GTA_USERDATA_MAX_PATH+1]) {
    static const char prefix[] = "/userdata/";
    if (!gta_guest || offset >= gta_guest_bytes) return -2;
    uint64_t available = gta_guest_bytes - offset;
    size_t limit = available > GTA_USERDATA_MAX_PATH ? GTA_USERDATA_MAX_PATH : (size_t)available;
    const unsigned char *src = gta_guest + (size_t)offset;
    const unsigned char *end = memchr(src, 0, limit);
    if (!end) return -3;
    size_t bytes = (size_t)(end - src);
    if (bytes <= sizeof(prefix)-1 || memcmp(src, prefix, sizeof(prefix)-1)) return -4;
    size_t n = bytes - (sizeof(prefix)-1);
    if (src[bytes-1] == '/' || n == 0) return -5;
    memcpy(path, src + sizeof(prefix)-1, n);
    path[n] = 0;
    /* Reject traversal, empty segments, Windows separators and control bytes.
       Do not interpret user-supplied strings as absolute filesystem paths. */
    const char *p = path;
    unsigned depth = 0;
    while (*p) {
        const char *slash = strchr(p, '/');
        size_t count = slash ? (size_t)(slash-p) : strlen(p);
        if (!count || count > 120 || (count == 1 && p[0]=='.') ||
            (count == 2 && p[0]=='.' && p[1]=='.')) return -6;
        for (size_t i=0; i<count; ++i) {
            unsigned char c = (unsigned char)p[i];
            if (c < 0x20 || c == 0x7f || c == '\\' || c == ':') return -7;
        }
        if (++depth > 12) return -8;
        if (!slash) break;
        p = slash + 1;
        if (!*p) return -9;
    }
    return 0;
}

/* Resolve each ancestor via dirfd and O_NOFOLLOW; malicious symlink
 * components cannot redirect a guest save outside the app sandbox. */
static int open_parent(char *relative, const char **filename) {
    int fd = open(gta_userdata_root, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return -10;
    char *segment = relative;
    char *slash;
    while ((slash = strchr(segment, '/')) != NULL) {
        *slash = 0;
        if (mkdirat(fd, segment, 0700) != 0 && errno != EEXIST) {
            close(fd);
            return -11;
        }
        int next = openat(fd, segment, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (next < 0) { close(fd); return -12; }
        close(fd);
        fd = next;
        segment = slash+1;
    }
    *filename = segment;
    return fd;
}

static int make_temp(int fd, char output[64]) {
    for (unsigned attempt=0; attempt<20; ++attempt) {
        unsigned long id = ++gta_temp_counter;
        snprintf(output, 64, ".gta-%ld-%lu.tmp", (long)getpid(), id);
        int temp = openat(fd, output, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC, 0600);
        if (temp >= 0) return temp;
        if (errno != EEXIST) return -1;
    }
    return -1;
}

int gta_userdata_put_js(uint64_t path_pointer, uint64_t data_pointer,
                        uint64_t length, double mtime_ms) {
    pthread_mutex_lock(&gta_userdata_guard);
    int rc = 0;
    char relative[GTA_USERDATA_MAX_PATH+1];
    if (!gta_userdata_root[0]) { rc=-20; goto end; }
    if (length > GTA_USERDATA_MAX_FILE) { rc=-21; goto end; }
    if (!gta_guest || data_pointer > gta_guest_bytes ||
        length > gta_guest_bytes - data_pointer) { rc=-22; goto end; }
    rc = guest_path(path_pointer, relative);
    if (rc) goto end;
    int dir = -1, out = -1;
    char temp_name[64] = {0};
    const char *filename = NULL;
    dir = open_parent(relative, &filename);
    if (dir < 0) { rc=dir; goto end; }
    /* Refuse to atomically replace any existing symlink. */
    struct stat existing;
    if (fstatat(dir, filename, &existing, AT_SYMLINK_NOFOLLOW)==0 &&
        !S_ISREG(existing.st_mode)) { rc=-23; goto cleanup; }
    out = make_temp(dir, temp_name);
    if (out < 0) { rc=-24; goto cleanup; }
    const unsigned char *data = gta_guest + (size_t)data_pointer;
    size_t done = 0;
    while (done < (size_t)length) {
        ssize_t wrote = write(out, data+done, (size_t)length-done);
        if (wrote < 0 && errno==EINTR) continue;
        if (wrote <= 0) { rc=-25; goto cleanup; }
        done += (size_t)wrote;
    }
    if (isfinite(mtime_ms) && mtime_ms >= 0 && mtime_ms < 32503680000000.0) {
        uint64_t milli = (uint64_t)mtime_ms;
        struct timespec times[2] = {{ .tv_nsec = UTIME_OMIT },
                                    { .tv_sec=(time_t)(milli/1000),
                                      .tv_nsec=(long)((milli%1000)*1000000) }};
        if (futimens(out, times) != 0) { rc=-26; goto cleanup; }
    }
    if (fsync(out) != 0) { rc=-27; goto cleanup; }
    if (close(out) != 0) { out=-1; rc=-28; goto cleanup; }
    out=-1;
    if (renameat(dir, temp_name, dir, filename) != 0) { rc=-29; goto cleanup; }
    temp_name[0]=0;
    if (fsync(dir) != 0) { rc=-30; goto cleanup; }
cleanup:
    if (out>=0) close(out);
    if (temp_name[0]) unlinkat(dir, temp_name, 0);
    close(dir);
end:
    rc=remember(rc);
    pthread_mutex_unlock(&gta_userdata_guard);
    return rc;
}

int gta_userdata_delete_js(uint64_t path_pointer) {
    pthread_mutex_lock(&gta_userdata_guard);
    int rc=0;
    char relative[GTA_USERDATA_MAX_PATH+1];
    if (!gta_userdata_root[0]) { rc=-20; goto end; }
    rc=guest_path(path_pointer, relative);
    if (rc) goto end;
    const char *filename=NULL;
    int dir=open_parent(relative, &filename);
    if (dir<0) { rc=dir; goto end; }
    struct stat item;
    if (fstatat(dir, filename, &item, AT_SYMLINK_NOFOLLOW) != 0) {
        if (errno != ENOENT) rc=-31;
    } else if (!S_ISREG(item.st_mode)) {
        rc=-32;
    } else if (unlinkat(dir, filename, 0) != 0) {
        rc=-33;
    } else if (fsync(dir) != 0) {
        rc=-34;
    }
    close(dir);
end:
    rc=remember(rc);
    pthread_mutex_unlock(&gta_userdata_guard);
    return rc;
}
