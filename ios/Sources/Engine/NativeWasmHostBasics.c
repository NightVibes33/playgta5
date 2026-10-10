#include "NativeWasmtimeHost.h"
#include "NativeTextHostABI.h"
#include "NativeUserdataHostABI.h"
#include "NativeWASIHostABI.h"
#include "NativeGameAudioABI.h"
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
    GTA_CPU_COUNT = 4,
    GTA_HEAP_MAX = 5,
    GTA_HAS_BROWSER_PAGE = 6,
    GTA_HAS_USERDATA_WORKER = 7,
    GTA_BLOCKING_ALLOWED_CHECK = 8
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
    if (nargs != 0) return NULL;
    uintptr_t op = (uintptr_t)env;
    if (op == GTA_BLOCKING_ALLOWED_CHECK) return NULL; // Empty callback per original game.js
    if (nresults != 1) return NULL;
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
        case GTA_HAS_BROWSER_PAGE:
        case GTA_HAS_USERDATA_WORKER:
            // No native browser page or JS userdata worker has been implemented.
            results[0].kind = WASMTIME_I32;
            results[0].of.i32 = 0;
            return NULL;
        case GTA_HEAP_MAX:
            // Exact maximum declared by the real GTA WASM memory64 import:
            // 262144 pages * 65536 bytes = 16 GiB. This is a WASM contract
            // limit, not a promise that iOS can actually reserve that much.
            results[0].kind = WASMTIME_I64;
            results[0].of.i64 = INT64_C(262144) * INT64_C(65536);
            return NULL;
        default: return NULL;
    }
}

/* The original WASM engine's env.wasm_input_publish_js(i64)->void
 * publishes the address of its real WasmInputBlock in shared memory.
 * No fake gamepad ABI is invented; this is the verified keyboard/mouse ABI.
 */
static wasm_trap_t *gta_native_input_callback(
    void *env, wasmtime_caller_t *caller, const wasmtime_val_t *args,
    size_t nargs, wasmtime_val_t *results, size_t nresults
) {
    (void)env; (void)caller; (void)results;
    if (nargs == 1 && nresults == 0 && args[0].kind == WASMTIME_I64)
        gta_native_input_publish_block((uint64_t)args[0].of.i64);
    return NULL;
}

static int gta_define_input_callback(wasmtime_linker_t *linker) {
    wasm_valtype_t *param = wasm_valtype_new(WASM_I64);
    if (!param) return -1;
    wasm_functype_t *type = wasm_functype_new_1_0(param);
    if (!type) return -2;
    const char *name = "wasm_input_publish_js";
    wasmtime_error_t *error = wasmtime_linker_define_func(
        linker, "env", 3, name, strlen(name), type,
        gta_native_input_callback, NULL, NULL);
    wasm_functype_delete(type);
    if (error) { wasmtime_error_delete(error); return -3; }
    return 0;
}

/* Real Emscripten host ABI: wasm_httpfs_manifest_js(i64 buffer, i32 cap)
 * -> i32 needed bytes, reading the staged USB data/manifest.json.
 * No implicit HTTP fetch, no archive copying, no fabricated JSON.
 */
static wasm_trap_t *gta_httpfs_manifest_callback(
    void *env, wasmtime_caller_t *caller, const wasmtime_val_t *args,
    size_t nargs, wasmtime_val_t *results, size_t nresults
) {
    (void)env; (void)caller;
    if (nargs != 2 || nresults != 1 || args[0].kind != WASMTIME_I64
                   || args[1].kind != WASMTIME_I32) return NULL;
    results[0].kind = WASMTIME_I32;
    results[0].of.i32 = gta_httpfs_manifest_js(
        (uint64_t)args[0].of.i64, args[1].of.i32);
    return NULL;
}

static int gta_define_manifest_callback(wasmtime_linker_t *linker) {
    wasm_valtype_t *ptr = wasm_valtype_new(WASM_I64);
    wasm_valtype_t *cap = wasm_valtype_new(WASM_I32);
    wasm_valtype_t *result = wasm_valtype_new(WASM_I32);
    if (!ptr || !cap || !result) return -1;
    wasm_functype_t *type = wasm_functype_new_2_1(ptr, cap, result);
    if (!type) return -2;
    const char *name = "wasm_httpfs_manifest_js";
    wasmtime_error_t *error = wasmtime_linker_define_func(
        linker, "env", 3, name, strlen(name), type,
        gta_httpfs_manifest_callback, NULL, NULL);
    wasm_functype_delete(type);
    if (error) { wasmtime_error_delete(error); return -3; }
    return 0;
}

/* These are exact host signatures from the uploaded GTA engine:
 * wasm_print_line_js(i64) -> void
 * wasm_hang_line_js(i64) -> void
 * wasm_module_int_js(i64,i32) -> i32
 *
 * No browser object is simulated. Guest strings require an explicitly bound
 * live memory64 allocation, and engine log lines are exported through Swift.
 */
