/*
 * iDOpus — Core: Directory Entry implementation
 *
 * Sorting mirrors the original DOpus 5 approach:
 *   - Shell sort on entry arrays (same as buffers_sort.c)
 *   - Name sort handles leading numbers intelligently
 *   - All sort functions fall back to name comparison on tie
 */

#include "core/dir_entry.h"
#include "pal/pal_memory.h"
#include "pal/pal_strings.h"
#include "pal/pal_file.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* --- Lifecycle --- */

dir_entry_t *dir_entry_create(const char *name, uint64_t size,
                               dir_entry_type_t type, time_t date,
                               uint32_t permissions)
{
    dir_entry_t *e = pal_alloc_clear(sizeof(dir_entry_t));
    if (!e) return NULL;

    e->name = pal_strdup(name ? name : "");
    e->name_len = (uint8_t)(name ? strlen(name) : 0);
    e->size = size;
    e->type = type;
    e->date_modified = date;
    e->permissions = permissions;
    e->flags = 0;

    return e;
}

dir_entry_t *dir_entry_copy(const dir_entry_t *src)
{
    if (!src) return NULL;
    dir_entry_t *dst = pal_alloc_clear(sizeof(dir_entry_t));
    if (!dst) return NULL;

    *dst = *src;
    dst->node.next = NULL;
    dst->node.prev = NULL;
    dst->name = pal_strdup(src->name);
    dst->comment = src->comment ? pal_strdup(src->comment) : NULL;
    dst->filetype_desc = src->filetype_desc ? pal_strdup(src->filetype_desc) : NULL;
    dst->owner = src->owner ? pal_strdup(src->owner) : NULL;
    dst->group = src->group ? pal_strdup(src->group) : NULL;

    return dst;
}

void dir_entry_free(dir_entry_t *entry)
{
    if (!entry) return;
    pal_free(entry->name);
    pal_free(entry->comment);
    pal_free(entry->filetype_desc);
    pal_free(entry->owner);
    pal_free(entry->group);
    pal_free(entry);
}

/* --- Accessors --- */

void dir_entry_set_comment(dir_entry_t *entry, const char *comment)
{
    if (!entry) return;
    pal_free(entry->comment);
    entry->comment = comment ? pal_strdup(comment) : NULL;
}

void dir_entry_set_filetype(dir_entry_t *entry, const char *desc)
{
    if (!entry) return;
    pal_free(entry->filetype_desc);
    entry->filetype_desc = desc ? pal_strdup(desc) : NULL;
}

bool dir_entry_is_dir(const dir_entry_t *entry)
{
    return entry && entry->type == ENTRY_DIRECTORY;
}

bool dir_entry_is_selected(const dir_entry_t *entry)
{
    return entry && (entry->flags & ENTF_SELECTED);
}

void dir_entry_select(dir_entry_t *entry, bool selected)
{
    if (!entry) return;
    if (selected) entry->flags |= ENTF_SELECTED;
    else          entry->flags &= ~ENTF_SELECTED;
}

/* --- Comparison functions ---
 *
 * The original DOpus 5 namesort() handles leading numeric strings
 * intelligently: "file2" sorts before "file10". We preserve that.
 */

static int smart_name_compare(const char *a, const char *b)
{
    if (!a || !b) return a ? 1 : (b ? -1 : 0);

    while (*a && *b) {
        if (isdigit((unsigned char)*a) && isdigit((unsigned char)*b)) {
            /* Both at a digit run — compare numerically */
            unsigned long na = strtoul(a, (char **)&a, 10);
            unsigned long nb = strtoul(b, (char **)&b, 10);
            if (na != nb) return (na < nb) ? -1 : 1;
        } else {
            int ca = tolower((unsigned char)*a);
            int cb = tolower((unsigned char)*b);
            if (ca != cb) return ca - cb;
            a++;
            b++;
        }
    }
    return (unsigned char)*a - (unsigned char)*b;
}

int dir_entry_compare_name(const dir_entry_t *a, const dir_entry_t *b)
{
    return smart_name_compare(a->name, b->name);
}

int dir_entry_compare_size(const dir_entry_t *a, const dir_entry_t *b)
{
    if (a->size != b->size)
        return (a->size < b->size) ? -1 : 1;
    return dir_entry_compare_name(a, b);
}

int dir_entry_compare_date(const dir_entry_t *a, const dir_entry_t *b)
{
    if (a->date_modified != b->date_modified)
        return (a->date_modified < b->date_modified) ? -1 : 1;
    return dir_entry_compare_name(a, b);
}

int dir_entry_compare_type(const dir_entry_t *a, const dir_entry_t *b)
{
    const char *ta = a->filetype_desc ? a->filetype_desc : "";
    const char *tb = b->filetype_desc ? b->filetype_desc : "";
    int cmp = pal_stricmp(ta, tb);
    return cmp ? cmp : dir_entry_compare_name(a, b);
}

int dir_entry_compare_extension(const dir_entry_t *a, const dir_entry_t *b)
{
    const char *ea = pal_path_extension(a->name);
    const char *eb = pal_path_extension(b->name);
    if (!ea) ea = "";
    if (!eb) eb = "";
    int cmp = pal_stricmp(ea, eb);
    return cmp ? cmp : dir_entry_compare_name(a, b);
}

static int compare_protection(const dir_entry_t *a, const dir_entry_t *b)
{
    if (a->permissions != b->permissions)
        return (a->permissions < b->permissions) ? -1 : 1;
    return dir_entry_compare_name(a, b);
}

static int compare_comment(const dir_entry_t *a, const dir_entry_t *b)
{
    const char *ca = a->comment ? a->comment : "";
    const char *cb = b->comment ? b->comment : "";
    int cmp = pal_stricmp(ca, cb);
    return cmp ? cmp : dir_entry_compare_name(a, b);
}

/* Comparator lookup table */
static entry_compare_fn sort_functions[SORT_MAX] = {
    [SORT_NAME]       = dir_entry_compare_name,
    [SORT_SIZE]       = dir_entry_compare_size,
    [SORT_PROTECTION] = compare_protection,
    [SORT_DATE]       = dir_entry_compare_date,
    [SORT_COMMENT]    = compare_comment,
    [SORT_TYPE]       = dir_entry_compare_type,
    [SORT_EXTENSION]  = dir_entry_compare_extension,
};

entry_compare_fn dir_entry_get_comparator(sort_field_t field)
{
    if (field >= 0 && field < SORT_MAX)
        return sort_functions[field];
    return dir_entry_compare_name;
}
