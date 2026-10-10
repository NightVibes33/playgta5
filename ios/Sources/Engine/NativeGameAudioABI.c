#include "NativeGameAudioABI.h"
#include <pthread.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>

/* The original browser audio-worklet.js uses:
 * header int32[0]=write,[1]=read,[2]=capacity,[3]=heartbeat
 * stereo float32 samples at (ring+64), power-of-two ring capacity.
 * Host does not allocate or invent GTA PCM: ownership stays with the guest. */
static pthread_mutex_t ring_lock=PTHREAD_MUTEX_INITIALIZER;
static unsigned char *guest_base;
static uint64_t guest_size;
static uint64_t active_offset;
static uint32_t active_capacity;
static int active;

void gta_game_audio_bind(void *base,uint64_t length) {
    pthread_mutex_lock(&ring_lock);
    guest_base=(unsigned char *)base;
    guest_size=base?length:0;
    active=0;active_offset=0;active_capacity=0;
    pthread_mutex_unlock(&ring_lock);
}
void gta_game_audio_unbind(void) { gta_game_audio_bind(NULL,0); }

int32_t gta_game_audio_publish(uint64_t ring,int32_t capacity) {
    pthread_mutex_lock(&ring_lock);
    active=0;active_capacity=0;active_offset=0;
    int32_t rc=-1;
    if(!guest_base || capacity<2 || capacity>(1<<20) ||
       (capacity&(capacity-1))!=0 || (ring&3)!=0)goto done;
    uint64_t needed=64+(uint64_t)capacity*2*sizeof(float);
    if(ring>guest_size || needed>guest_size-ring ||
       ring>(uint64_t)SIZE_MAX || needed>(uint64_t)SIZE_MAX-(size_t)ring) {
        rc=-2;goto done;
    }
    active_offset=ring;
    active_capacity=(uint32_t)capacity;
    active=1;
    rc=0;
done:
    pthread_mutex_unlock(&ring_lock);
    return rc;
}

uint32_t gta_game_audio_drain(float *output,uint32_t frames) {
    if(!output || frames==0)return 0;
    pthread_mutex_lock(&ring_lock);
    if(!active || !guest_base) {
        pthread_mutex_unlock(&ring_lock);
        return 0;
    }
    uint32_t *h=(uint32_t *)(void *)(guest_base+(size_t)active_offset);
    uint32_t w=__atomic_load_n(&h[0],__ATOMIC_ACQUIRE);
    uint32_t r=__atomic_load_n(&h[1],__ATOMIC_RELAXED);
    uint32_t available=w-r; /* uint32 sequence wraps naturally */
    const uint32_t cap=active_capacity;
    if(available>cap) {
        r=w-cap; /* overwritten frames cannot be played */
        available=cap;
    }
    uint32_t count=available<frames?available:frames;
    const unsigned char *samples=guest_base+(size_t)active_offset+64;
    for(uint32_t i=0;i<count;i++){
        size_t at=(size_t)((r+i)&(cap-1))*2*sizeof(float);
        memcpy(output+(size_t)i*2,samples+at,2*sizeof(float));
    }
    if(count){
        __atomic_store_n(&h[1],r+count,__ATOMIC_RELEASE);
        __atomic_add_fetch(&h[3],1,__ATOMIC_RELAXED);
    }
    pthread_mutex_unlock(&ring_lock);
    return count;
}
