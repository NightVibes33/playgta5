#ifndef GTA_NATIVE_GAME_INPUT_ABI_H
#define GTA_NATIVE_GAME_INPUT_ABI_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Verified from the original homepage installInput + game.wasm:
 * env.wasm_input_publish_js : (i64) -> void
 * WasmInputBlock = 256 VK bytes + 10 int32 mouse/focus/text counters +
 * 64 uint16 text entries + 4 int32 debug/viewport + startMode at byte 440.
 * This is keyboard/mouse input, not a true analog gamepad interface. */
typedef struct gta_native_pad_frame {
  float lx, ly, rx, ry, lt, rt;
  uint32_t buttons;   /* ABXY, LB/RB, L3/R3, dpad, menu/options */
  uint32_t profile;   /* 0=on foot; 1=driving; 2=air */
  uint32_t active;    /* Hardware connected OR active touch input */
  uint32_t width, height;
} gta_native_pad_frame_t;
enum {
  GTA_PAD_A=1u<<0, GTA_PAD_B=1u<<1, GTA_PAD_X=1u<<2,
  GTA_PAD_Y=1u<<3, GTA_PAD_LB=1u<<4, GTA_PAD_RB=1u<<5,
  GTA_PAD_L3=1u<<6, GTA_PAD_R3=1u<<7,
  GTA_PAD_UP=1u<<8, GTA_PAD_DOWN=1u<<9, GTA_PAD_LEFT=1u<<10,
  GTA_PAD_RIGHT=1u<<11, GTA_PAD_MENU=1u<<12, GTA_PAD_OPTIONS=1u<<13
};
#define GTA_WASM_INPUT_BLOCK_BYTES 444
/* Used by native memory64 host after allocating the *real* shared memory.
 * Always clear this binding BEFORE deallocating/moving the Wasmtime memory.
 * Caller must serialize rebinding with all guest accesses. */
void gta_native_input_bind_memory(void *data, uint64_t capacity);
void gta_native_input_publish_block(uint64_t wasm_i64_offset);
void gta_native_input_unbind(void);
/* Result: 0 applied, 1 staged (no guest memory), negative invalid input.
 * Applied keys are 0x80 while pressed, else zero. Focus/lock published only
 * when active; no synthetic DOM KeyboardEvents are created. */
int gta_native_input_apply(const gta_native_pad_frame_t *input);
uint64_t gta_native_input_block_offset(void);
#ifdef __cplusplus
}
#endif
#endif