static wasm_trap_t *gta_text_line_callback(
    void *env, wasmtime_caller_t *caller, const wasmtime_val_t *args,
    size_t nargs, wasmtime_val_t *results, size_t nresults
) {
    (void)caller; (void)results;
    if (nargs != 1 || nresults != 0 || args[0].kind != WASMTIME_I64) return NULL;
    if ((uintptr_t)env == 1) gta_text_host_print_line_js((uint64_t)args[0].of.i64);
    else gta_text_host_hang_line_js((uint64_t)args[0].of.i64);
    return NULL;
}
static wasm_trap_t *gta_module_int_callback(
    void *env, wasmtime_caller_t *caller, const wasmtime_val_t *args,
    size_t nargs, wasmtime_val_t *results, size_t nresults
) {
    (void)env; (void)caller;
    if (nargs != 2 || nresults != 1 ||
        args[0].kind != WASMTIME_I64 || args[1].kind != WASMTIME_I32) return NULL;
    results[0].kind = WASMTIME_I32;
    results[0].of.i32 = gta_text_host_module_int_js(
        (uint64_t)args[0].of.i64, args[1].of.i32);
    return NULL;
}
static int gta_define_text_callbacks(wasmtime_linker_t *linker) {
    const struct { const char *name; uintptr_t tag; } one_arg[] = {
        { "wasm_print_line_js", 1 }, { "wasm_hang_line_js", 2 }
    };
    for (size_t i = 0; i < 2; ++i) {
        wasm_valtype_t *ptr = wasm_valtype_new(WASM_I64);
        if (!ptr) return -1;
        wasm_functype_t *type = wasm_functype_new_1_0(ptr);
        if (!type) return -2;
        wasmtime_error_t *error = wasmtime_linker_define_func(
            linker, "env", 3, one_arg[i].name, strlen(one_arg[i].name),
            type, gta_text_line_callback, (void *)one_arg[i].tag, NULL);
        wasm_functype_delete(type);
        if (error) { wasmtime_error_delete(error); return -3; }
    }
    wasm_valtype_t *ptr = wasm_valtype_new(WASM_I64);
    wasm_valtype_t *fallback = wasm_valtype_new(WASM_I32);
    wasm_valtype_t *result = wasm_valtype_new(WASM_I32);
    if (!ptr || !fallback || !result) return -4;
    wasm_functype_t *type = wasm_functype_new_2_1(ptr, fallback, result);
    if (!type) return -5;
    const char *name = "wasm_module_int_js";
    wasmtime_error_t *error = wasmtime_linker_define_func(
        linker, "env", 3, name, strlen(name), type,
        gta_module_int_callback, NULL, NULL);
    wasm_functype_delete(type);
    if (error) { wasmtime_error_delete(error); return -6; }
    return 0;
}

/* Exact signatures from the uploaded GTA WebAssembly binary:
 * env.wasm_userdata_put_js(i64 path,i64 bytes,i64 size,f64 mtimeMs)->void
 * env.wasm_userdata_delete_js(i64 path)->void.
 * Original game.js hands writes/deletes asynchronously to IndexedDB.
 * Native implementation persists them atomically in the app's save sandbox.
 * Failure is retained for Files-exportable diagnostics; void guest ABI cannot
 * report write failures synchronously back to game.wasm.
 */
static wasm_trap_t *gta_userdata_put_callback(
    void *env, wasmtime_caller_t *caller, const wasmtime_val_t *args,
    size_t nargs, wasmtime_val_t *results, size_t nresults
) {
    (void)env; (void)caller; (void)results;
    if (nargs == 4 && nresults == 0 &&
        args[0].kind == WASMTIME_I64 && args[1].kind == WASMTIME_I64 &&
        args[2].kind == WASMTIME_I64 && args[3].kind == WASMTIME_F64) {
        (void)gta_userdata_put_js((uint64_t)args[0].of.i64,
            (uint64_t)args[1].of.i64, (uint64_t)args[2].of.i64,
            args[3].of.f64);
    }
    return NULL;
}
static wasm_trap_t *gta_userdata_delete_callback(
    void *env, wasmtime_caller_t *caller, const wasmtime_val_t *args,
    size_t nargs, wasmtime_val_t *results, size_t nresults
) {
    (void)env; (void)caller; (void)results;
    if (nargs == 1 && nresults == 0 && args[0].kind == WASMTIME_I64)
        (void)gta_userdata_delete_js((uint64_t)args[0].of.i64);
    return NULL;
}
static int gta_define_userdata_callbacks(wasmtime_linker_t *linker) {
    wasm_valtype_t *params[4] = {
        wasm_valtype_new(WASM_I64), wasm_valtype_new(WASM_I64),
        wasm_valtype_new(WASM_I64), wasm_valtype_new(WASM_F64)
    };
    if (!params[0] || !params[1] || !params[2] || !params[3]) {
        for (int i=0; i<4; ++i) if (params[i]) wasm_valtype_delete(params[i]);
        return -1;
    }
    wasm_valtype_vec_t inputs, outputs;
    wasm_valtype_vec_new(&inputs, 4, params);
    wasm_valtype_vec_new_empty(&outputs);
    wasm_functype_t *put_type = wasm_functype_new(&inputs, &outputs);
    if (!put_type) return -2;
    const char *put_name = "wasm_userdata_put_js";
    wasmtime_error_t *error = wasmtime_linker_define_func(
        linker, "env", 3, put_name, strlen(put_name), put_type,
        gta_userdata_put_callback, NULL, NULL);
    wasm_functype_delete(put_type);
    if (error) { wasmtime_error_delete(error); return -3; }

    wasm_valtype_t *path = wasm_valtype_new(WASM_I64);
    if (!path) return -4;
    wasm_functype_t *delete_type = wasm_functype_new_1_0(path);
    if (!delete_type) return -5;
    const char *delete_name = "wasm_userdata_delete_js";
    error = wasmtime_linker_define_func(
        linker, "env", 3, delete_name, strlen(delete_name), delete_type,
        gta_userdata_delete_callback, NULL, NULL);
    wasm_functype_delete(delete_type);
    if (error) { wasmtime_error_delete(error); return -6; }
    return 0;
}

