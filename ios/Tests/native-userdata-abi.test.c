#define _POSIX_C_SOURCE 200809L
#include "../Sources/Engine/NativeUserdataHostABI.h"
#include <assert.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int main(void) {
    char root[] = "/tmp/gtaios-userdata-XXXXXX";
    assert(mkdtemp(root) != NULL);
    uint8_t memory[2048] = {0};
    const char *path = "/userdata/Documents/GTAV/Profile 1/SGTA50001";
    strcpy((char *)memory + 32, path);
    strcpy((char *)memory + 160, "/userdata/Documents/GTAV/../evil");
    strcpy((char *)memory + 240, "/userdata/Documents/GTAV/Profile 1/SGTA50002");
    const char payload[] = "real GTA userdata bytes 00\x01\x02";
    memcpy(memory + 600, payload, sizeof(payload));
    assert(gta_userdata_set_root(root) == 0);
    gta_userdata_bind_memory(memory, sizeof(memory));
    assert(gta_userdata_put_js(32, 600, sizeof(payload), 1700000000123.0) == 0);
    char file[1024];
    snprintf(file, sizeof(file), "%s/Documents/GTAV/Profile 1/SGTA50001", root);
    int fd = open(file, O_RDONLY);
    assert(fd >= 0);
    char found[sizeof(payload)] = {0};
    assert(read(fd, found, sizeof(found)) == (ssize_t)sizeof(found));
    assert(memcmp(found, payload, sizeof(payload)) == 0);
    struct stat attr;
    assert(fstat(fd, &attr) == 0);
    assert(attr.st_mtime == 1700000000);
    close(fd);
    assert(gta_userdata_put_js(160, 600, 3, 1700000000123.0) < 0);
    assert(gta_userdata_take_error() < 0);
    assert(gta_userdata_take_error() == 0);
    assert(gta_userdata_put_js(32, 600, (uint64_t)GTA_USERDATA_MAX_FILE+1, 0) < 0);
    assert(gta_userdata_put_js(32, 2047, 10, 0) < 0);
    assert(gta_userdata_delete_js(32) == 0);
    assert(access(file, F_OK) != 0);
    assert(gta_userdata_delete_js(32) == 0); /* idempotent */
    assert(gta_userdata_put_js(240, 600, 6, 0) == 0);
    gta_userdata_unbind_memory();
    assert(gta_userdata_put_js(32, 600, 5, 0) < 0);
    assert(gta_userdata_delete_js(32) < 0);
    assert(gta_userdata_take_error() < 0);
    assert(gta_userdata_set_root("relative/root") < 0);
    char second[1024];
    snprintf(second, sizeof(second), "%s/Documents/GTAV/Profile 1/SGTA50002", root);
    assert(unlink(second) == 0);
    char nested[1024];
    snprintf(nested, sizeof(nested), "%s/Documents/GTAV/Profile 1", root);
    assert(rmdir(nested) == 0);
    snprintf(nested, sizeof(nested), "%s/Documents/GTAV", root);
    assert(rmdir(nested) == 0);
    snprintf(nested, sizeof(nested), "%s/Documents", root);
    assert(rmdir(nested) == 0);
    assert(rmdir(root) == 0);
    puts("PASS: real GTA userdata put/delete ABI: guest memory64 validation, sandbox paths, atomic persistence, mtime and deletion");
    return 0;
}
