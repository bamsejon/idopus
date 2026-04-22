/*
 * iDOpus — Platform Abstraction Layer: Synchronization
 *
 * Replaces Amiga exec.library synchronization:
 *   SignalSemaphore, ObtainSemaphore, ReleaseSemaphore,
 *   ObtainSemaphoreShared, AttemptSemaphore,
 *   Forbid/Permit (global lock)
 *
 * POSIX implementation: pthread_mutex/pthread_rwlock/pthread_cond.
 * Windows implementation: CRITICAL_SECTION + SRWLOCK + CONDITION_VARIABLE.
 */

#ifndef PAL_SYNC_H
#define PAL_SYNC_H

#include <stdbool.h>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <pthread.h>
#endif

/* --- Mutex (replaces SignalSemaphore exclusive, recursive) --- */

typedef struct {
#ifdef _WIN32
    CRITICAL_SECTION cs;
#else
    pthread_mutex_t mutex;
#endif
} pal_mutex_t;

void pal_mutex_init(pal_mutex_t *m);
void pal_mutex_destroy(pal_mutex_t *m);
void pal_mutex_lock(pal_mutex_t *m);
void pal_mutex_unlock(pal_mutex_t *m);
bool pal_mutex_trylock(pal_mutex_t *m);

/* --- RWLock (replaces ObtainSemaphore / ObtainSemaphoreShared) --- */

typedef struct {
#ifdef _WIN32
    SRWLOCK lock;
    /* SRWLOCK needs separate shared/exclusive release; track last-acquired
     * mode so the single pal_rwlock_*_unlock surface stays mode-agnostic
     * (matches pthread_rwlock_unlock semantics). */
    volatile LONG writer_held;
#else
    pthread_rwlock_t rwlock;
#endif
} pal_rwlock_t;

void pal_rwlock_init(pal_rwlock_t *rw);
void pal_rwlock_destroy(pal_rwlock_t *rw);
void pal_rwlock_read_lock(pal_rwlock_t *rw);
void pal_rwlock_read_unlock(pal_rwlock_t *rw);
void pal_rwlock_write_lock(pal_rwlock_t *rw);
void pal_rwlock_write_unlock(pal_rwlock_t *rw);

/* --- Condition Variable (no direct Amiga equivalent, but needed for IPC) --- */

typedef struct {
#ifdef _WIN32
    CONDITION_VARIABLE cond;
#else
    pthread_cond_t cond;
#endif
} pal_cond_t;

void pal_cond_init(pal_cond_t *c);
void pal_cond_destroy(pal_cond_t *c);
void pal_cond_wait(pal_cond_t *c, pal_mutex_t *m);
bool pal_cond_timedwait(pal_cond_t *c, pal_mutex_t *m, unsigned int timeout_ms);
void pal_cond_signal(pal_cond_t *c);
void pal_cond_broadcast(pal_cond_t *c);

#endif /* PAL_SYNC_H */
