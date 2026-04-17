/*
 * iDOpus — Core: Directory Buffer implementation
 *
 * Mirrors the original DOpus 5 buffer architecture:
 *   - Shell sort (same algorithm as buffers_sort.c)
 *   - Dir/file separation with independent sorting
 *   - Filter patterns (show/hide) with reject list
 *   - Buffer cache with MRU ordering
 *   - Thread-safe via rwlock
 */

#include "core/dir_buffer.h"
#include "pal/pal_memory.h"
#include "pal/pal_strings.h"
#include "pal/pal_file.h"
#include <stdlib.h>
#include <string.h>

/* --- Lifecycle --- */

dir_buffer_t *dir_buffer_create(void)
{
    dir_buffer_t *buf = pal_alloc_clear(sizeof(dir_buffer_t));
    if (!buf) return NULL;
    pal_list_init(&buf->entry_list);
    pal_list_init(&buf->reject_list);
    pal_rwlock_init(&buf->lock);
    buf->format.sort.field = SORT_NAME;
    buf->format.sort.separation = SEPARATE_DIRS_FIRST;
    return buf;
}

static void free_entry_list(pal_list_t *list)
{
    pal_node_t *node, *tmp;
    node = list->head;
    while (node) {
        tmp = node->next;
        dir_entry_t *entry = PAL_CONTAINER_OF(node, dir_entry_t, node);
        dir_entry_free(entry);
        node = tmp;
    }
    pal_list_init(list);
}

void dir_buffer_clear(dir_buffer_t *buf)
{
    if (!buf) return;
    free_entry_list(&buf->entry_list);
    free_entry_list(&buf->reject_list);
    memset(&buf->stats, 0, sizeof(buf->stats));
    buf->flags = 0;
    buf->scroll_v = 0;
    buf->scroll_h = 0;
}

void dir_buffer_free(dir_buffer_t *buf)
{
    if (!buf) return;
    dir_buffer_clear(buf);
    pal_rwlock_destroy(&buf->lock);
    pal_free(buf);
}

/* --- Locking --- */

void dir_buffer_lock_read(dir_buffer_t *buf)  { pal_rwlock_read_lock(&buf->lock); }
void dir_buffer_lock_write(dir_buffer_t *buf) { pal_rwlock_write_lock(&buf->lock); }
void dir_buffer_unlock(dir_buffer_t *buf)     { pal_rwlock_read_unlock(&buf->lock); }

/* --- Reading --- */

bool dir_buffer_read(dir_buffer_t *buf, const char *path)
{
    if (!buf || !path) return false;

    dir_buffer_lock_write(buf);
    dir_buffer_clear(buf);
    pal_strlcpy(buf->path, path, sizeof(buf->path));
    buf->flags = DBUF_READING;

    pal_dir_t *dir = pal_dir_open(path);
    if (!dir) {
        buf->flags = DBUF_ABORTED;
        dir_buffer_unlock(buf);
        return false;
    }

    pal_fileinfo_t info;
    while (pal_dir_next(dir, &info)) {
        dir_entry_type_t type = (info.type == PAL_FILE_TYPE_DIR) ?
                                 ENTRY_DIRECTORY : ENTRY_FILE;
        dir_entry_t *entry = dir_entry_create(info.name, info.size,
                                               type, info.date_modified,
                                               info.permissions);
        if (entry) {
            entry->date_created = info.date_created;
            if (info.hidden) entry->flags |= ENTF_HIDDEN;
            if (info.readonly) entry->flags |= ENTF_READONLY;
            if (info.type == PAL_FILE_TYPE_LINK) entry->flags |= ENTF_LINK;
            pal_list_add_tail(&buf->entry_list, &entry->node);
        }
    }
    pal_dir_close(dir);

    /* Get disk info */
    pal_volume_t vols[32];
    int nvols = pal_volumes_list(vols, 32);
    for (int i = 0; i < nvols; i++) {
        if (strncmp(path, vols[i].mount_point, strlen(vols[i].mount_point)) == 0) {
            buf->disk_total = vols[i].total_bytes;
            buf->disk_free = vols[i].free_bytes;
            pal_strlcpy(buf->volume_name, vols[i].name, sizeof(buf->volume_name));
            break;
        }
    }

    /* Apply filter and sort */
    dir_buffer_apply_filter(buf);
    dir_buffer_sort(buf);
    dir_buffer_update_stats(buf);

    buf->flags = DBUF_VALID;
    buf->dir_timestamp = time(NULL);
    dir_buffer_unlock(buf);
    return true;
}

