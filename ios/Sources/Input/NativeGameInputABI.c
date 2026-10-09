#include "NativeGameInputABI.h"
#include <pthread.h>
#include <math.h>
#include <string.h>
#include <limits.h>

enum { VK_SPACE=0x20, VK_TAB=0x09, VK_ESC=0x1b, VK_ENTER=0x0d,
       VK_W=0x57, VK_A=0x41, VK_S=0x53, VK_D=0x44, VK_F=0x46,
       VK_R=0x52, VK_Q=0x51, VK_M=0x4d, VK_C=0x43,
       VK_SHIFT=0xa0, VK_CONTROL=0xa2, VK_UP=0x26, VK_DOWN=0x28,
       VK_LEFT=0x25, VK_RIGHT=0x27, VK_NPAD2=0x62, VK_NPAD4=0x64,
       VK_NPAD6=0x66, VK_NPAD8=0x68 };
enum { WORD_MOUSE_X, WORD_MOUSE_Y, WORD_DX, WORD_DY, WORD_DZ,
       WORD_BUTTONS, WORD_FOCUS, WORD_LOCKED, WORD_HEAD, WORD_TAIL };

static pthread_mutex_t input_lock = PTHREAD_MUTEX_INITIALIZER;
static uint8_t *memory_data;
static uint64_t memory_capacity;
static uint64_t input_offset = UINT64_MAX;

