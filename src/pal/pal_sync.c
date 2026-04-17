/*
 * iDOpus — PAL Synchronization implementation (macOS/POSIX)
 */

#include "pal/pal_sync.h"
#include <sys/time.h>
#include <errno.h>

/* --- Mutex --- */

void pal_mutex_init(pal_mutex_t *m)
{
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&m->mutex, &attr);
    pthread_mutexattr_destroy(&attr);
}

void pal_mutex_destroy(pal_mutex_t *m)
{
    pthread_mutex_destroy(&m->mutex);
}

void pal_mutex_lock(pal_mutex_t *m)
{
    pthread_mutex_lock(&m->mutex);
}

void pal_mutex_unlock(pal_mutex_t *m)
{
    pthread_mutex_unlock(&m->mutex);
}

bool pal_mutex_trylock(pal_mutex_t *m)
{
    return pthread_mutex_trylock(&m->mutex) == 0;
}

/* --- RWLock --- */

void pal_rwlock_init(pal_rwlock_t *rw)
{
    pthread_rwlock_init(&rw->rwlock, NULL);
}

void pal_rwlock_destroy(pal_rwlock_t *rw)
{
    pthread_rwlock_destroy(&rw->rwlock);
}

void pal_rwlock_read_lock(pal_rwlock_t *rw)
{
    pthread_rwlock_rdlock(&rw->rwlock);
}

void pal_rwlock_read_unlock(pal_rwlock_t *rw)
{
    pthread_rwlock_unlock(&rw->rwlock);
}

void pal_rwlock_write_lock(pal_rwlock_t *rw)
{
    pthread_rwlock_wrlock(&rw->rwlock);
}

void pal_rwlock_write_unlock(pal_rwlock_t *rw)
{
    pthread_rwlock_unlock(&rw->rwlock);
}

/* --- Condition Variable --- */

void pal_cond_init(pal_cond_t *c)
{
    pthread_cond_init(&c->cond, NULL);
}

void pal_cond_destroy(pal_cond_t *c)
{
    pthread_cond_destroy(&c->cond);
}

void pal_cond_wait(pal_cond_t *c, pal_mutex_t *m)
{
    pthread_cond_wait(&c->cond, &m->mutex);
}

bool pal_cond_timedwait(pal_cond_t *c, pal_mutex_t *m, unsigned int timeout_ms)
{
    struct timespec ts;
    struct timeval tv;
    gettimeofday(&tv, NULL);
    ts.tv_sec = tv.tv_sec + timeout_ms / 1000;
    ts.tv_nsec = (tv.tv_usec * 1000) + (timeout_ms % 1000) * 1000000;
    if (ts.tv_nsec >= 1000000000) {
        ts.tv_sec++;
        ts.tv_nsec -= 1000000000;
    }
    return pthread_cond_timedwait(&c->cond, &m->mutex, &ts) == 0;
}

void pal_cond_signal(pal_cond_t *c)
{
    pthread_cond_signal(&c->cond);
}

void pal_cond_broadcast(pal_cond_t *c)
{
    pthread_cond_broadcast(&c->cond);
}
