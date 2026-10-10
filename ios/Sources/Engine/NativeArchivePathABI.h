#ifndef GTA_NATIVE_ARCHIVE_PATH_ABI_H
#define GTA_NATIVE_ARCHIVE_PATH_ABI_H
#include <stddef.h>
#include <stdint.h>
/* Guest flags are Emscripten/Linux values, never Darwin O_* values. */
int gta_archive_flags_readonly(int32_t flags);
/* Translate the manifest's /game/ mount into external data/, without I/O. */
int gta_archive_relative_path(const char *guest, char *output, size_t capacity);
#endif
