/*
 * iDOpus — Platform Abstraction Layer: Memory
 *
 * Replaces Amiga exec.library memory functions:
 *   AllocVec/FreeVec, AllocMem/FreeMem, AllocPooled/FreePooled,
 *   CopyMem, MEMF_CLEAR, MEMF_ANY, MEMF_PUBLIC
 *
 * macOS implementation: standard malloc/free/calloc with optional
 * pool allocator for hot-path allocations.
 */

#ifndef PAL_MEMORY_H
#define PAL_MEMORY_H

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>

/* --- Basic allocation (replaces AllocVec/FreeVec) --- */

void *pal_alloc(size_t size);
void *pal_alloc_clear(size_t size);   /* zeroed, replaces MEMF_CLEAR */
void  pal_free(void *ptr);

/* --- Pool allocator (replaces AllocPooled/FreePooled) --- */

typedef struct pal_pool pal_pool_t;

pal_pool_t *pal_pool_create(size_t puddle_size, size_t thresh_size);
void        pal_pool_destroy(pal_pool_t *pool);
void       *pal_pool_alloc(pal_pool_t *pool, size_t size);
void        pal_pool_free(pal_pool_t *pool, void *ptr, size_t size);

/* --- Utilities (replaces CopyMem) --- */

void pal_memcopy(const void *src, void *dst, size_t size);

#endif /* PAL_MEMORY_H */