/* Native WASI preview1 host functions. The verified uploaded 63MiB engine
 * imports i32,i64,i64 -> i32 clock and i64,i64 -> i32 environment functions.
 * Unlike no-op linker placeholders, these validate guest memory64 offsets
 * and write the actual expected WASI output cells. The embedding runtime
 * must bind the live shared memory before GTA can call these callbacks.
 */
enum { GTA_WASI_CLOCK=1, GTA_WASI_ENV_SIZES=2, GTA_WASI_ENV_GET=3,
       GTA_WASI_FD_WRITE=4, GTA_WASI_FD_CLOSE=5, GTA_WASI_FD_READ=6,
       GTA_WASI_FD_SEEK=7, GTA_WASI_FD_PREAD=8 };
static wasm_trap_t *gta_wasi_callback(
    void *env, wasmtime_caller_t *caller, const wasmtime_val_t *args,
    size_t nargs, wasmtime_val_t *results, size_t nresults
) {
    (void)caller;
    if (nresults != 1 || !results) return NULL;
    const uintptr_t op=(uintptr_t)env;
    int32_t rc=21; /* WASI EFAULT for unavailable guest memory. */
    if (op==GTA_WASI_CLOCK && nargs==3 &&
        args[0].kind==WASMTIME_I32 && args[1].kind==WASMTIME_I64 &&
        args[2].kind==WASMTIME_I64) {
        rc=gta_wasi_clock_time_get((uint32_t)args[0].of.i32,
            (uint64_t)args[1].of.i64, (uint64_t)args[2].of.i64);
    } else if (op==GTA_WASI_ENV_SIZES && nargs==2 &&
        args[0].kind==WASMTIME_I64 && args[1].kind==WASMTIME_I64) {
        rc=gta_wasi_environ_sizes_get((uint64_t)args[0].of.i64,
            (uint64_t)args[1].of.i64);
    } else if (op==GTA_WASI_ENV_GET && nargs==2 &&
        args[0].kind==WASMTIME_I64 && args[1].kind==WASMTIME_I64) {
        rc=gta_wasi_environ_get((uint64_t)args[0].of.i64,
            (uint64_t)args[1].of.i64);
    } else if (op==GTA_WASI_FD_WRITE && nargs==4 &&
        args[0].kind==WASMTIME_I32 && args[1].kind==WASMTIME_I64 &&
        args[2].kind==WASMTIME_I64 && args[3].kind==WASMTIME_I64) {
        rc=gta_wasi_fd_write((uint32_t)args[0].of.i32,
            (uint64_t)args[1].of.i64,(uint64_t)args[2].of.i64,
            (uint64_t)args[3].of.i64);
    } else if (op==GTA_WASI_FD_CLOSE && nargs==1 &&
        args[0].kind==WASMTIME_I32) {
        rc=gta_wasi_fd_close((uint32_t)args[0].of.i32);
    } else if (op==GTA_WASI_FD_READ && nargs==4 &&
        args[0].kind==WASMTIME_I32 && args[1].kind==WASMTIME_I64 &&
        args[2].kind==WASMTIME_I64 && args[3].kind==WASMTIME_I64) {
        rc=gta_wasi_fd_read((uint32_t)args[0].of.i32,
            (uint64_t)args[1].of.i64, (uint64_t)args[2].of.i64,
            (uint64_t)args[3].of.i64);
    } else if (op==GTA_WASI_FD_SEEK && nargs==4 &&
        args[0].kind==WASMTIME_I32 && args[1].kind==WASMTIME_I64 &&
        args[2].kind==WASMTIME_I32 && args[3].kind==WASMTIME_I64) {
        rc=gta_wasi_fd_seek((uint32_t)args[0].of.i32,
            args[1].of.i64, (uint32_t)args[2].of.i32,
            (uint64_t)args[3].of.i64);
    } else if (op==GTA_WASI_FD_PREAD && nargs==5 &&
        args[0].kind==WASMTIME_I32 && args[1].kind==WASMTIME_I64 &&
        args[2].kind==WASMTIME_I64 && args[3].kind==WASMTIME_I64 &&
        args[4].kind==WASMTIME_I64) {
        rc=gta_wasi_fd_pread((uint32_t)args[0].of.i32,
            (uint64_t)args[1].of.i64, (uint64_t)args[2].of.i64,
            (uint64_t)args[3].of.i64, (uint64_t)args[4].of.i64);
    }
    results[0].kind=WASMTIME_I32;
    results[0].of.i32=rc;
    return NULL;
}
static int gta_define_wasi_callback(wasmtime_linker_t *linker,
                                     const char *name, uintptr_t op) {
    const int number=(op==GTA_WASI_FD_PREAD) ? 5 :
                     (op==GTA_WASI_FD_CLOSE) ? 1 :
                     (op==GTA_WASI_FD_WRITE || op==GTA_WASI_FD_READ ||
                      op==GTA_WASI_FD_SEEK) ? 4 :
                     (op==GTA_WASI_CLOCK) ? 3 : 2;
    wasm_valtype_t *params[5]={0};
    for(int i=0;i<number;++i) {
        params[i]=wasm_valtype_new(
            (i==0 && (op==GTA_WASI_CLOCK || op==GTA_WASI_FD_WRITE ||
                      op==GTA_WASI_FD_CLOSE || op==GTA_WASI_FD_READ ||
                      op==GTA_WASI_FD_SEEK || op==GTA_WASI_FD_PREAD)) ||
             (op==GTA_WASI_FD_SEEK && i==2)
            ? WASM_I32 : WASM_I64);
        if (!params[i]) {
            for(int j=0;j<i;++j) wasm_valtype_delete(params[j]);
            return -1;
        }
    }
    wasm_valtype_t *result=wasm_valtype_new(WASM_I32);
    if(!result) {for(int i=0;i<number;++i)wasm_valtype_delete(params[i]);return -2;}
    wasm_valtype_vec_t input, output;
    wasm_valtype_vec_new(&input, number, params);
    wasm_valtype_vec_new(&output, 1, &result);
    wasm_functype_t *type=wasm_functype_new(&input,&output);
    if(!type) return -3;
    const char *module="wasi_snapshot_preview1";
    wasmtime_error_t *error=wasmtime_linker_define_func(
        linker, module, strlen(module), name, strlen(name), type,
        gta_wasi_callback, (void *)op, NULL);
    wasm_functype_delete(type);
    if(error) {wasmtime_error_delete(error);return -4;}
    return 0;
}
static int gta_define_wasi_callbacks(wasmtime_linker_t *linker) {
    if(gta_define_wasi_callback(linker,"clock_time_get",GTA_WASI_CLOCK)) return -1;
    if(gta_define_wasi_callback(linker,"environ_sizes_get",GTA_WASI_ENV_SIZES)) return -2;
    if(gta_define_wasi_callback(linker,"environ_get",GTA_WASI_ENV_GET)) return -3;
    if(gta_define_wasi_callback(linker,"fd_write",GTA_WASI_FD_WRITE)) return -4;
    if(gta_define_wasi_callback(linker,"fd_close",GTA_WASI_FD_CLOSE)) return -5;
    if(gta_define_wasi_callback(linker,"fd_read",GTA_WASI_FD_READ)) return -6;
    if(gta_define_wasi_callback(linker,"fd_seek",GTA_WASI_FD_SEEK)) return -7;
    if(gta_define_wasi_callback(linker,"fd_pread",GTA_WASI_FD_PREAD)) return -8;
    return 0;
}


