#ifndef GTA_IOS_NATIVE_WASMTIME_HOST_H
#define GTA_IOS_NATIVE_WASMTIME_HOST_H
#ifdef __cplusplus
extern "C" {
#endif
/* 0 when real Wasmtime runtime can initialize. -100 on simulator; -1 error.
   This does not instantiate the GTA game engine. */
int gta_ios_wasmtime_engine_probe(void);
#ifdef __cplusplus
}
#endif
#endif
