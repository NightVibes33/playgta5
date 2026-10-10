#include "NativeWasmtimeHost.h"
#include <TargetConditionals.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

#if !TARGET_OS_SIMULATOR
#include <wasm.h>
#include <wasmtime/error.h>
#include <wasmtime/config.h>
#include <wasmtime/module.h>
#include <wasmtime/linker.h>
#include <wasmtime/extern.h>
#include <wasmtime/func.h>
#include <wasmtime/store.h>
extern int gta_ios_wasmtime_register_host_basics(wasmtime_linker_t *, unsigned int *, char *, size_t);
static bool gta_types_match(const wasm_functype_t *a, const wasm_functype_t *b) {
    if (!a || !b) return false;
    const wasm_valtype_vec_t *ap=wasm_functype_params(a), *bp=wasm_functype_params(b);
    const wasm_valtype_vec_t *ar=wasm_functype_results(a), *br=wasm_functype_results(b);
    if (ap->size!=bp->size || ar->size!=br->size) return false;
    for(size_t i=0;i<ap->size;i++) if(wasm_valtype_kind(ap->data[i])!=wasm_valtype_kind(bp->data[i])) return false;
    for(size_t i=0;i<ar->size;i++) if(wasm_valtype_kind(ar->data[i])!=wasm_valtype_kind(br->data[i])) return false;
    return true;
}


/* The definitive function type inventory comes from the SHA-verified
 * private module, NOT the larger superset in minified game.js. */
static const char *gta_wasm_kind(wasm_valkind_t k) {
    switch (k) {
        case WASM_I32: return "i32";
        case WASM_I64: return "i64";
        case WASM_F32: return "f32";
        case WASM_F64: return "f64";
        default: return "ref-or-vector";
    }
}
static void gta_audit_append(char *buffer, size_t capacity, size_t *used,
                             const char *fmt, ...) {
    if (!buffer || !capacity || *used >= capacity - 1) return;
    va_list args;
    va_start(args, fmt);
    int n = vsnprintf(buffer + *used, capacity - *used, fmt, args);
    va_end(args);
    if (n < 0) return;
    size_t available = capacity - *used;
    *used += (size_t)n >= available ? available - 1 : (size_t)n;
}
static void gta_audit_import(char *buffer, size_t capacity, size_t *used,
                             const wasm_name_t *module, const wasm_name_t *name,
                             const wasm_externtype_t *type, bool mismatch) {
    gta_audit_append(buffer, capacity, used, "\\n%s %.*s.%.*s",
        mismatch ? "TYPE_MISMATCH" : "UNRESOLVED",
        (int)(module->size > 96 ? 96 : module->size), module->data,
        (int)(name->size > 128 ? 128 : name->size), name->data);
    if (wasm_externtype_kind(type) != WASM_EXTERN_FUNC) {
        gta_audit_append(buffer, capacity, used, " [non-function import]");
        return;
    }
    const wasm_functype_t *signature = wasm_externtype_as_functype_const(type);
    const wasm_valtype_vec_t *params = wasm_functype_params(signature);
    const wasm_valtype_vec_t *results = wasm_functype_results(signature);
    gta_audit_append(buffer, capacity, used, "(");
    for (size_t j=0; j<params->size; ++j)
        gta_audit_append(buffer, capacity, used, "%s%s",
            j ? "," : "", gta_wasm_kind(wasm_valtype_kind(params->data[j])));
    gta_audit_append(buffer, capacity, used, ")->");
    if (!results->size) gta_audit_append(buffer, capacity, used, "void");
    for (size_t j=0; j<results->size; ++j)
        gta_audit_append(buffer, capacity, used, "%s%s",
            j ? "," : "", gta_wasm_kind(wasm_valtype_kind(results->data[j])));
}

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
                              unsigned int *import_count, unsigned int *covered_count,
                              char *error_message, size_t error_capacity) {
    if (import_count) *import_count = 0;
    if (covered_count) *covered_count = 0;
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
    // Require exactly the GC-disabled profile used when compiling our
    // signed iOS AOT modules; the static Wasmtime host has no GC feature.
    wasmtime_config_gc_support_set(config, false);
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

    // Verify actual C-API linker exports and exact function signatures, not
    // just string names. No fake defaults, 3 GiB memory, or engine execution.
    wasmtime_linker_t *linker = wasmtime_linker_new(engine);
    wasmtime_store_t *store = linker ? wasmtime_store_new(engine, NULL, NULL) : NULL;
    if (!linker || !store) {
        aot_message(error_message, error_capacity, "Host import audit linker/store unavailable");
        if (store) wasmtime_store_delete(store);
        if (linker) wasmtime_linker_delete(linker);
        wasm_importtype_vec_delete(&imports);
        wasmtime_module_delete(module);
        wasm_engine_delete(engine);
        return -40;
    }
    unsigned int registered = 0;
    int registration = gta_ios_wasmtime_register_host_basics(linker, &registered,
        error_message, error_capacity);
    if (registration) {
        wasmtime_store_delete(store); wasmtime_linker_delete(linker);
        wasm_importtype_vec_delete(&imports); wasmtime_module_delete(module);
        wasm_engine_delete(engine);
        return -41;
    }
    unsigned int covered = 0;
    char missing_report[12000] = {0};
    size_t missing_used = 0;
    char first_missing[144] = {0};
    wasmtime_context_t *context = wasmtime_store_context(store);
    for (size_t i=0; i<imports.size; ++i) {
        const wasm_importtype_t *entry = imports.data[i];
        const wasm_name_t *mod = wasm_importtype_module(entry);
        const wasm_name_t *name = wasm_importtype_name(entry);
        const wasm_externtype_t *expected = wasm_importtype_type(entry);
        wasmtime_extern_t existing = {0};
        bool found = wasmtime_linker_get(linker, context,
            mod->data, mod->size, name->data, name->size, &existing);
        bool valid = false;
        if (found) {
            wasm_externtype_t *actual = wasmtime_extern_type(context, &existing);
            if (actual && wasm_externtype_kind(expected)==WASM_EXTERN_FUNC
                    && wasm_externtype_kind(actual)==WASM_EXTERN_FUNC)
                valid = gta_types_match(wasm_externtype_as_functype_const(expected),
                                        wasm_externtype_as_functype_const(actual));
            if (actual) wasm_externtype_delete(actual);
            wasmtime_extern_delete(&existing);
        }
        if (valid) ++covered;
        else {
            if (!first_missing[0]) {
                snprintf(first_missing, sizeof(first_missing), "%.*s.%.*s",
                    (int)(mod->size>40?40:mod->size), mod->data,
                    (int)(name->size>88?88:name->size), name->data);
            }
            gta_audit_import(missing_report, sizeof(missing_report), &missing_used,
                             mod, name, expected, found);
        }
    }
    if (covered_count) *covered_count = covered;
    if (error_message && error_capacity) {
        snprintf(error_message, error_capacity,
            "Host ABI: %u/%u imports linked, %u unresolved, first=%s; game NOT instantiated.",
            covered, (unsigned int)imports.size, (unsigned int)imports.size-covered,
            first_missing[0]?first_missing:"(none)");
        size_t used = strlen(error_message);
        gta_audit_append(error_message, error_capacity, &used,
            "\\nVerified module unresolved import signatures:%s", missing_report);
    }
    wasmtime_store_delete(store);
    wasmtime_linker_delete(linker);
    wasm_importtype_vec_delete(&imports);
    wasmtime_module_delete(module);
    wasm_engine_delete(engine);
    return 0;
#endif
}
