#include "NativeWasmtimeHost.h"
#include <TargetConditionals.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <limits.h>
#include <time.h>
#include <unistd.h>

#if !TARGET_OS_SIMULATOR
#include <wasm.h>
#include <wasmtime/func.h>
#include <wasmtime/linker.h>
#include <wasmtime/extern.h>
#include <wasmtime/store.h>
#include <wasmtime/val.h>
#include <wasmtime/error.h>

/* Four *real* import implementations from the verified 86-import GTA
 * WebAssembly ABI. No unimplemented functions are silently stubbed, and this
 * intentionally does not instantiate the actual GTA engine. */
enum gta_host_function {
    GTA_MONOTONIC_MS = 1,
    GTA_EMSCRIPTEN_NOW = 2,
    GTA_WALLCLOCK_MS = 3,
    GTA_CPU_COUNT = 4
};

static double gta_clock_ms(clockid_t clock_id) {
    struct timespec stamp;
    if (clock_gettime(clock_id, &stamp) != 0) return -1.0;
    return (double)stamp.tv_sec * 1000.0 + (double)stamp.tv_nsec / 1000000.0;
}

static wasm_trap_t *gta_basic_callback(
    void *env, wasmtime_caller_t *caller, const wasmtime_val_t *args,
    size_t nargs, wasmtime_val_t *results, size_t nresults
) {
    (void)caller; (void)args;
    if (nargs != 0 || nresults != 1) return NULL;
    uintptr_t op = (uintptr_t)env;
    switch (op) {
        case GTA_MONOTONIC_MS:
        case GTA_EMSCRIPTEN_NOW:
            results[0].kind = WASMTIME_F64;
            results[0].of.f64 = gta_clock_ms(CLOCK_MONOTONIC);
            return NULL;
        case GTA_WALLCLOCK_MS:
            results[0].kind = WASMTIME_F64;
            results[0].of.f64 = gta_clock_ms(CLOCK_REALTIME);
            return NULL;
        case GTA_CPU_COUNT: {
            long n = sysconf(_SC_NPROCESSORS_ONLN);
            results[0].kind = WASMTIME_I32;
            results[0].of.i32 = (int32_t)(n > 0 && n <= INT32_MAX ? n : 1);
            return NULL;
        }
        default: return NULL;
    }
}

static void gta_host_message(char *dst, size_t capacity, const char *msg) {
    if (dst && capacity) {
        snprintf(dst, capacity, "%s", msg ? msg : "Unknown host error");
        dst[capacity - 1] = 0;
    }
}

static int gta_define(
    wasmtime_linker_t *linker, const char *name, uint8_t kind, uintptr_t op,
    char *message, size_t capacity
) {
    wasm_valtype_t *output = wasm_valtype_new(kind == WASMTIME_I32 ? WASM_I32 : WASM_F64);
    if (!output) {
        gta_host_message(message, capacity, "Could not allocate Wasm result type");
        return -1;
    }
    wasm_functype_t *type = wasm_functype_new_0_1(output);
    if (!type) {
        gta_host_message(message, capacity, "Could not allocate Wasm function type");
        return -2;
    }
    wasmtime_error_t *error = wasmtime_linker_define_func(
        linker, "env", 3, name, strlen(name), type, gta_basic_callback,
        (void *)op, NULL
    );
    wasm_functype_delete(type);
    if (error) {
        wasm_name_t why;
        wasmtime_error_message(error, &why);
        char buf[384] = {0};
        size_t n = why.size < sizeof(buf) - 1 ? why.size : sizeof(buf) - 1;
        if (n && why.data) memcpy(buf, why.data, n);
        gta_host_message(message, capacity, buf);
        wasm_byte_vec_delete(&why);
        wasmtime_error_delete(error);
        return -3;
    }
    return 0;
}

/* Returns 0 only when all four GTA-matching host functions are registered
 * and the linker successfully calls the native monotonic callback. This is
 * hardware runtime integration, NOT game engine instantiation. */
int gta_ios_wasmtime_basic_host_probe(unsigned int *installed,
                                      char *message, size_t capacity) {
    if (installed) *installed = 0;
    wasm_engine_t *engine = wasm_engine_new();
    if (!engine) {
        gta_host_message(message, capacity, "Wasmtime engine initialization unavailable");
        return -10;
    }
    wasmtime_linker_t *linker = wasmtime_linker_new(engine);
    if (!linker) {
        wasm_engine_delete(engine);
        gta_host_message(message, capacity, "Wasmtime linker initialization unavailable");
        return -11;
    }

    const struct { const char *name; uint8_t kind; uintptr_t op; } functions[] = {
        { "wasm_now_ms", WASMTIME_F64, GTA_MONOTONIC_MS },
        { "emscripten_get_now", WASMTIME_F64, GTA_EMSCRIPTEN_NOW },
        { "emscripten_date_now", WASMTIME_F64, GTA_WALLCLOCK_MS },
        { "emscripten_num_logical_cores", WASMTIME_I32, GTA_CPU_COUNT },
    };
    int result = 0;
    for (size_t i = 0; i < sizeof(functions) / sizeof(functions[0]); i++) {
        result = gta_define(linker, functions[i].name, functions[i].kind,
                            functions[i].op, message, capacity);
        if (result != 0) goto finish;
        if (installed) (*installed)++;
    }

    wasmtime_store_t *store = wasmtime_store_new(engine, NULL, NULL);
    if (!store) {
        result = -20;
        gta_host_message(message, capacity, "Wasmtime store allocation failed");
        goto finish;
    }
    wasmtime_context_t *context = wasmtime_store_context(store);
    wasmtime_extern_t exported = {0};
    if (!wasmtime_linker_get(linker, context, "env", 3,
                             "wasm_now_ms", strlen("wasm_now_ms"), &exported)
        || exported.kind != WASMTIME_EXTERN_FUNC) {
        result = -21;
        gta_host_message(message, capacity, "Monotonic clock linker resolution failed");
    } else {
        wasmtime_val_t value = {0};
        wasm_trap_t *trap = NULL;
        wasmtime_error_t *error = wasmtime_func_call(
            context, &exported.of.func, NULL, 0, &value, 1, &trap
        );
        if (error || trap || value.kind != WASMTIME_F64 || value.of.f64 < 0) {
            result = -22;
            gta_host_message(message, capacity, "Monotonic clock callback failed");
        } else {
            gta_host_message(message, capacity,
                "Four native GTA host callbacks registered; monotonic function invoked correctly");
        }
        if (error) wasmtime_error_delete(error);
        if (trap) wasm_trap_delete(trap);
    }
    if (exported.kind == WASMTIME_EXTERN_FUNC) wasmtime_extern_delete(&exported);
    wasmtime_store_delete(store);
finish:
    wasmtime_linker_delete(linker);
    wasm_engine_delete(engine);
    return result;
}
#else
int gta_ios_wasmtime_basic_host_probe(unsigned int *installed,
                                      char *message, size_t capacity) {
    if (installed) *installed = 0;
    if (message && capacity) snprintf(message, capacity, "%s", "Native Wasmtime host probe requires iPhone ARM64");
    return -100;
}
#endif
