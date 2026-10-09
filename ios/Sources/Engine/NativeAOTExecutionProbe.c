#include "NativeWasmtimeHost.h"
#include <TargetConditionals.h>
#include <stdio.h>
#include <string.h>

#if !TARGET_OS_SIMULATOR
#include <wasm.h>
#include <wasmtime/config.h>
#include <wasmtime/module.h>
#include <wasmtime/linker.h>
#include <wasmtime/instance.h>
#include <wasmtime/func.h>
#include <wasmtime/extern.h>
#include <wasmtime/store.h>
#include <wasmtime/error.h>
#include <wasmtime/val.h>

static void smoke_message(char *buf, size_t cap, const char *msg) {
    if (buf && cap) {
        snprintf(buf, cap, "%s", msg ? msg : "Unknown Wasmtime error");
        buf[cap - 1] = 0;
    }
}
static void smoke_wasmtime_error(char *buf, size_t cap, wasmtime_error_t *err) {
    if (!err) return;
    wasm_name_t message = {0};
    wasmtime_error_message(err, &message);
    if (buf && cap) {
        int len = message.size < cap-1 ? (int)message.size : (int)(cap-1);
        snprintf(buf, cap, "%.*s", len, message.data ? message.data : "");
    }
    wasm_byte_vec_delete(&message);
    wasmtime_error_delete(err);
}

/* Exact Wasmtime v49 AOT program: (i32,i32) -> i32 add.
 * Compiled during CI for aarch64-apple-ios. This test runs actual AOT
 * machine code through Wasmtime, not just deserializes its ELF metadata.
 * Do not confuse this synthetic probe with real GTA gameplay.
 */
int gta_ios_wasmtime_execute_smoke(const char *aot_path, char *message, size_t cap) {
    if (!aot_path || !*aot_path) {
        smoke_message(message, cap, "Missing trusted AOT fixture path");
        return -1;
    }
    wasm_config_t *cfg = wasm_config_new();
    if (!cfg) return -2;
    wasmtime_config_wasm_threads_set(cfg, true);
    wasmtime_config_shared_memory_set(cfg, true);
    wasmtime_config_wasm_memory64_set(cfg, true);
    wasm_engine_t *engine = wasm_engine_new_with_config(cfg);
    if (!engine) {
        smoke_message(message, cap, "Wasmtime engine unavailable");
        return -3;
    }

    int rc = 0;
    wasmtime_module_t *module = NULL;
    wasmtime_store_t *store = NULL;
    wasmtime_linker_t *linker = NULL;
    wasmtime_extern_t add = {0};
    bool have_add = false;
    wasm_trap_t *trap = NULL;
    wasmtime_error_t *error = wasmtime_module_deserialize_file(engine, aot_path, &module);
    if (error) { smoke_wasmtime_error(message, cap, error); rc = -4; goto cleanup; }
    if (!module) { smoke_message(message, cap, "AOT deserialization returned null"); rc = -5; goto cleanup; }
    store = wasmtime_store_new(engine, NULL, NULL);
    linker = wasmtime_linker_new(engine);
    if (!store || !linker) { smoke_message(message, cap, "Store or linker unavailable"); rc = -6; goto cleanup; }

    wasmtime_context_t *ctx = wasmtime_store_context(store);
    wasmtime_instance_t instance = {0};
    error = wasmtime_linker_instantiate(linker, ctx, module, &instance, &trap);
    if (error) { smoke_wasmtime_error(message, cap, error); rc = -7; goto cleanup; }
    if (trap) { smoke_message(message, cap, "AOT instantiation trapped"); rc = -8; goto cleanup; }

    if (!wasmtime_instance_export_get(ctx, &instance, "add", 3, &add)
        || add.kind != WASMTIME_EXTERN_FUNC) {
        smoke_message(message, cap, "AOT smoke export 'add' missing");
        rc = -9; goto cleanup;
    }
    have_add = true;
    wasmtime_val_t args[2] = {0};
    args[0].kind = WASMTIME_I32; args[0].of.i32 = 20;
    args[1].kind = WASMTIME_I32; args[1].of.i32 = 22;
    wasmtime_val_t result = {0};
    error = wasmtime_func_call(ctx, &add.of.func, args, 2, &result, 1, &trap);
    if (error) { smoke_wasmtime_error(message, cap, error); rc = -10; goto cleanup; }
    if (trap) { smoke_message(message, cap, "AOT execution trapped"); rc = -11; goto cleanup; }
    if (result.kind != WASMTIME_I32 || result.of.i32 != 42) {
        smoke_message(message, cap, "AOT result mismatch; expected add(20,22)=42");
        rc = -12; goto cleanup;
    }
    smoke_message(message, cap, "AOT ARM64 test code executed and returned 42; GTA game NOT started");
cleanup:
    if (have_add) wasmtime_extern_delete(&add);
    if (trap) wasm_trap_delete(trap);
    if (linker) wasmtime_linker_delete(linker);
    if (store) wasmtime_store_delete(store);
    if (module) wasmtime_module_delete(module);
    wasm_engine_delete(engine);
    return rc;
}
#else
int gta_ios_wasmtime_execute_smoke(const char *aot_path, char *message, size_t cap) {
    (void)aot_path;
    if (message && cap) snprintf(message, cap, "Device-only ARM64 AOT smoke test");
    return -100;
}
#endif
