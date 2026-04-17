/*
 * iDOpus — PAL Memory implementation (macOS)
 */

#include "pal/pal_memory.h"
#include <stdlib.h>
#include <string.h>

/* --- Basic allocation --- */

void *pal_alloc(size_t size)
{
    if (size == 0) return NULL;
    return malloc(size);
}

void *pal_alloc_clear(size_t size)
{
    if (size == 0) return NULL;
    return calloc(1, size);
}

void pal_free(void *ptr)
{
    free(ptr);
}

/* --- Pool allocator ---
 *
 * On Amiga, pools were essential for performance (AllocPooled avoided
 * repeated kernel calls). On macOS, malloc is already very fast and
 * zone-based. This implementation is a thin wrapper — the pool struct
 * exists for API compatibility, but allocations go through malloc.
 *
 * A more sophisticated implementation using malloc_zone_create()
 * can be added later if profiling shows it's needed.
 */

struct pal_pool {
    size_t puddle_size;
    size_t thresh_size;
    size_t total_allocated;
};

pal_pool_t *pal_pool_create(size_t puddle_size, size_t thresh_size)
{
    pal_pool_t *pool = calloc(1, sizeof(pal_pool_t));
    if (pool) {
        pool->puddle_size = puddle_size;
        pool->thresh_size = thresh_size;
    }
    return pool;
}

void pal_pool_destroy(pal_pool_t *pool)
{
    /* In a real pool allocator we'd free all puddles here.
     * With malloc pass-through, individual frees are the caller's job.
     * This is a known leak source during transition — tracked. */
    free(pool);
}

void *pal_pool_alloc(pal_pool_t *pool, size_t size)
{
    if (!pool || size == 0) return NULL;
    void *ptr = malloc(size);
    if (ptr) pool->total_allocated += size;
    return ptr;
}

void pal_pool_free(pal_pool_t *pool, void *ptr, size_t size)
{
    if (!pool) return;
    if (ptr) {
        pool->total_allocated -= size;
        free(ptr);
    }
}

/* --- Utilities --- */

void pal_memcopy(const void *src, void *dst, size_t size)
{
    /* Note: Amiga CopyMem has src,dst order (opposite of memcpy).
     * We preserve the Amiga convention here to ease porting. */
    if (src && dst && size > 0)
        memcpy(dst, src, size);
}
