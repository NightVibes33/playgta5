#include "NativeHTTPFSManifestABI.h"
#include <pthread.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

/* Copies the *small* JSON manifest into app-controlled memory. The JSON
 * is read with NSFileCoordinator on the existing security-scoped USB URL.
 * The game archives themselves remain on USB.
 * All state transitions are guarded; never retain a Swift Data pointer.
 */
static pthread_mutex_t gate = PTHREAD_MUTEX_INITIALIZER;
static unsigned char *manifest = NULL;
static size_t manifest_size = 0;
static unsigned char *wasm_memory = NULL;
static uint64_t wasm_size = 0;

int gta_httpfs_manifest_stage(const void *bytes, size_t size) {
    if (!bytes || size == 0 || size > GTA_HTTPFS_MAX_MANIFEST
               || size > INT32_MAX) return -1;
    unsigned char *copy = malloc(size);
    if (!copy) return -2;
    memcpy(copy, bytes, size);
    pthread_mutex_lock(&gate);
    unsigned char *prior = manifest;
    manifest = copy;
    manifest_size = size;
    pthread_mutex_unlock(&gate);
    free(prior);
    return 0;
}

void gta_httpfs_manifest_clear(void) {
    pthread_mutex_lock(&gate);
    unsigned char *prior = manifest;
    manifest = NULL;
    manifest_size = 0;
    wasm_memory = NULL;
    wasm_size = 0;
    pthread_mutex_unlock(&gate);
    free(prior);
}

size_t gta_httpfs_manifest_length(void) {
    pthread_mutex_lock(&gate);
    size_t n = manifest_size;
    pthread_mutex_unlock(&gate);
    return n;
}

void gta_httpfs_manifest_bind_memory(void *memory, uint64_t capacity) {
    pthread_mutex_lock(&gate);
    wasm_memory = (unsigned char *)memory;
    wasm_size = memory ? capacity : 0;
    pthread_mutex_unlock(&gate);
}

void gta_httpfs_manifest_unbind_memory(void) {
    gta_httpfs_manifest_bind_memory(NULL, 0);
}

int32_t gta_httpfs_manifest_js(uint64_t dest, int32_t capacity) {
    pthread_mutex_lock(&gate);
    if (!manifest || manifest_size == 0) {
        pthread_mutex_unlock(&gate);
        return -1; /* Matches original JS when /data/manifest.json absent. */
    }
    int32_t length = (int32_t)manifest_size;
    if (capacity > length) {
        /* Host code cannot leave the linear-memory boundaries. Unlike the JS
         * typed-array operation, a bad memory address returns -1 instead of
         * invoking undefined C pointer arithmetic.
         */
        uint64_t needed = (uint64_t)manifest_size + 1u;
        if (!wasm_memory || dest > wasm_size || needed > wasm_size - dest) {
            pthread_mutex_unlock(&gate);
            return -1;
        }
        memcpy(wasm_memory + (size_t)dest, manifest, manifest_size);
        wasm_memory[(size_t)dest + manifest_size] = 0;
    }
    pthread_mutex_unlock(&gate);
    return length;
}
