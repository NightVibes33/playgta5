#include "NativeArchivePathABI.h"
#include <string.h>

int gta_archive_flags_readonly(int32_t flags) {
    /* O_ACCMODE, O_CREAT, O_EXCL, O_TRUNC, O_APPEND in the guest ABI. */
    return (flags & (3 | 64 | 128 | 512 | 1024)) == 0;
}

int gta_archive_relative_path(const char *guest, char *output, size_t capacity) {
    if (!guest || !output || !capacity) return 0;
    const char *relative = guest;
    if (*relative == '/') ++relative;
    /* Validate every component before translating the mount prefix. */
    if (!*relative) return 0;
    for (const char *part = relative; *part;) {
        size_t length = strcspn(part, "/");
        if (!length || (length == 1 && part[0] == '.') ||
            (length == 2 && part[0] == '.' && part[1] == '.')) return 0;
        part += length;
        if (*part == '/' && !*++part) return 0;
    }
    const char *prefix = "";
    if (strncmp(relative, "game/", 5) == 0) {
        prefix = "data/";
        relative += 5;
    } else if (strncmp(relative, "data/", 5) != 0 &&
               strncmp(relative, "b/", 2) != 0) return 0;
    size_t a = strlen(prefix), b = strlen(relative);
    if (a >= capacity || b >= capacity - a) return 0;
    memcpy(output, prefix, a);
    memcpy(output + a, relative, b + 1);
    return 1;
}