bool dir_buffer_refresh(dir_buffer_t *buf)
{
    if (!buf || !buf->path[0]) return false;
    return dir_buffer_read(buf, buf->path);
}

/* --- Entry management --- */

dir_entry_t *dir_buffer_add_entry(dir_buffer_t *buf, dir_entry_t *entry)
{
    if (!buf || !entry) return NULL;
    pal_list_add_tail(&buf->entry_list, &entry->node);
    return entry;
}

void dir_buffer_remove_entry(dir_buffer_t *buf, dir_entry_t *entry)
{
    if (!buf || !entry) return;
    pal_list_remove_from(&buf->entry_list, &entry->node);
    /* Update stats */
    if (dir_entry_is_dir(entry)) {
        buf->stats.total_dirs--;
        if (dir_entry_is_selected(entry)) buf->stats.selected_dirs--;
    } else {
        buf->stats.total_files--;
        buf->stats.total_bytes -= entry->size;
        if (dir_entry_is_selected(entry)) {
            buf->stats.selected_files--;
            buf->stats.selected_bytes -= entry->size;
        }
    }
    buf->stats.total_entries--;
}

dir_entry_t *dir_buffer_find_entry(dir_buffer_t *buf, const char *name)
{
    if (!buf || !name) return NULL;
    pal_node_t *node = buf->entry_list.head;
    while (node) {
        dir_entry_t *e = PAL_CONTAINER_OF(node, dir_entry_t, node);
        if (pal_stricmp(e->name, name) == 0) return e;
        node = node->next;
    }
    return NULL;
}

dir_entry_t *dir_buffer_get_entry(dir_buffer_t *buf, int index)
{
    if (!buf || index < 0) return NULL;
    pal_node_t *node = buf->entry_list.head;
    for (int i = 0; node; node = node->next, i++)
        if (i == index)
            return PAL_CONTAINER_OF(node, dir_entry_t, node);
    return NULL;
}

/* --- Sorting ---
 *
 * Uses Shell sort, same algorithm as the original buffers_sort.c.
 * Entries are extracted to a temporary array, sorted, then re-linked.
 * Dir/file separation is handled by splitting into two arrays first.
 */

static void shell_sort_entries(dir_entry_t **arr, int count, entry_compare_fn cmp, bool reverse)
{
    if (count <= 1) return;

    /* Shell sort gap sequence */
    int gap = 1;
    while (gap < count / 3) gap = gap * 3 + 1;

    while (gap > 0) {
        for (int i = gap; i < count; i++) {
            dir_entry_t *tmp = arr[i];
            int j = i;
            while (j >= gap) {
                int c = cmp(arr[j - gap], tmp);
                if (reverse) c = -c;
                if (c <= 0) break;
                arr[j] = arr[j - gap];
                j -= gap;
            }
            arr[j] = tmp;
        }
        gap /= 3;
    }
}

static int collect_entries(pal_list_t *list, dir_entry_t ***out_dirs, int *ndir,
                            dir_entry_t ***out_files, int *nfile)
{
    /* Count */
    int dc = 0, fc = 0;
    pal_node_t *n = list->head;
    while (n) {
        dir_entry_t *e = PAL_CONTAINER_OF(n, dir_entry_t, node);
        if (dir_entry_is_dir(e)) dc++; else fc++;
        n = n->next;
    }

    *out_dirs = dc ? pal_alloc(dc * sizeof(dir_entry_t *)) : NULL;
    *out_files = fc ? pal_alloc(fc * sizeof(dir_entry_t *)) : NULL;
    *ndir = dc;
    *nfile = fc;

    int di = 0, fi = 0;
    pal_node_t *n2;
    while ((n2 = pal_list_rem_head(list))) {
        dir_entry_t *e = PAL_CONTAINER_OF(n2, dir_entry_t, node);
        if (dir_entry_is_dir(e))
            (*out_dirs)[di++] = e;
        else
            (*out_files)[fi++] = e;
    }
    return dc + fc;
}

