#include "../Sources/Engine/NativeTextHostABI.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    uint8_t memory[512] = {0};
    memcpy(memory + 16, "frameLimit", 11);
    memcpy(memory + 128, "GTA engine initialising\n", 24);
    memcpy(memory + 192, "The engine is waiting", 22);
    gta_text_host_bind_memory(memory, sizeof(memory));

    assert(gta_text_host_module_int_js(16, 30) == 30);
    assert(gta_text_host_set_int("frameLimit", 60) == 0);
    assert(gta_text_host_module_int_js(16, 30) == 60);
    assert(gta_text_host_module_int_js(700, 77) == 77);
    assert(gta_text_host_set_int("", 0) == -1);

    gta_text_host_print_line_js(128);
    gta_text_host_hang_line_js(192);
    gta_text_host_print_line_js(700);
    char line[256];
    assert(gta_text_host_next_log(line, sizeof(line)) == 1);
    assert(strstr(line, "[engine] GTA engine initialising") != NULL);
    assert(gta_text_host_next_log(line, sizeof(line)) == 1);
    assert(strstr(line, "[engine-hang] The engine is waiting") != NULL);
    assert(gta_text_host_next_log(line, sizeof(line)) == 1);
    assert(strstr(line, "invalid guest text pointer") != NULL);
    assert(gta_text_host_next_log(line, sizeof(line)) == 0);

    gta_text_host_unbind_memory();
    assert(gta_text_host_module_int_js(16, 13) == 13);
    gta_text_host_print_line_js(16);
    assert(gta_text_host_next_log(line, sizeof(line)) == 1);
    assert(strstr(line, "invalid guest text pointer") != NULL);
    puts("PASS: actual GTA text/diagnostic host ABI (bounded memory64 strings, config lookup and FIFO)");
    return 0;
}
