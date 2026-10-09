#include "NativeWasmtimeHost.h"
#include <TargetConditionals.h>
#include <stdio.h>
#include <string.h>

#if !TARGET_OS_SIMULATOR
#include <wasm.h>
#include <wasmtime.h>
#endif

static void aot_message(char *out, size_t capacity, const char *msg) {
    if (out && capacity) {
        snprintf(out, capacity, "%s", msg ? msg : "unknown");
        out[capacity - 1] = '\0';
    }
}

/* Only caller-verified, SHA256-allowlisted Wasmtime 49.0.2 AOT files may be
   handed to this API. Wasmtime's deserialize_* functions are unsafe on
   arbitrary inputs, and may be blocked by executable memory signing on iOS.
   This function never instantiates the module or executes its exports. */
int gta_ios_wasmtime_aot_probe(const char *path,
                              unsigned int *import_count,
                              char *error_message, size_t error_capacity) {
    if (import_count) *import_count = 0;
#if TARGET_OS_SIMULATOR
    aot_message(error_message, error_capacity,
                "Wasmtime AOT module inspection is supported only on a signed iOS device");
    return -100;
#else
    if (!path || !path[0]) {
        aot_message(error_message, error_capacity, "AOT file path missing");
        return -10;
    }

    wasm_config_t *config = wasm_config_new();
    if (!config) {
        aot_message(error_message, error_capacity, "Wasmtime configuration failed");
        return -11;
    }
    wasmtime_config_wasm_threads_set(config, true);
    wasmtime_config_shared_memory_set(config, true);
    wasmtime_config_wasm_memory64_set(config, true);
    wasm_engine_t *engine = wasm_engine_new_with_config(config);
    if (!engine) {
        aot_message(error_message, error_capacity, "Wasmtime engine unavailable on this iOS signing environment");
        return -12;
    }

    wasmtime_module_t *module = NULL;
    wasmtime_error_t *error = wasmtime_module_deserialize_file(engine, path, &module);
    if (error) {
        wasm_name_t details;
        wasmtime_error_message(error, &details);
        char temporary[768] = {0};
        size_t length = details.size < sizeof(temporary)-1 ? details.size : sizeof(temporary)-1;
        if (length && details.data) memcpy(temporary, details.data, length);
        aot_message(error_message, error_capacity, temporary);
        wasm_byte_vec_delete(&details);
        wasmtime_error_delete(error);
        wasm_engine_delete(engine);
        return -20;
    }
    if (!module) {
        aot_message(error_message, error_capacity, "Wasmtime returned a null deserialized module");
        wasm_engine_delete(engine);
        return -21;
    }

    wasm_importtype_vec_t imports = {0};
    wasmtime_module_imports(module, &imports);
    if (import_count) *import_count = (unsigned int)imports.size;

    if (imports.size != 86) {
        aot_message(error_message, error_capacity, "Compiled module imported ABI count differs from the verified GTA engine");
        wasm_importtype_vec_delete(&imports);
        wasmtime_module_delete(module);
        wasm_engine_delete(engine);
        return -30;
    }

    wasm_importtype_vec_delete(&imports);
    wasmtime_module_delete(module);
    wasm_engine_delete(engine);
    aot_message(error_message, error_capacity,
                "AOT module deserialized and 86 imports enumerated; game is NOT instantiated");
    return 0;
#endif
}
