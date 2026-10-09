#define _POSIX_C_SOURCE 200809L
#include "gta-native-atomics.h"
#include <pthread.h>
#include <time.h>
#include <errno.h>
#include <stdint.h>
#include <stdbool.h>

/* Portable wait queues keyed by shared memory instance and effective address.
   Each waiter has a private condvar. Notify wakes at most count matching
   waiters. iOS-compatible pthread synchronization; not a no-op. */
typedef struct gta_waiter {
  struct gta_waiter *next;
  wasm_rt_shared_memory_t *memory;
  uint64_t address;
  pthread_cond_t cond;
  bool signalled;
} gta_waiter;
static pthread_mutex_t gta_wait_lock = PTHREAD_MUTEX_INITIALIZER;
static gta_waiter *gta_waiters;

static void gta_check_address(wasm_rt_shared_memory_t *m, uint64_t addr,
                              uint64_t width, bool *misaligned, bool *outside) {
  *misaligned = (addr & (width - 1)) != 0;
  *outside = m == NULL || addr > m->size || m->size - addr < width;
}

static uint32_t gta_wait(wasm_rt_shared_memory_t *m, uint64_t addr,
                         uint64_t expected, int64_t timeout_ns, uint64_t width) {
  if (!m) wasm_rt_trap(WASM_RT_TRAP_OOB);
  pthread_mutex_lock(&gta_wait_lock);
  pthread_mutex_lock(&m->mem_lock);
  bool misaligned, outside;
  gta_check_address(m, addr, width, &misaligned, &outside);
  uint64_t value = 0;
  if (!outside && !misaligned) {
    if (width == 4) {
      const volatile uint32_t *p = (const volatile uint32_t *)
          (const void *)(m->data + addr);
      value = __atomic_load_n(p, __ATOMIC_SEQ_CST);
    } else {
      const volatile uint64_t *p = (const volatile uint64_t *)
          (const void *)(m->data + addr);
      value = __atomic_load_n(p, __ATOMIC_SEQ_CST);
    }
  }
  pthread_mutex_unlock(&m->mem_lock);
  if (misaligned || outside) {
    pthread_mutex_unlock(&gta_wait_lock);
    wasm_rt_trap(misaligned ? WASM_RT_TRAP_UNALIGNED : WASM_RT_TRAP_OOB);
  }
  if (value != expected) {
    pthread_mutex_unlock(&gta_wait_lock);
    return 1;
  }
  if (timeout_ns == 0) {
    pthread_mutex_unlock(&gta_wait_lock);
    return 2;
  }
  gta_waiter w = {0};
  w.memory = m;
  w.address = addr;
  if (pthread_cond_init(&w.cond, NULL) != 0) {
    pthread_mutex_unlock(&gta_wait_lock);
    wasm_rt_trap(WASM_RT_TRAP_UNREACHABLE);
  }
  w.next = gta_waiters;
  gta_waiters = &w;
  int status = 0;
  if (timeout_ns < 0) {
    while (!w.signalled && status == 0)
      status = pthread_cond_wait(&w.cond, &gta_wait_lock);
  } else {
    struct timespec deadline;
    if (clock_gettime(CLOCK_REALTIME, &deadline) != 0) {
      status = EINVAL;
    } else {
      deadline.tv_sec += timeout_ns / 1000000000LL;
      deadline.tv_nsec += timeout_ns % 1000000000LL;
      if (deadline.tv_nsec >= 1000000000L) {
        deadline.tv_sec++;
        deadline.tv_nsec -= 1000000000L;
      }
      while (!w.signalled && status == 0)
        status = pthread_cond_timedwait(&w.cond, &gta_wait_lock, &deadline);
    }
  }
  gta_waiter **it = &gta_waiters;
  while (*it && *it != &w) it = &(*it)->next;
  if (*it == &w) *it = w.next;
  const bool awakened = w.signalled;
  pthread_mutex_unlock(&gta_wait_lock);
  pthread_cond_destroy(&w.cond);
  return awakened ? 0 : 2;
}

uint32_t gta_wasm_atomic_wait32(wasm_rt_shared_memory_t *m, uint64_t addr,
                                uint32_t expected, int64_t timeout_ns) {
  return gta_wait(m, addr, expected, timeout_ns, 4);
}
uint32_t gta_wasm_atomic_wait64(wasm_rt_shared_memory_t *m, uint64_t addr,
                                uint64_t expected, int64_t timeout_ns) {
  return gta_wait(m, addr, expected, timeout_ns, 8);
}
uint32_t gta_wasm_atomic_notify(wasm_rt_shared_memory_t *m, uint64_t addr,
                                uint32_t count) {
  if (!m) wasm_rt_trap(WASM_RT_TRAP_OOB);
  pthread_mutex_lock(&gta_wait_lock);
  pthread_mutex_lock(&m->mem_lock);
  bool misaligned, outside;
  gta_check_address(m, addr, 4, &misaligned, &outside);
  pthread_mutex_unlock(&m->mem_lock);
  if (misaligned || outside) {
    pthread_mutex_unlock(&gta_wait_lock);
    wasm_rt_trap(misaligned ? WASM_RT_TRAP_UNALIGNED : WASM_RT_TRAP_OOB);
  }
  uint32_t woken = 0;
  for (gta_waiter *w = gta_waiters; w && woken < count; w = w->next) {
    if (w->memory == m && w->address == addr && !w->signalled) {
      w->signalled = true;
      pthread_cond_signal(&w->cond);
      woken++;
    }
  }
  pthread_mutex_unlock(&gta_wait_lock);
  return woken;
}