/* Actual four-argument Emscripten memory64 import from game.js. */
static wasm_trap_t *gta_openat_callback(
    void *env, wasmtime_caller_t *caller, const wasmtime_val_t *args,
    size_t nargs, wasmtime_val_t *results, size_t nresults
) {
    (void)env; (void)caller;
    if (nargs != 4 || nresults != 1 ||
        args[0].kind != WASMTIME_I32 || args[1].kind != WASMTIME_I64 ||
        args[2].kind != WASMTIME_I32 || args[3].kind != WASMTIME_I64)
        return NULL;
    results[0].kind = WASMTIME_I32;
    results[0].of.i32 = gta_wasi_syscall_openat(
        args[0].of.i32, (uint64_t)args[1].of.i64,
        args[2].of.i32, (uint64_t)args[3].of.i64);
    return NULL;
}
static int gta_define_openat_callback(wasmtime_linker_t *linker) {
    wasm_valtype_t *args[4] = {
        wasm_valtype_new(WASM_I32), wasm_valtype_new(WASM_I64),
        wasm_valtype_new(WASM_I32), wasm_valtype_new(WASM_I64)
    };
    for (int i = 0; i < 4; ++i) {
        if (!args[i]) {
            for (int j = 0; j < i; ++j) wasm_valtype_delete(args[j]);
            return -1;
        }
    }
    wasm_valtype_t *result = wasm_valtype_new(WASM_I32);
    if (!result) {
        for (int j = 0; j < 4; ++j) wasm_valtype_delete(args[j]);
        return -2;
    }
    wasm_valtype_vec_t inputs, outputs;
    wasm_valtype_vec_new(&inputs, 4, args);
    wasm_valtype_vec_new(&outputs, 1, &result);
    wasm_functype_t *type = wasm_functype_new(&inputs, &outputs);
    if (!type) return -3;
    const char *name = "__syscall_openat";
    wasmtime_error_t *error = wasmtime_linker_define_func(
        linker, "env", 3, name, strlen(name), type,
        gta_openat_callback, NULL, NULL);
    wasm_functype_delete(type);
    if (error) { wasmtime_error_delete(error); return -4; }
    return 0;
}


