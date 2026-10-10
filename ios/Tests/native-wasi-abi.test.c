#include "../Sources/Engine/NativeWASIHostABI.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static uint64_t le64(const unsigned char *p) {
    uint64_t n=0;
    for (unsigned i=0;i<8;i++) n|=(uint64_t)p[i]<<(8*i);
    return n;
}
int main(void) {
    unsigned char memory[80];
    memset(memory, 0xA5, sizeof(memory));
    gta_wasi_unbind_memory();
    assert(gta_wasi_clock_time_get(1, 1, 8)==21);
    assert(gta_wasi_environ_sizes_get(0, 8)==21);
    assert(gta_wasi_environ_get(0, 0)==21);
    gta_wasi_bind_memory(memory, sizeof memory);
    assert(gta_wasi_clock_time_get(1, 1, 8)==0);
    assert(le64(memory+8)>0);
    assert(gta_wasi_clock_time_get(0, 1000000, 16)==0);
    assert(le64(memory+16)>1000000000ULL);
    assert(gta_wasi_clock_time_get(999, 0, 32)==28);
    assert(gta_wasi_clock_time_get(1, 0, 76)==21);
    assert(gta_wasi_clock_time_get(1, 0, UINT64_MAX)==21);
    assert(memory[76]==0xA5);
    assert(gta_wasi_environ_sizes_get(24, 32)==0);
    assert(le64(memory+24)==0 && le64(memory+32)==0);
    assert(memory[40]==0xA5);
    assert(gta_wasi_environ_sizes_get(74, 32)==21);
    assert(gta_wasi_environ_sizes_get(UINT64_MAX, 0)==21);
    assert(gta_wasi_environ_get(80, 80)==0);
    assert(gta_wasi_environ_get(81, 80)==21);
    assert(gta_wasi_environ_get(80, UINT64_MAX)==21);
    gta_wasi_unbind_memory();
    assert(gta_wasi_environ_sizes_get(0, 8)==21);
    assert(gta_wasi_clock_time_get(1, 0, 8)==21);
    printf("PASS: actual memory64 WASI clock_time_get, environ_sizes_get, environ_get; bounds/unbind/secret-free env\n");
    return 0;
}