static float limit_axis(float value) {
  if (!isfinite(value)) return 0;
  return fmaxf(-1.0f, fminf(1.0f, value));
}
static void key(uint8_t *base, unsigned vk, int down) {
  __atomic_store_n(base+vk, down ? 0x80 : 0, __ATOMIC_SEQ_CST);
}
static void word(uint8_t *base, unsigned index, int32_t value) {
  int32_t *addr = (int32_t *)(void *)(base+256+index*4);
  __atomic_store_n(addr,value,__ATOMIC_SEQ_CST);
}
static void delta(uint8_t *base, unsigned index, int32_t value) {
  int32_t *addr = (int32_t *)(void *)(base+256+index*4);
  if (value) __atomic_fetch_add(addr,value,__ATOMIC_SEQ_CST);
}
void gta_native_input_bind_memory(void *data, uint64_t size) {
  pthread_mutex_lock(&input_lock);
  memory_data = (uint8_t *)data;
  memory_capacity = data ? size : 0;
  pthread_mutex_unlock(&input_lock);
}
void gta_native_input_publish_block(uint64_t offset) {
  pthread_mutex_lock(&input_lock);
  input_offset = offset;
  pthread_mutex_unlock(&input_lock);
}
uint64_t gta_native_input_block_offset(void) {
  pthread_mutex_lock(&input_lock);
  uint64_t result = input_offset;
  pthread_mutex_unlock(&input_lock);
  return result;
}
void gta_native_input_unbind(void) {
  pthread_mutex_lock(&input_lock);
  memory_data = NULL;
  memory_capacity = 0;
  input_offset = UINT64_MAX;
  pthread_mutex_unlock(&input_lock);
}
int gta_native_input_apply(const gta_native_pad_frame_t *f) {
  if (!f) return -1;
  pthread_mutex_lock(&input_lock);
  if (!memory_data || input_offset == UINT64_MAX) {
    pthread_mutex_unlock(&input_lock);
    return 1;
  }
  if (input_offset % 4 != 0 || input_offset > memory_capacity
      || memory_capacity-input_offset < GTA_WASM_INPUT_BLOCK_BYTES) {
    pthread_mutex_unlock(&input_lock);
    return -2;
  }
  uint8_t *base = memory_data + input_offset;
  const float lx=limit_axis(f->lx),ly=limit_axis(f->ly);
  const float rx=limit_axis(f->rx),ry=limit_axis(f->ry);
  const float lt=limit_axis(f->lt),rt=limit_axis(f->rt);
  const uint32_t b=f->buttons;
  const int active=f->active != 0;
  const int in_menu=(b & GTA_PAD_MENU)!=0;
  const int drive=f->profile==1, air=f->profile==2;
  const int forwards=(ly>0.19f || ((drive||air)&&rt>0.15f));
  const int backwards=(ly< -0.19f || ((drive||air)&&lt>0.15f));
  if (!active) {
    static const uint8_t controlled_keys[]={
      VK_W,VK_A,VK_S,VK_D,VK_SHIFT,VK_SPACE,VK_F,VK_R,VK_Q,
      VK_TAB,VK_CONTROL,VK_C,VK_M,VK_ESC,VK_ENTER,
      VK_UP,VK_DOWN,VK_LEFT,VK_RIGHT,VK_NPAD2,VK_NPAD4,VK_NPAD6,VK_NPAD8
    };
    for (size_t i=0;i<sizeof(controlled_keys);++i) key(base,controlled_keys[i],0);
    word(base, WORD_BUTTONS, 0);
    word(base, WORD_LOCKED, 0);
    pthread_mutex_unlock(&input_lock);
    return 0;
  }
  key(base,VK_W,!in_menu && forwards);
  key(base,VK_S,!in_menu && backwards);
  key(base,VK_A,!in_menu && lx< -0.19f);
  key(base,VK_D,!in_menu && lx>0.19f);
  key(base,VK_SHIFT,!in_menu && !drive && !air && (b&GTA_PAD_A));
  key(base,VK_SPACE,!in_menu && ((b&GTA_PAD_X) || (drive && (b&GTA_PAD_RB))));
  key(base,VK_F,!in_menu && (b&GTA_PAD_Y));
  key(base,VK_R,!in_menu && !drive && !air && (b&GTA_PAD_B));
  key(base,VK_Q,!in_menu && !drive && !air && (b&GTA_PAD_RB));
  key(base,VK_TAB,!in_menu && (b&GTA_PAD_LB));
  key(base,VK_CONTROL,!in_menu && (b&GTA_PAD_L3));
  key(base,VK_C,!in_menu && (b&GTA_PAD_R3));
  key(base,VK_M,!in_menu && (b&GTA_PAD_OPTIONS));
  key(base,VK_ESC,(b&GTA_PAD_MENU) || (in_menu && (b&GTA_PAD_B)));
  key(base,VK_ENTER,in_menu && (b&GTA_PAD_A));
  key(base,VK_UP,(b&GTA_PAD_UP)||(in_menu&&ly>0.5f));
  key(base,VK_DOWN,(b&GTA_PAD_DOWN)||(in_menu&&ly< -0.5f));
  key(base,VK_LEFT,(b&GTA_PAD_LEFT)||(in_menu&&lx< -0.5f));
  key(base,VK_RIGHT,(b&GTA_PAD_RIGHT)||(in_menu&&lx>0.5f));
  key(base,VK_NPAD8,air && ry>0.19f);
  key(base,VK_NPAD2,air && ry< -0.19f);
  key(base,VK_NPAD4,air && rx< -0.19f);
  key(base,VK_NPAD6,air && rx>0.19f);

  int mouse = (!in_menu && !drive && !air) ? (rt>0.15f ? 1 : 0)|(lt>0.15f ? 2 : 0) : 0;
  word(base,WORD_BUTTONS,mouse);
  word(base,WORD_FOCUS,1);
  word(base,WORD_LOCKED,1);
  if (!in_menu && !air) {
    delta(base,WORD_DX,(int32_t)lrintf(rx*15.0f));
    delta(base,WORD_DY,(int32_t)lrintf(-ry*15.0f));
  }
  if (f->width > 0 && f->height > 0 && f->width < INT32_MAX && f->height < INT32_MAX) {
    word(base,WORD_MOUSE_X,(int32_t)(f->width/2));
    word(base,WORD_MOUSE_Y,(int32_t)(f->height/2));
    /* Original ext[2], ext[3] = backbuffer viewport dimensions */
    int32_t *w=(int32_t *)(void *)(base+424);
    __atomic_store_n(w+2,(int32_t)f->width,__ATOMIC_SEQ_CST);
    __atomic_store_n(w+3,(int32_t)f->height,__ATOMIC_SEQ_CST);
  }
  pthread_mutex_unlock(&input_lock);
  return 0;
}