void dir_buffer_sort(dir_buffer_t *buf)
{
    if (!buf) return;

    entry_compare_fn cmp = dir_entry_get_comparator(buf->format.sort.field);
    bool reverse = (buf->format.sort.flags & SORTF_REVERSE) != 0;

    if (buf->format.sort.separation == SEPARATE_MIX) {
        /* Sort everything together */
        int count = pal_list_count(&buf->entry_list);
        if (count <= 1) return;

        dir_entry_t **arr = pal_alloc(count * sizeof(dir_entry_t *));
        if (!arr) return;

        int i = 0;
        pal_node_t *n;
        while ((n = pal_list_rem_head(&buf->entry_list)))
            arr[i++] = PAL_CONTAINER_OF(n, dir_entry_t, node);

        shell_sort_entries(arr, count, cmp, reverse);
        for (i = 0; i < count; i++)
            pal_list_add_tail(&buf->entry_list, &arr[i]->node);

        pal_free(arr);
    } else {
        /* Separate dirs and files, sort independently */
        dir_entry_t **dirs, **files;
        int ndir, nfile;
        collect_entries(&buf->entry_list, &dirs, &ndir, &files, &nfile);

        if (ndir > 0) shell_sort_entries(dirs, ndir, cmp, reverse);
        if (nfile > 0) shell_sort_entries(files, nfile, cmp, reverse);

        /* Rebuild list in correct separation order */
        if (buf->format.sort.separation == SEPARATE_DIRS_FIRST) {
            for (int i = 0; i < ndir; i++)
                pal_list_add_tail(&buf->entry_list, &dirs[i]->node);
            for (int i = 0; i < nfile; i++)
                pal_list_add_tail(&buf->entry_list, &files[i]->node);
        } else {
            for (int i = 0; i < nfile; i++)
                pal_list_add_tail(&buf->entry_list, &files[i]->node);
            for (int i = 0; i < ndir; i++)
                pal_list_add_tail(&buf->entry_list, &dirs[i]->node);
        }

        pal_free(dirs);
        pal_free(files);
    }
}

void dir_buffer_set_sort(dir_buffer_t *buf, sort_field_t field,
                          bool reverse, separation_t sep)
{
    if (!buf) return;
    buf->format.sort.field = field;
    buf->format.sort.flags = reverse ? SORTF_REVERSE : 0;
    buf->format.sort.separation = sep;
    dir_buffer_sort(buf);
}

/* --- Filtering --- */

void dir_buffer_set_filter(dir_buffer_t *buf,
                            const char *show_pattern,
                            const char *hide_pattern,
                            bool reject_hidden)
{
    if (!buf) return;
    if (show_pattern)
        pal_strlcpy(buf->format.show_pattern, show_pattern, sizeof(buf->format.show_pattern));
    else
        buf->format.show_pattern[0] = '\0';
    if (hide_pattern)
        pal_strlcpy(buf->format.hide_pattern, hide_pattern, sizeof(buf->format.hide_pattern));
    else
        buf->format.hide_pattern[0] = '\0';
    buf->format.reject_hidden = reject_hidden;
}

static bool entry_should_reject(dir_entry_t *entry, list_format_t *fmt)
{
    if (!entry) return true;
    /* Don't reject directories */
    if (dir_entry_is_dir(entry)) return false;
    /* Hidden files */
    if (fmt->reject_hidden && (entry->flags & ENTF_HIDDEN)) return true;
    /* Show pattern — must match */
    if (fmt->show_pattern[0] && !pal_path_match(fmt->show_pattern, entry->name))
        return true;
    /* Hide pattern — must NOT match */
    if (fmt->hide_pattern[0] && pal_path_match(fmt->hide_pattern, entry->name))
        return true;
    return false;
}

void dir_buffer_apply_filter(dir_buffer_t *buf)
{
    if (!buf) return;

    /* Move rejects back to entry list first */
    /* Move all rejects back to entry list */
    pal_node_t *n;
    while ((n = pal_list_rem_head(&buf->reject_list)))
        pal_list_add_tail(&buf->entry_list, n);

    /* Now filter: move rejected entries out */
    n = buf->entry_list.head;
    while (n) {
        pal_node_t *next = n->next;
        dir_entry_t *e = PAL_CONTAINER_OF(n, dir_entry_t, node);
        if (entry_should_reject(e, &buf->format)) {
            pal_list_remove_from(&buf->entry_list, n);
            pal_list_add_tail(&buf->reject_list, n);
        }
        n = next;
    }
}

/* --- Selection --- */

void dir_buffer_select_all(dir_buffer_t *buf)
{
    if (!buf) return;
    pal_node_t *n = buf->entry_list.head;
    while (n) {
        dir_entry_select(PAL_CONTAINER_OF(n, dir_entry_t, node), true);
        n = n->next;
    }
    dir_buffer_update_stats(buf);
}