enum { GTA_P_FSTAT=1,GTA_P_STAT,GTA_P_LSTAT,GTA_P_GMTIME,GTA_P_LOCALTIME };
static wasm_trap_t *gta_platform_callback(void *env,wasmtime_caller_t *caller,
    const wasmtime_val_t *args,size_t nargs,wasmtime_val_t *results,size_t nresults) {
    (void)caller;
    if(nargs!=2 || nresults!=1 || args[1].kind!=WASMTIME_I64)return NULL;
    int32_t v=0; uintptr_t op=(uintptr_t)env;
    if(op==GTA_P_FSTAT && args[0].kind==WASMTIME_I32)
        v=gta_wasi_syscall_fstat64(args[0].of.i32,(uint64_t)args[1].of.i64);
    else if(args[0].kind==WASMTIME_I64) {
        uint64_t p=(uint64_t)args[0].of.i64,q=(uint64_t)args[1].of.i64;
        switch(op) {
            case GTA_P_STAT:v=gta_wasi_syscall_stat64(p,q);break;
            case GTA_P_LSTAT:v=gta_wasi_syscall_lstat64(p,q);break;
            case GTA_P_GMTIME:v=gta_wasi_gmtime_js((int64_t)p,q);break;
            case GTA_P_LOCALTIME:v=gta_wasi_localtime_js((int64_t)p,q);break;
            default:return NULL;
        }
    } else return NULL;
    results[0].kind=WASMTIME_I32;results[0].of.i32=v;
    return NULL;
}
static int gta_define_platform_callbacks(wasmtime_linker_t *linker) {
    const struct {const char *name;uintptr_t op;wasm_valkind_t first;} ops[]={
        {"__syscall_fstat64",GTA_P_FSTAT,WASM_I32},
        {"__syscall_stat64",GTA_P_STAT,WASM_I64},
        {"__syscall_lstat64",GTA_P_LSTAT,WASM_I64},
        {"_gmtime_js",GTA_P_GMTIME,WASM_I64},
        {"_localtime_js",GTA_P_LOCALTIME,WASM_I64}
    };
    for(size_t i=0;i<sizeof(ops)/sizeof(ops[0]);++i) {
        wasm_valtype_t *a=wasm_valtype_new(ops[i].first);
        wasm_valtype_t *b=wasm_valtype_new(WASM_I64);
        wasm_valtype_t *r=wasm_valtype_new(WASM_I32);
        if(!a||!b||!r){
            if(a)wasm_valtype_delete(a);
            if(b)wasm_valtype_delete(b);
            if(r)wasm_valtype_delete(r);
            return -1;
        }
        wasm_functype_t *type=wasm_functype_new_2_1(a,b,r);
        if(!type)return -2;
        wasmtime_error_t *err=wasmtime_linker_define_func(linker,"env",3,
            ops[i].name,strlen(ops[i].name),type,gta_platform_callback,
            (void *)ops[i].op,NULL);
        wasm_functype_delete(type);
        if(err){wasmtime_error_delete(err);return -3;}
    }
    return 0;
}


/* Three actual imports from the original game.js:
 * env.__syscall_getcwd(i64,i64)->i32
 * env._emscripten_system(i64)->i32
 * env.__syscall_fcntl64(i32,i32,i64)->i32
 * Do not register placeholder/default callbacks for unsupported imports.
 */
