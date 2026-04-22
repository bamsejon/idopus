/*
 * iDOpus — PAL Synchronization implementation (Windows)
 *
 * CRITICAL_SECTION for recursive mutex, SRWLOCK for rwlock,
 * CONDITION_VARIABLE for condvar. All Vista+ APIs.
 */

#include "pal/pal_sync.h"

/* --- Mutex --- */

void pal_mutex_init(pal_mutex_t *m)
{
    /* CRITICAL_SECTION is recursive by default */
    InitializeCriticalSection(&m->cs);
}

void pal_mutex_destroy(pal_mutex_t *m)
{
    DeleteCriticalSection(&m->cs);
}

void pal_mutex_lock(pal_mutex_t *m)
{
    EnterCriticalSection(&m->cs);
}

void pal_mutex_unlock(pal_mutex_t *m)
{
    LeaveCriticalSection(&m->cs);
}

bool pal_mutex_trylock(pal_mutex_t *m)
{
    return TryEnterCriticalSection(&m->cs) != 0;
}

/* --- RWLock --- */

void pal_rwlock_init(pal_rwlock_t *rw)
{
    InitializeSRWLock(&rw->lock);
}

void pal_rwlock_destroy(pal_rwlock_t *rw)
{
    /* SRWLOCK has no destroy */
    (void)rw;
}

void pal_rwlock_read_lock(pal_rwlock_t *rw)
{
    AcquireSRWLockShared(&rw->lock);
}

void pal_rwlock_read_unlock(pal_rwlock_t *rw)
{
    ReleaseSRWLockShared(&rw->lock);
}

void pal_rwlock_write_lock(pal_rwlock_t *rw)
{
    AcquireSRWLockExclusive(&rw->lock);
}

void pal_rwlock_write_unlock(pal_rwlock_t *rw)
{
    ReleaseSRWLockExclusive(&rw->lock);
}

/* --- Condition Variable --- */

void pal_cond_init(pal_cond_t *c)
{
    InitializeConditionVariable(&c->cond);
}

void pal_cond_destroy(pal_cond_t *c)
{
    /* CONDITION_VARIABLE has no destroy */
    (void)c;
}

void pal_cond_wait(pal_cond_t *c, pal_mutex_t *m)
{
    SleepConditionVariableCS(&c->cond, &m->cs, INFINITE);
}

bool pal_cond_timedwait(pal_cond_t *c, pal_mutex_t *m, unsigned int timeout_ms)
{
    return SleepConditionVariableCS(&c->cond, &m->cs, (DWORD)timeout_ms) != 0;
}

void pal_cond_signal(pal_cond_t *c)
{
    WakeConditionVariable(&c->cond);
}

void pal_cond_broadcast(pal_cond_t *c)
{
    WakeAllConditionVariable(&c->cond);
}