void dir_buffer_deselect_all(dir_buffer_t *buf)
{
    if (!buf) return;
    pal_node_t *n = buf->entry_list.head;
    while (n) {
        dir_entry_select(PAL_CONTAINER_OF(n, dir_entry_t, node), false);
        n = n->next;
    }
    dir_buffer_update_stats(buf);
}

void dir_buffer_select_pattern(dir_buffer_t *buf, const char *pattern, bool select)
{
    if (!buf || !pattern) return;
    pal_node_t *n = buf->entry_list.head;
    while (n) {
        dir_entry_t *e = PAL_CONTAINER_OF(n, dir_entry_t, node);
        if (pal_path_match(pattern, e->name))
            dir_entry_select(e, select);
        n = n->next;
    }
    dir_buffer_update_stats(buf);
}

void dir_buffer_update_stats(dir_buffer_t *buf)
{
    if (!buf) return;
    memset(&buf->stats, 0, sizeof(buf->stats));
    pal_node_t *n = buf->entry_list.head;
    while (n) {
        dir_entry_t *e = PAL_CONTAINER_OF(n, dir_entry_t, node);
        buf->stats.total_entries++;
        if (dir_entry_is_dir(e)) {
            buf->stats.total_dirs++;
            if (dir_entry_is_selected(e)) buf->stats.selected_dirs++;
        } else {
            buf->stats.total_files++;
            buf->stats.total_bytes += e->size;
            if (dir_entry_is_selected(e)) {
                buf->stats.selected_files++;
                buf->stats.selected_bytes += e->size;
            }
        }
        n = n->next;
    }
}

/* --- Buffer Cache --- */

buffer_cache_t *buffer_cache_create(int max_buffers)
{
    buffer_cache_t *cache = pal_alloc_clear(sizeof(buffer_cache_t));
    if (!cache) return NULL;
    pal_list_init(&cache->list);
    pal_mutex_init(&cache->lock);
    cache->max_count = max_buffers;
    return cache;
}

void buffer_cache_free(buffer_cache_t *cache)
{
    if (!cache) return;
    pal_node_t *n = cache->list.head;
    while (n) {
        pal_node_t *next = n->next;
        dir_buffer_free(PAL_CONTAINER_OF(n, dir_buffer_t, node));
        n = next;
    }
    pal_mutex_destroy(&cache->lock);
    pal_free(cache);
}

dir_buffer_t *buffer_cache_find(buffer_cache_t *cache, const char *path)
{
    if (!cache || !path) return NULL;
    pal_mutex_lock(&cache->lock);
    pal_node_t *n = cache->list.head;
    while (n) {
        dir_buffer_t *buf = PAL_CONTAINER_OF(n, dir_buffer_t, node);
        if (strcmp(buf->path, path) == 0 && !buf->owner_lister) {
            pal_mutex_unlock(&cache->lock);
            return buf;
        }
        n = n->next;
    }
    pal_mutex_unlock(&cache->lock);
    return NULL;
}

dir_buffer_t *buffer_cache_get_or_create(buffer_cache_t *cache, const char *path)
{
    if (!cache) return NULL;

    /* Try cache first */
    dir_buffer_t *buf = buffer_cache_find(cache, path);
    if (buf) {
        buffer_cache_touch(cache, buf);
        return buf;
    }

    pal_mutex_lock(&cache->lock);

    /* Over limit? Evict LRU (last in list) without an owner */
    if (cache->count >= cache->max_count) {
        pal_node_t *n = cache->list.tail;
        while (n) {
            pal_node_t *prev = n->prev;
            dir_buffer_t *candidate = PAL_CONTAINER_OF(n, dir_buffer_t, node);
            if (!candidate->owner_lister) {
                pal_list_remove_from(&cache->list, n);
                dir_buffer_free(candidate);
                cache->count--;
                break;
            }
            n = prev;
        }
    }

    /* Create new */
    buf = dir_buffer_create();
    if (buf) {
        if (path)
            pal_strlcpy(buf->path, path, sizeof(buf->path));
        pal_list_add_head(&cache->list, &buf->node);
        cache->count++;
    }

    pal_mutex_unlock(&cache->lock);
    return buf;
}

void buffer_cache_touch(buffer_cache_t *cache, dir_buffer_t *buf)
{
    if (!cache || !buf) return;
    pal_mutex_lock(&cache->lock);
    pal_list_remove_from(&cache->list, &buf->node);
    pal_list_add_head(&cache->list, &buf->node);
    pal_mutex_unlock(&cache->lock);
}
