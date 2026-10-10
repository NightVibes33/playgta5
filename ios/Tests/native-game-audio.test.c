#include "../Sources/Engine/NativeGameAudioABI.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

int main(void){
    _Alignas(4) unsigned char memory[512]={0};
    float frames[24]={0};
    gta_game_audio_unbind();
    assert(gta_game_audio_publish(128,8)<0);
    assert(gta_game_audio_drain(frames,12)==0);
    gta_game_audio_bind(memory,sizeof memory);
    assert(gta_game_audio_publish(UINT64_MAX,8)<0);
    assert(gta_game_audio_publish(128,7)<0);
    assert(gta_game_audio_publish(129,8)<0);
    uint32_t *hdr=(uint32_t *)(void *)(memory+128);
    float *samples=(float *)(void *)(memory+128+64);
    hdr[2]=8;
    for(int i=0;i<8;i++){
        samples[i*2]=(float)i+0.25f;
        samples[i*2+1]=(float)i+0.75f;
    }
    assert(gta_game_audio_publish(128,8)==0);
    hdr[0]=5;
    assert(gta_game_audio_drain(frames,3)==3);
    assert(frames[0]==0.25f && frames[1]==0.75f);
    assert(frames[4]==2.25f && frames[5]==2.75f);
    assert(hdr[1]==3 && hdr[3]==1);
    assert(gta_game_audio_drain(frames,12)==2);
    assert(frames[0]==3.25f && frames[2]==4.25f);
    assert(hdr[1]==5);
    assert(gta_game_audio_drain(frames,12)==0);
    hdr[0]=20;hdr[1]=5;
    assert(gta_game_audio_drain(frames,8)==8);
    assert(hdr[1]==20 && hdr[3]==3);
    gta_game_audio_unbind();
    assert(gta_game_audio_drain(frames,8)==0);
    puts("PASS: engine WebAudio PCM ring layout, wrapping, memory bounds, underrun");
    return 0;
}
