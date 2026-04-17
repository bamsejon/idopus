/*
 * iDOpus — Platform Abstraction Layer: Synchronization
 *
 * Replaces Amiga exec.library synchronization:
 *   SignalSemaphore, ObtainSemaphore, ReleaseSemaphore,
 *   ObtainSemaphoreShared, AttemptSemaphore,
 *   Forbid/Permit (global lock)
 *
 * macOS implementation: pthread_mutex for exclusive,
 * pthread_rwlock for shared/exclusive, os_unfair_lock for spinlocks.
 */

#ifndef PAL_SYNC_H
#define PAL_SYNC_H

#include <stdbool.h>
#include <pthread.h>

/* --- Mutex (replaces SignalSemaphore exclusive) --- */

typedef struct {
    pthread_mutex_t mutex;
} pal_mutex_t;

void pal_mutex_init(pal_mutex_t *m);
void pal_mutex_destroy(pal_mutex_t *m);
void pal_mutex_lock(pal_mutex_t *m);
void pal_mutex_unlock(pal_mutex_t *m);
bool pal_mutex_trylock(pal_mutex_t *m);

/* --- RWLock (replaces ObtainSemaphore / ObtainSemaphoreShared) --- */

typedef struct {
    pthread_rwlock_t rwlock;
} pal_rwlock_t;

void pal_rwlock_init(pal_rwlock_t *rw);
void pal_rwlock_destroy(pal_rwlock_t *rw);
void pal_rwlock_read_lock(pal_rwlock_t *rw);
void pal_rwlock_read_unlock(pal_rwlock_t *rw);
void pal_rwlock_write_lock(pal_rwlock_t *rw);
void pal_rwlock_write_unlock(pal_rwlock_t *rw);

/* --- Condition Variable (no direct Amiga equivalent, but needed for IPC) --- */

typedef struct {
    pthread_cond_t cond;
} pal_cond_t;

void pal_cond_init(pal_cond_t *c);
void pal_cond_destroy(pal_cond_t *c);
void pal_cond_wait(pal_cond_t *c, pal_mutex_t *m);
bool pal_cond_timedwait(pal_cond_t *c, pal_mutex_t *m, unsigned int timeout_ms);
void pal_cond_signal(pal_cond_t *c);
void pal_cond_broadcast(pal_cond_t *c);

#endif /* PAL_SYNC_H */
