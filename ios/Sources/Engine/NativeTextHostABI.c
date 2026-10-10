#define _POSIX_C_SOURCE 200809L
#include "NativeTextHostABI.h"
#include <pthread.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#define GTA_TEXT_QUEUE 32
#define GTA_TEXT_ENTRY 256
#define GTA_TEXT_OPTION_COUNT 24
#define GTA_TEXT_NAME_MAX 63
#define GTA_TEXT_SOURCE_MAX 4096
typedef struct { char key[GTA_TEXT_NAME_MAX + 1]; int32_t value; } gta_text_option;
static pthread_mutex_t guard = PTHREAD_MUTEX_INITIALIZER;
static const unsigned char *wasm_base;
static uint64_t wasm_length;
static gta_text_option options[GTA_TEXT_OPTION_COUNT];
static size_t option_count;
static char queue[GTA_TEXT_QUEUE][GTA_TEXT_ENTRY];
static size_t read_slot, write_slot, queued;

static int read_guest_string(uint64_t offset, size_t limit,
                             char *dest, size_t dest_count) {
    if (!wasm_base || !dest || dest_count < 2 || offset >= wasm_length) return 0;
    uint64_t available = wasm_length - offset;
    size_t n = available > limit ? limit : (size_t)available;
    const unsigned char *p = wasm_base + (size_t)offset;
    const unsigned char *end = memchr(p, 0, n);
    if (!end) return 0; /* Reject nonterminated or out-of-bounds strings. */
    n = (size_t)(end - p);
    size_t copy = n < dest_count - 1 ? n : dest_count - 1;
    for (size_t i = 0; i < copy; ++i) {
        unsigned char c = p[i];
        dest[i] = c >= 0x20 || c == '\n' || c == '\t' ? (char)c : ' ';
    }
    dest[copy] = 0;
    return 1;
}

void gta_text_host_bind_memory(const void *base, uint64_t size) {
    pthread_mutex_lock(&guard);
    wasm_base = base;
    wasm_length = base ? size : 0;
    pthread_mutex_unlock(&guard);
}
void gta_text_host_unbind_memory(void) {
    gta_text_host_bind_memory(NULL, 0);
}
int gta_text_host_set_int(const char *name, int32_t value) {
    if (!name) return -1;
    size_t length = strnlen(name, GTA_TEXT_NAME_MAX + 2);
    if (length == 0 || length > GTA_TEXT_NAME_MAX) return -1;
    pthread_mutex_lock(&guard);
    for (size_t i = 0; i < option_count; ++i) {
        if (strcmp(options[i].key, name) == 0) {
            options[i].value = value;
            pthread_mutex_unlock(&guard);
            return 0;
        }
    }
    if (option_count >= GTA_TEXT_OPTION_COUNT) {
        pthread_mutex_unlock(&guard);
        return -2;
    }
    memcpy(options[option_count].key, name, length + 1);
    options[option_count].value = value;
    option_count++;
    pthread_mutex_unlock(&guard);
    return 0;
}

int32_t gta_text_host_module_int_js(uint64_t name, int32_t fallback) {
    char key[GTA_TEXT_NAME_MAX + 1];
    pthread_mutex_lock(&guard);
    if (!read_guest_string(name, GTA_TEXT_NAME_MAX + 1, key, sizeof(key))) {
        pthread_mutex_unlock(&guard);
        return fallback;
    }
    for (size_t i = 0; i < option_count; ++i) {
        if (strcmp(options[i].key, key) == 0) {
            int32_t value = options[i].value;
            pthread_mutex_unlock(&guard);
            return value;
        }
    }
    pthread_mutex_unlock(&guard);
    return fallback;
}

static void enqueue_line(const char *kind, uint64_t pointer) {
    char message[GTA_TEXT_ENTRY - 24];
    pthread_mutex_lock(&guard);
    int valid = read_guest_string(pointer, GTA_TEXT_SOURCE_MAX,
                                   message, sizeof(message));
    if (!valid) snprintf(message, sizeof(message), "%s", "[invalid guest text pointer]");
    /* Overwrite oldest when full. No unbounded engine log allocations. */
    snprintf(queue[write_slot], GTA_TEXT_ENTRY, "%s %s", kind, message);
    write_slot = (write_slot + 1) % GTA_TEXT_QUEUE;
    if (queued == GTA_TEXT_QUEUE) read_slot = (read_slot + 1) % GTA_TEXT_QUEUE;
    else queued++;
    pthread_mutex_unlock(&guard);
}
void gta_text_host_print_line_js(uint64_t text) { enqueue_line("[engine]", text); }
void gta_text_host_hang_line_js(uint64_t text) { enqueue_line("[engine-hang]", text); }
int gta_text_host_next_log(char *destination, size_t capacity) {
    if (!destination || capacity < 2) return 0;
    pthread_mutex_lock(&guard);
    if (!queued) {
        destination[0] = 0;
        pthread_mutex_unlock(&guard);
        return 0;
    }
    snprintf(destination, capacity, "%s", queue[read_slot]);
    read_slot = (read_slot + 1) % GTA_TEXT_QUEUE;
    queued--;
    pthread_mutex_unlock(&guard);
    return 1;
}
