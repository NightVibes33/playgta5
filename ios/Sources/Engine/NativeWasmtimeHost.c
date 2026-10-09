#include "NativeWasmtimeHost.h"
#include <TargetConditionals.h>

#if TARGET_OS_SIMULATOR
int gta_ios_wasmtime_engine_probe(void) {
    return -100; /* Device-only static library: no simulator runtime linked. */
}
#else
#include <wasm.h>
int gta_ios_wasmtime_engine_probe(void) {
    wasm_engine_t *engine = wasm_engine_new();
    if (!engine) return -1;
    wasm_engine_delete(engine);
    return 0;
}
#endif
