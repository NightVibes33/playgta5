#include "NativeWasmtimeHost.h"
#include <TargetConditionals.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if !TARGET_OS_SIMULATOR
#include <wasm.h>
#include <wasmtime/config.h>
#include <wasmtime/module.h>
#include <wasmtime/store.h>
#include <wasmtime/linker.h>
#include <wasmtime/instance.h>
#include <wasmtime/func.h>
#include <wasmtime/extern.h>
#include <wasmtime/sharedmemory.h>
#include <wasmtime/memory.h>
#include <wasmtime/error.h>
#include <wasmtime/val.h>

static void gta_memory_message(char *dst, size_t n, const char *source) {
    if (dst && n) {
        snprintf(dst, n, "%s", source ? source : "unknown");
        dst[n - 1] = 0;
    }
}

static void gta_memory_error(char *dst, size_t n, wasmtime_error_t *error) {
    if (!error) return;
    wasm_name_t text = {0};
    wasmtime_error_message(error, &text);
    if (dst && n) {
        size_t len = text.size < n - 1 ? text.size : n - 1;
        if (len && text.data) memcpy(dst, text.data, len);
        dst[len] = 0;
    }
    wasm_byte_vec_delete(&text);
    wasmtime_error_delete(error);
}

/* This is a real 64-bit, shared imported-memory test with a tiny 64 KiB
 * fixture. It does NOT allocate GTA's 3 GiB initial memory, register
 * unimplemented browser functions or instantiate the GTA executable.
 *
 * Fixture:
 *   (import "env" "memory" (memory i64 1 2 shared))
 *   (export "touch" (func (param i64) (result i32)
 *     i32.store 42, i32.load at address))
 * Returning 42 AND observing the native memory bytes proves execution,
 * imported shared memory linkage and host/guest coherence on the device.
 */
