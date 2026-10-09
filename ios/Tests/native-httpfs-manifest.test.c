#include "../Sources/Engine/NativeHTTPFSManifestABI.h"
#include <assert.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>
int main(void) {
    unsigned char memory[128];
    memset(memory, 0xA5, sizeof(memory));
    assert(gta_httpfs_manifest_js(0, 0) == -1);
    const char json[] = "{\"a\":1}";
    assert(gta_httpfs_manifest_stage(json, sizeof(json)-1) == 0);
    assert(gta_httpfs_manifest_length() == sizeof(json)-1);
    assert(gta_httpfs_manifest_js(UINT64_MAX, 0) == 7); /* Size query: no writes */
    gta_httpfs_manifest_bind_memory(memory, sizeof(memory));
    assert(gta_httpfs_manifest_js(20, 7) == 7); /* Capacity == length: no copy */
    assert(memory[20] == 0xA5);
    assert(gta_httpfs_manifest_js(20, 8) == 7);
    assert(memcmp(memory+20, json, sizeof(json)) == 0);
    assert(memory[19] == 0xA5 && memory[28] == 0xA5);
    assert(gta_httpfs_manifest_js(124, 20) == -1); /* No overrun */
    assert(gta_httpfs_manifest_js(UINT64_MAX, 20) == -1); /* No overflow */
    gta_httpfs_manifest_unbind_memory();
    assert(gta_httpfs_manifest_js(0, 20) == -1);
    gta_httpfs_manifest_clear();
    assert(gta_httpfs_manifest_length() == 0);
    assert(gta_httpfs_manifest_js(0, 0) == -1);
    printf("PASS: verified GTA HTTPFS manifest ABI, null termination, bounds, and size-query semantics\n");
}