enum { GTA_MORE_CWD=1,GTA_MORE_SYSTEM=2,GTA_MORE_FCNTL=3 };
static wasm_trap_t *gta_more_callback(void *env,wasmtime_caller_t *caller,
    const wasmtime_val_t *args,size_t nargs,
    wasmtime_val_t *out,size_t nout) {
    (void)caller;
    uintptr_t op=(uintptr_t)env;
    if(nout!=1)return NULL;
    int32_t rc;
    if(op==GTA_MORE_CWD && nargs==2 && args[0].kind==WASMTIME_I64 &&
       args[1].kind==WASMTIME_I64)
        rc=gta_wasi_syscall_getcwd((uint64_t)args[0].of.i64,
                                   (uint64_t)args[1].of.i64);
    else if(op==GTA_MORE_SYSTEM && nargs==1 && args[0].kind==WASMTIME_I64)
        rc=gta_wasi_emscripten_system((uint64_t)args[0].of.i64);
    else if(op==GTA_MORE_FCNTL && nargs==3 &&
            args[0].kind==WASMTIME_I32 && args[1].kind==WASMTIME_I32 &&
            args[2].kind==WASMTIME_I64)
        rc=gta_wasi_syscall_fcntl64(args[0].of.i32,args[1].of.i32,
                                     (uint64_t)args[2].of.i64);
    else return NULL;
    out[0].kind=WASMTIME_I32;
    out[0].of.i32=rc;
    return NULL;
}
static int gta_define_more_callbacks(wasmtime_linker_t *linker) {
    const struct {
        const char *name; uintptr_t op; wasm_valkind_t kinds[3];size_t count;
    } funcs[]={
        {"__syscall_getcwd",GTA_MORE_CWD,{WASM_I64,WASM_I64},2},
        {"_emscripten_system",GTA_MORE_SYSTEM,{WASM_I64},1},
        {"__syscall_fcntl64",GTA_MORE_FCNTL,{WASM_I32,WASM_I32,WASM_I64},3}
    };
    for(size_t i=0;i<sizeof(funcs)/sizeof(funcs[0]);i++){
        wasm_valtype_t *args[3]={0};
        for(size_t j=0;j<funcs[i].count;j++){
            args[j]=wasm_valtype_new(funcs[i].kinds[j]);
            if(!args[j]){
                for(size_t k=0;k<j;k++)wasm_valtype_delete(args[k]);
                return -1;
            }
        }
        wasm_valtype_t *retval=wasm_valtype_new(WASM_I32);
        if(!retval){
            for(size_t j=0;j<funcs[i].count;j++)wasm_valtype_delete(args[j]);
            return -2;
        }
        wasm_valtype_vec_t inputs, outputs;
        wasm_valtype_vec_new(&inputs,funcs[i].count,args);
        wasm_valtype_vec_new(&outputs,1,&retval);
        wasm_functype_t *type=wasm_functype_new(&inputs,&outputs);
        if(!type)return -3;
        wasmtime_error_t *error=wasmtime_linker_define_func(
            linker,"env",3,funcs[i].name,strlen(funcs[i].name),
            type,gta_more_callback,(void *)funcs[i].op,NULL);
        wasm_functype_delete(type);
        if(error){wasmtime_error_delete(error);return -4;}
    }
    return 0;
}


/* The source engine's real env.wasm_audio_publish_js(i64,i32)->void
 * publishes its shared stereo PCM ring. Audio remains silent unless a
 * live Wasmtime guest allocation is actually bound to the audio ABI. */
