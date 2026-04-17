/*
 * iDOpus — Core: Directory Buffer
 *
 * A directory buffer holds a cached listing of a filesystem directory.
 * Based on the original DOpus 5 DirBuffer, modernized for macOS.
 *
 * Architecture notes (from original):
 *   - Each Lister window displays one buffer at a time
 *   - Buffers are cached in a global list (MRU ordering)
 *   - A lister can switch between cached buffers instantly
 *   - Buffers are NOT shared simultaneously between listers
 *   - Each buffer has its own sort format and filter patterns
 */

#ifndef DIR_BUFFER_H
#define DIR_BUFFER_H

#include <stdbool.h>
#include <stdint.h>
#include <time.h>
#include "pal/pal_lists.h"
#include "pal/pal_sync.h"
#include "core/dir_entry.h"

/* Buffer state flags */
enum {
    DBUF_VALID      = (1 << 0),   /* buffer contains valid data */
    DBUF_READING    = (1 << 1),   /* currently reading directory */
    DBUF_ABORTED    = (1 << 2),   /* read was aborted */
    DBUF_READONLY   = (1 << 3),   /* volume is read-only */
    DBUF_ROOT       = (1 << 4),   /* showing a root/volume directory */
};

/* Display format — which columns and how */
typedef struct {
    sort_format_t   sort;
    char            show_pattern[128];   /* fnmatch pattern for inclusion */
    char            hide_pattern[128];   /* fnmatch pattern for exclusion */
    bool            reject_hidden;       /* hide dotfiles */
    bool            show_free_space;
} list_format_t;

/* --- Directory Buffer --- */

typedef struct dir_buffer {
    pal_node_t      node;               /* linkage in global buffer cache */
    pal_rwlock_t    lock;               /* read/write lock for thread safety */

    char            path[4096];         /* directory path */
    uint32_t        flags;              /* DBUF_* state flags */

    /* Entry storage */
    pal_list_t      entry_list;         /* all visible entries (dir_entry_t) */
    pal_list_t      reject_list;        /* entries hidden by filter */
    list_format_t   format;             /* current display/sort format */

    /* Statistics */
    struct {
        int32_t     total_entries;
        int32_t     total_files;
        int32_t     total_dirs;
        uint64_t    total_bytes;
        int32_t     selected_files;
        int32_t     selected_dirs;
        uint64_t    selected_bytes;
    } stats;

    /* Disk info */
    uint64_t        disk_total;
    uint64_t        disk_free;
    char            volume_name[256];

    /* Display state */
    int32_t         scroll_v;           /* vertical scroll offset */
    int32_t         scroll_h;           /* horizontal scroll offset */

    /* Directory timestamp (for change detection) */
    time_t          dir_timestamp;

    /* Owner tracking (which lister is showing this buffer) */
    void           *owner_lister;       /* opaque — will be Lister* later */

    /* Custom title (user-set label) */
    char            custom_title[128];

} dir_buffer_t;

/* --- Buffer lifecycle --- */

dir_buffer_t *dir_buffer_create(void);
void          dir_buffer_free(dir_buffer_t *buf);
void          dir_buffer_clear(dir_buffer_t *buf);  /* free entries, keep struct */

/* --- Buffer locking (thread-safe access) --- */

void dir_buffer_lock_read(dir_buffer_t *buf);
void dir_buffer_lock_write(dir_buffer_t *buf);
void dir_buffer_unlock(dir_buffer_t *buf);

/* --- Reading a directory into the buffer --- */

bool dir_buffer_read(dir_buffer_t *buf, const char *path);
bool dir_buffer_refresh(dir_buffer_t *buf);         /* re-read current path */

/* --- Entry management --- */

dir_entry_t *dir_buffer_add_entry(dir_buffer_t *buf, dir_entry_t *entry);
void         dir_buffer_remove_entry(dir_buffer_t *buf, dir_entry_t *entry);
dir_entry_t *dir_buffer_find_entry(dir_buffer_t *buf, const char *name);
dir_entry_t *dir_buffer_get_entry(dir_buffer_t *buf, int index);

/* --- Sorting --- */

void dir_buffer_sort(dir_buffer_t *buf);
void dir_buffer_set_sort(dir_buffer_t *buf, sort_field_t field,
                          bool reverse, separation_t sep);

/* --- Filtering --- */

void dir_buffer_set_filter(dir_buffer_t *buf,
                            const char *show_pattern,
                            const char *hide_pattern,
                            bool reject_hidden);
void dir_buffer_apply_filter(dir_buffer_t *buf);    /* move entries ↔ reject_list */

/* --- Selection --- */

void dir_buffer_select_all(dir_buffer_t *buf);
void dir_buffer_deselect_all(dir_buffer_t *buf);
void dir_buffer_select_pattern(dir_buffer_t *buf, const char *pattern, bool select);
void dir_buffer_update_stats(dir_buffer_t *buf);    /* recalculate counts/bytes */

/* --- Buffer cache management --- */

typedef struct {
    pal_list_t      list;               /* cached buffers (MRU order) */
    pal_mutex_t     lock;
    int32_t         count;
    int32_t         max_count;
} buffer_cache_t;

buffer_cache_t *buffer_cache_create(int max_buffers);
void            buffer_cache_free(buffer_cache_t *cache);
dir_buffer_t   *buffer_cache_find(buffer_cache_t *cache, const char *path);
dir_buffer_t   *buffer_cache_get_or_create(buffer_cache_t *cache, const char *path);
void            buffer_cache_touch(buffer_cache_t *cache, dir_buffer_t *buf);

#endif /* DIR_BUFFER_H */
