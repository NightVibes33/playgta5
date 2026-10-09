#include "../Sources/Input/NativeGameInputABI.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
/* Deterministic native host memory test, no proprietary WASM code used.
 * Confirms the actual 444-byte homepage WasmInputBlock layout. */
static int32_t word(const uint8_t *p, int idx) {
    int32_t v;
    memcpy(&v,p+256+idx*4,4);
    return v;
}
int main(void) {
    _Alignas(16) uint8_t memory[1024];
    memset(memory,0,sizeof(memory));
    gta_native_input_unbind();
    gta_native_pad_frame_t f={0};
    f.active=1; f.ly=0.8f; f.rx=0.5f; f.ry=-0.5f;
    f.rt=0.9f; f.lt=0.7f; f.buttons=GTA_PAD_A|GTA_PAD_Y;
    f.width=960; f.height=540;
    assert(gta_native_input_apply(&f)==1);
    gta_native_input_bind_memory(memory,sizeof(memory));
    assert(gta_native_input_apply(&f)==1); // block was not yet published
    gta_native_input_publish_block(128);
    assert(gta_native_input_apply(&f)==0);
    const uint8_t *p=memory+128;
    assert(p[0x57]==0x80); // W, movement
    assert(p[0xa0]==0x80); // shift/jump
    assert(p[0x46]==0x80); // F/enter vehicle
    assert(word(p,5)==3); // fire+aim mouse flags
    assert(word(p,2)==8); // right stick camera dx
    assert(word(p,3)==8); // Y inverted camera dy
    assert(word(p,6)==1 && word(p,7)==1);
    assert(word(p,0)==480 && word(p,1)==270);
    int32_t extw,exth;
    memcpy(&extw,p+424+8,4);
    memcpy(&exth,p+424+12,4);
    assert(extw==960 && exth==540);
    f.active=0;
    assert(gta_native_input_apply(&f)==0);
    assert(p[0x57]==0 && p[0xa0]==0 && word(p,5)==0);
    f.active=1; f.profile=1; f.ly=0; f.rt=0.8f;
    assert(gta_native_input_apply(&f)==0);
    assert(p[0x57]==0x80 && word(p,5)==0); // drive acceleration, no fire
    gta_native_input_publish_block(1020);
    assert(gta_native_input_apply(&f)==-2); // no buffer overread
    gta_native_input_unbind();
    assert(gta_native_input_apply(&f)==1);
    puts("PASS: original WASM input block layout, controller→game keys, camera, driving, bounds and disconnect");
    return 0;
}