static wasm_trap_t *gta_native_audio_callback(void *env,wasmtime_caller_t *caller,
    const wasmtime_val_t *args,size_t count,
    wasmtime_val_t *results,size_t out_count) {
    (void)env;(void)caller;(void)results;
    if(count==2 && out_count==0 && args[0].kind==WASMTIME_I64 &&
       args[1].kind==WASMTIME_I32){
        (void)gta_game_audio_publish((uint64_t)args[0].of.i64,args[1].of.i32);
    }
    return NULL;
}
static int gta_define_game_audio(wasmtime_linker_t *linker) {
    wasm_valtype_t *ptr=wasm_valtype_new(WASM_I64);
    wasm_valtype_t *size=wasm_valtype_new(WASM_I32);
    if(!ptr || !size){
        if(ptr)wasm_valtype_delete(ptr);
        if(size)wasm_valtype_delete(size);
        return -1;
    }
    wasm_functype_t *type=wasm_functype_new_2_0(ptr,size);
    if(!type)return -2;
    const char *name="wasm_audio_publish_js";
    wasmtime_error_t *error=wasmtime_linker_define_func(
        linker,"env",3,name,strlen(name),type,
        gta_native_audio_callback,NULL,NULL);
    wasm_functype_delete(type);
    if(error){wasmtime_error_delete(error);return -3;}
    return 0;
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
    wasm_valkind_t result_type =
        kind == WASMTIME_I32 ? WASM_I32 :
        kind == WASMTIME_I64 ? WASM_I64 : WASM_F64;
    wasm_valtype_t *output = wasm_valtype_new(result_type);
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

static int gta_define_void(wasmtime_linker_t *linker, const char *name,
                           uintptr_t op, char *message, size_t capacity) {
    wasm_functype_t *type = wasm_functype_new_0_0();
    if (!type) {
        gta_host_message(message, capacity, "Could not allocate void Wasm function type");
        return -1;
    }
    wasmtime_error_t *error = wasmtime_linker_define_func(
        linker, "env", 3, name, strlen(name), type, gta_basic_callback,
        (void *)op, NULL);
    wasm_functype_delete(type);
    if (error) {
        wasmtime_error_delete(error);
        gta_host_message(message, capacity, "Native void host registration failed");
        return -3;
    }
    return 0;
}

// Shared import-registration path used by both callback tests and real AOT
// module coverage. All registrations use verified signatures from game.wasm.
int gta_ios_wasmtime_register_host_basics(
    wasmtime_linker_t *linker, unsigned int *installed,
    char *message, size_t capacity
) {
    if (installed) *installed = 0;
    const struct { const char *name; uint8_t kind; uintptr_t op; } functions[] = {
        { "wasm_now_ms", WASMTIME_F64, GTA_MONOTONIC_MS },
        { "emscripten_get_now", WASMTIME_F64, GTA_EMSCRIPTEN_NOW },
        { "emscripten_date_now", WASMTIME_F64, GTA_WALLCLOCK_MS },
        { "emscripten_num_logical_cores", WASMTIME_I32, GTA_CPU_COUNT },
        { "emscripten_get_heap_max", WASMTIME_I64, GTA_HEAP_MAX },
        { "wasm_has_page_js", WASMTIME_I32, GTA_HAS_BROWSER_PAGE },
        { "wasm_userdata_page_js", WASMTIME_I32, GTA_HAS_USERDATA_WORKER },
    };
    for (size_t i = 0; i < sizeof(functions) / sizeof(functions[0]); i++) {
        int rc = gta_define(linker, functions[i].name, functions[i].kind,
                            functions[i].op, message, capacity);
        if (rc != 0) return rc;
        if (installed) ++*installed;
    }
    int rc = gta_define_void(linker, "emscripten_check_blocking_allowed",
                             GTA_BLOCKING_ALLOWED_CHECK, message, capacity);
    if (rc != 0) return rc;
    if (installed) ++*installed;
    rc = gta_define_input_callback(linker);
    if (rc != 0) {
        gta_host_message(message, capacity, "Native WASM shared-memory input callback registration failed");
        return rc;
    }
    if (installed) ++*installed;
    rc = gta_define_manifest_callback(linker);
    if (rc != 0) {
        gta_host_message(message, capacity, "Native HTTPFS manifest callback registration failed");
        return rc;
    }
    if (installed) ++*installed;
    rc = gta_define_text_callbacks(linker);
    if (rc != 0) {
        gta_host_message(message, capacity, "Native GTA engine text/config callback registration failed");
        return rc;
    }
    if (installed) *installed += 3;
    rc = gta_define_userdata_callbacks(linker);
    if (rc != 0) {
        gta_host_message(message, capacity, "Native GTA userdata put/delete callback registration failed");
        return rc;
    }
    if (installed) *installed += 2;
    rc = gta_define_wasi_callbacks(linker);
    if (rc != 0) {
        gta_host_message(message, capacity, "Actual memory64 WASI clock/environment registration failed");
        return rc;
    }
    if (installed) *installed += 8;
    rc = gta_define_openat_callback(linker);
    if (rc != 0) {
        gta_host_message(message, capacity, "Game archive __syscall_openat callback registration failed");
        return rc;
    }
    if (installed) ++*installed;
    rc=gta_define_platform_callbacks(linker);
    if(rc!=0){
        gta_host_message(message,capacity,"POSIX stat64/calendar import registration failed");
        return rc;
    }
    if(installed)*installed+=5;
    rc=gta_define_more_callbacks(linker);
    if(rc!=0){
        gta_host_message(message,capacity,"Native Emscripten fcntl/getcwd/system import registration failed");
        return rc;
    }
    if(installed)*installed+=3;
    rc=gta_define_game_audio(linker);
    if(rc!=0){
        gta_host_message(message,capacity,"Native game audio PCM publish import registration failed");
        return rc;
    }
    if(installed)++*installed;
    return 0;
}

/* Returns 0 only when 33 ABI-matched host functions are registered
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

    int result = gta_ios_wasmtime_register_host_basics(linker, installed, message, capacity);
    if (result != 0) goto finish;

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
                "Native GTA host callbacks registered; monotonic function invoked correctly");
        }
        if (error) wasmtime_error_delete(error);
        if (trap) wasm_trap_delete(trap);
    }
    if (exported.kind == WASMTIME_EXTERN_FUNC) wasmtime_extern_delete(&exported);
    // Exercise the *real* i64 heap limit import as well, using the exact
    // maximum encoded by the supplied 63 MiB engine. The host must never
    // mistake this logical memory maximum for available physical RAM.
    if (result == 0) {
        wasmtime_extern_t heap = {0};
        const char *name = "emscripten_get_heap_max";
        if (!wasmtime_linker_get(linker, context, "env", 3, name, strlen(name), &heap)
                || heap.kind != WASMTIME_EXTERN_FUNC) {
            result = -23;
            gta_host_message(message, capacity, "Heap limit linker lookup failed");
        } else {
            wasmtime_val_t answer = {0};
            wasm_trap_t *trap = NULL;
            wasmtime_error_t *error = wasmtime_func_call(
                context, &heap.of.func, NULL, 0, &answer, 1, &trap);
            if (error || trap || answer.kind != WASMTIME_I64
                    || answer.of.i64 != INT64_C(17179869184)) {
                result = -24;
                gta_host_message(message, capacity, "WASM memory64 logical maximum host callback failed");
            } else {
                gta_host_message(message, capacity,
                    "Native GTA imports registered; monotonic clock and i64 heap maximum callbacks executed");
            }
            if (error) wasmtime_error_delete(error);
            if (trap) wasm_trap_delete(trap);
        }
        if (heap.kind == WASMTIME_EXTERN_FUNC) wasmtime_extern_delete(&heap);
    }
    if (result == 0) {
        /* Exercise the exact engine-published input-block callback; no 3GiB
         * memory allocated and no unsupported GTA function is invoked. */
        wasmtime_extern_t input_export = {0};
        const char *name = "wasm_input_publish_js";
        if (!wasmtime_linker_get(linker, context, "env", 3,
                name, strlen(name), &input_export)
                || input_export.kind != WASMTIME_EXTERN_FUNC) {
            result = -25;
            gta_host_message(message, capacity,
                             "Native game input linker resolution failed");
        } else {
            wasmtime_val_t address = {0};
            address.kind = WASMTIME_I64;
            address.of.i64 = 256;
            wasm_trap_t *trap = NULL;
            wasmtime_error_t *error = wasmtime_func_call(context,
                &input_export.of.func, &address, 1, NULL, 0, &trap);
            if (error || trap || gta_native_input_block_offset() != 256) {
                result = -26;
                gta_host_message(message, capacity,
                    "Actual WASM input block publish callback failed");
            } else {
                gta_host_message(message, capacity,
                    "Native GTA host imports; real i64 input block callback invoked; game still not instantiated");
            }
            if (error) wasmtime_error_delete(error);
            if (trap) wasm_trap_delete(trap);
            gta_native_input_unbind();
        }
        if (input_export.kind == WASMTIME_EXTERN_FUNC)
            wasmtime_extern_delete(&input_export);
    }
    /* Invoke the actual 64-bit-pointer + i32 fallback import through
     * Wasmtime, not through a direct C-only test. Without bound game memory,
     * the browser-equivalent behavior is to return the supplied fallback.
     */
    if (result == 0) {
        wasmtime_extern_t setting = {0};
        const char *name = "wasm_module_int_js";
        if (!wasmtime_linker_get(linker, context, "env", 3, name,
                                 strlen(name), &setting) ||
            setting.kind != WASMTIME_EXTERN_FUNC) {
            result = -27;
            gta_host_message(message, capacity, "Native engine configuration callback lookup failed");
        } else {
            wasmtime_val_t args[2] = {0};
            args[0].kind = WASMTIME_I64;
            args[0].of.i64 = 0;
            args[1].kind = WASMTIME_I32;
            args[1].of.i32 = 742;
            wasmtime_val_t answer = {0};
            wasm_trap_t *trap = NULL;
            wasmtime_error_t *error = wasmtime_func_call(
                context, &setting.of.func, args, 2, &answer, 1, &trap);
            if (error || trap || answer.kind != WASMTIME_I32 || answer.of.i32 != 742) {
                result = -28;
                gta_host_message(message, capacity, "GTA module-int native fallback smoke failed");
            } else {
                gta_host_message(message, capacity,
                    "Native GTA ABI imports linked, module-int fallback and input-block callbacks executed; game not instantiated");
            }
            if (error) wasmtime_error_delete(error);
            if (trap) wasm_trap_delete(trap);
        }
        if (setting.kind == WASMTIME_EXTERN_FUNC)
            wasmtime_extern_delete(&setting);
    }
    /* Call an actual newly registered WASI memory64 function through the
     * Wasmtime C API. Because the real GTA heap is intentionally unbound,
     * the correct result is WASI EFAULT (21), not a fake success value.
     */
    if (result == 0) {
        const char *module="wasi_snapshot_preview1";
        const char *name="clock_time_get";
        wasmtime_extern_t clock_func={0};
        if (!wasmtime_linker_get(linker, context, module, strlen(module),
                                 name, strlen(name), &clock_func) ||
                clock_func.kind != WASMTIME_EXTERN_FUNC) {
            result=-29;
            gta_host_message(message, capacity, "WASI clock_time_get linker lookup failed");
        } else {
            wasmtime_val_t args[3]={0}, answer={0};
            args[0].kind=WASMTIME_I32; args[0].of.i32=1; /* monotonic */
            args[1].kind=WASMTIME_I64; args[1].of.i64=1;
            args[2].kind=WASMTIME_I64; args[2].of.i64=0;
            wasm_trap_t *trap=NULL;
            wasmtime_error_t *error=wasmtime_func_call(context,
                &clock_func.of.func, args, 3, &answer, 1, &trap);
            if(error || trap || answer.kind!=WASMTIME_I32 || answer.of.i32!=21) {
                result=-30;
                gta_host_message(message, capacity,
                    "WASI clock memory64 callback did not return EFAULT for unbound heap");
            } else {
                gta_host_message(message, capacity,
                    "24 real GTA host functions linked; WASI clock callback correctly returns EFAULT before memory bind. No game instantiation.");
            }
            if(error) wasmtime_error_delete(error);
            if(trap) wasm_trap_delete(trap);
        }
        if(clock_func.kind==WASMTIME_EXTERN_FUNC)
            wasmtime_extern_delete(&clock_func);
    }
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