int gta_ios_wasmtime_memory64_smoke(const char *aot_path,
                                    char *message, size_t capacity) {
    int rc = -1;
    wasm_engine_t *engine = NULL;
    wasm_memorytype_t *type = NULL;
    wasmtime_sharedmemory_t *memory = NULL;
    wasmtime_module_t *module = NULL;
    wasmtime_store_t *store = NULL;
    wasmtime_linker_t *linker = NULL;
    wasmtime_extern_t exported = {0};
    bool exported_owned = false;
    wasmtime_extern_t input_export = {0};
    bool input_export_owned = false;
    bool input_bound = false;
    wasm_trap_t *trap = NULL;
    wasmtime_error_t *error = NULL;

    if (!aot_path || !aot_path[0]) {
        gta_memory_message(message, capacity, "Missing signed memory64 AOT smoke fixture");
        return -1;
    }
    wasm_config_t *config = wasm_config_new();
    if (!config) {
        gta_memory_message(message, capacity, "Wasmtime memory64 configuration unavailable");
        return -2;
    }
    wasmtime_config_wasm_threads_set(config, true);
    wasmtime_config_shared_memory_set(config, true);
    wasmtime_config_wasm_memory64_set(config, true);
    engine = wasm_engine_new_with_config(config);
    if (!engine) {
        gta_memory_message(message, capacity, "Wasmtime shared-memory engine initialization failed");
        return -3;
    }
    /* Explicit memory64, shared, 64 KiB pages, 1..2 pages only. */
    error = wasmtime_memorytype_new(1, true, 2, true, true, 16, &type);
    if (error || !type) {
        gta_memory_error(message, capacity, error);
        if (!error) gta_memory_message(message, capacity, "Memory64 shared type unavailable");
        rc = -4; goto cleanup;
    }
    error = wasmtime_sharedmemory_new(engine, type, &memory);
    if (error || !memory) {
        gta_memory_error(message, capacity, error);
        if (!error) gta_memory_message(message, capacity, "Could not allocate one-page shared memory");
        rc = -5; goto cleanup;
    }
    if (wasmtime_sharedmemory_size(memory) != 1
        || wasmtime_sharedmemory_data_size(memory) != 65536
        || !wasmtime_sharedmemory_data(memory)) {
        gta_memory_message(message, capacity, "Host shared memory size is invalid");
        rc = -6; goto cleanup;
    }
    error = wasmtime_module_deserialize_file(engine, aot_path, &module);
    if (error || !module) {
        gta_memory_error(message, capacity, error);
        if (!error) gta_memory_message(message, capacity, "Shared-memory AOT module absent");
        rc = -7; goto cleanup;
    }
    store = wasmtime_store_new(engine, NULL, NULL);
    linker = wasmtime_linker_new(engine);
    if (!store || !linker) {
        gta_memory_message(message, capacity, "Shared-memory store or linker unavailable");
        rc = -8; goto cleanup;
    }
    wasmtime_context_t *ctx = wasmtime_store_context(store);
    wasmtime_extern_t imported = {0};
    imported.kind = WASMTIME_EXTERN_SHAREDMEMORY;
    imported.of.sharedmemory = memory;
    error = wasmtime_linker_define(linker, ctx, "env", 3, "memory", 6, &imported);
    if (error) {
        gta_memory_error(message, capacity, error);
        rc = -9; goto cleanup;
    }
    wasmtime_instance_t instance = {0};
    error = wasmtime_linker_instantiate(linker, ctx, module, &instance, &trap);
    if (error || trap) {
        gta_memory_error(message, capacity, error);
        if (trap) gta_memory_message(message, capacity, "Shared memory module trapped at instantiation");
        rc = -10; goto cleanup;
    }
    if (!wasmtime_instance_export_get(ctx, &instance, "touch", 5, &exported)
        || exported.kind != WASMTIME_EXTERN_FUNC) {
        gta_memory_message(message, capacity, "Native memory64 fixture missing touch(i64)->i32");
        rc = -11; goto cleanup;
    }
    exported_owned = true;
    wasmtime_val_t args[1] = {0};
    args[0].kind = WASMTIME_I64;
    args[0].of.i64 = 16;
    wasmtime_val_t answer = {0};
    error = wasmtime_func_call(ctx, &exported.of.func, args, 1, &answer, 1, &trap);
    if (error || trap) {
        gta_memory_error(message, capacity, error);
        if (trap) gta_memory_message(message, capacity, "Memory64 touch function trapped");
        rc = -12; goto cleanup;
    }
    uint32_t observed = 0;
    memcpy(&observed, wasmtime_sharedmemory_data(memory) + 16, sizeof(observed));
    if (answer.kind != WASMTIME_I32 || answer.of.i32 != 42 || observed != 42) {
        gta_memory_message(message, capacity, "Guest / host memory64 contents disagree");
        rc = -13; goto cleanup;
    }
    /* Prove a genuine native GameController/touch frame is visible to an
     * AOT-compiled WASM guest through the 444-byte game input block.
     * This synthetic module reads a keyboard byte from guest memory; it
     * does not run GTA's original gameplay routines. */
    enum { INPUT_BLOCK = 512, VK_W_OFFSET = 0x57 };
    gta_native_input_bind_memory(wasmtime_sharedmemory_data(memory),
                                 wasmtime_sharedmemory_data_size(memory));
    input_bound = true;
    gta_native_input_publish_block(INPUT_BLOCK);
    gta_native_pad_frame_t pad = {0};
    pad.active = 1;
    pad.ly = 0.8f; /* Forward motion -> original virtual key W */
    pad.width = 960;
    pad.height = 540;
    if (gta_native_input_apply(&pad) != 0) {
        gta_memory_message(message, capacity, "Native controller input could not be applied to AOT shared memory");
        rc = -14; goto cleanup;
    }
    if (!wasmtime_instance_export_get(ctx, &instance, "input_w", 7, &input_export)
            || input_export.kind != WASMTIME_EXTERN_FUNC) {
        gta_memory_message(message, capacity, "AOT fixture missing compiled input_w(i64)->i32");
        rc = -15; goto cleanup;
    }
    input_export_owned = true;
    wasmtime_val_t input_address[1] = {0};
    input_address[0].kind = WASMTIME_I64;
    input_address[0].of.i64 = INPUT_BLOCK + VK_W_OFFSET;
    wasmtime_val_t key_pressed = {0};
    error = wasmtime_func_call(ctx, &input_export.of.func, input_address, 1,
                               &key_pressed, 1, &trap);
    if (error || trap || key_pressed.kind != WASMTIME_I32
            || key_pressed.of.i32 != 0x80) {
        gta_memory_error(message, capacity, error);
        if (trap || !error) gta_memory_message(message, capacity,
            "Native-to-WASM input press was not visible in compiled AOT code");
        rc = -16; goto cleanup;
    }
    pad.active = 0;
    if (gta_native_input_apply(&pad) != 0) {
        gta_memory_message(message, capacity, "Native controller release failed");
        rc = -17; goto cleanup;
    }
    wasmtime_val_t key_released = {0};
    error = wasmtime_func_call(ctx, &input_export.of.func, input_address, 1,
                               &key_released, 1, &trap);
    if (error || trap || key_released.kind != WASMTIME_I32
            || key_released.of.i32 != 0) {
        gta_memory_error(message, capacity, error);
        if (trap || !error) gta_memory_message(message, capacity,
            "AOT guest retained a released controller key");
        rc = -18; goto cleanup;
    }
    gta_memory_message(message, capacity,
        "PASS: ARM64 memory64 AOT guest executed, shared host data=42; native controller W press=128 and release=0 read by guest. GTA NOT running.");
    rc = 0;
cleanup:
    /* Never leave the live gamepad publisher pointing into freed guest memory. */
    if (input_bound) gta_native_input_unbind();
    if (input_export_owned) wasmtime_extern_delete(&input_export);
    if (exported_owned) wasmtime_extern_delete(&exported);
    if (trap) wasm_trap_delete(trap);
    if (linker) wasmtime_linker_delete(linker);
    if (store) wasmtime_store_delete(store);
    if (module) wasmtime_module_delete(module);
    if (memory) wasmtime_sharedmemory_delete(memory);
    if (type) wasm_memorytype_delete(type);
    if (engine) wasm_engine_delete(engine);
    return rc;
}
#else
int gta_ios_wasmtime_memory64_smoke(const char *aot_path,
                                   char *message, size_t capacity) {
    (void)aot_path;
    if (message && capacity)
        snprintf(message, capacity, "Shared memory64 AOT test requires iPhone ARM64");
    return -100;
}
#endif
