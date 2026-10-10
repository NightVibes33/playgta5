#ifndef GTA_NATIVE_GAME_AUDIO_ABI_H
#define GTA_NATIVE_GAME_AUDIO_ABI_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Original game.js wasm_audio_publish_js(i64 ring, i32 capacity) -> void.
 * Memory mapping is owned by the live Wasmtime guest. Unbind BEFORE release
 * or replacement and bind the new mapping after successful engine startup. */
void gta_game_audio_bind(void *guest_base, uint64_t guest_bytes);
void gta_game_audio_unbind(void);
int32_t gta_game_audio_publish(uint64_t ring, int32_t capacity);
/* Copy actual interleaved stereo float32 PCM only. No guest -> 0 frames. */
uint32_t gta_game_audio_drain(float *interleaved, uint32_t max_frames);
#ifdef __cplusplus
}
#endif
#endif
