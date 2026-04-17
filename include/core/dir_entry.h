/*
 * iDOpus — Core: Directory Entry
 *
 * Represents a single file/directory in a listing.
 * Based on the original DOpus 5 DirEntry/DirNode structures,
 * modernized for macOS (POSIX types, no Amiga tags, UTF-8 names).
 */

#ifndef DIR_ENTRY_H
#define DIR_ENTRY_H

#include <stdbool.h>
#include <stdint.h>
#include <time.h>
#include "pal/pal_lists.h"

/* Entry types (mirrors original semantics) */
typedef enum {
    ENTRY_FILE      = -1,
    ENTRY_DEVICE    =  0,
    ENTRY_DIRECTORY =  1,
} dir_entry_type_t;

/* Entry flags */
enum {
    ENTF_SELECTED   = (1 << 0),
    ENTF_HIDDEN     = (1 << 1),
    ENTF_LINK       = (1 << 2),
    ENTF_READONLY   = (1 << 3),
};

/* Sort fields */
typedef enum {
    SORT_NAME       = 0,
    SORT_SIZE       = 1,
    SORT_PROTECTION = 2,
    SORT_DATE       = 3,
    SORT_COMMENT    = 4,
    SORT_TYPE       = 5,    /* filetype description */
    SORT_EXTENSION  = 6,    /* added for macOS (not in original) */
    SORT_MAX
} sort_field_t;

/* Sort flags */
enum {
    SORTF_REVERSE = (1 << 0),
};

/* File separation */
typedef enum {
    SEPARATE_MIX        = 0,
    SEPARATE_DIRS_FIRST = 1,
    SEPARATE_FILES_FIRST= 2,
} separation_t;

/* Sort format (how a buffer is sorted) */
typedef struct {
    sort_field_t    field;
    uint8_t         flags;          /* SORTF_REVERSE, etc. */
    separation_t    separation;
} sort_format_t;

/* --- Directory Entry --- */

typedef struct dir_entry {
    pal_node_t      node;           /* linkage in buffer's entry list */
    dir_entry_type_t type;
    uint16_t        flags;          /* ENTF_* */

    char           *name;           /* file/directory name (heap-allocated, UTF-8) */
    uint64_t        size;           /* file size in bytes */
    time_t          date_modified;
    time_t          date_created;
    uint32_t        permissions;    /* POSIX mode bits */

    char           *comment;        /* optional comment (xattr or NULL) */
    char           *filetype_desc;  /* optional filetype description (NULL until resolved) */
    char           *owner;          /* optional owner name */
    char           *group;          /* optional group name */

    uint8_t         name_len;       /* cached strlen(name) */
    uint8_t         colour;         /* display colour index */
    void           *userdata;       /* arbitrary user data */
} dir_entry_t;

/* --- Entry lifecycle --- */

dir_entry_t *dir_entry_create(const char *name, uint64_t size,
                               dir_entry_type_t type, time_t date,
                               uint32_t permissions);
dir_entry_t *dir_entry_copy(const dir_entry_t *src);
void         dir_entry_free(dir_entry_t *entry);

/* --- Entry accessors --- */

void dir_entry_set_comment(dir_entry_t *entry, const char *comment);
void dir_entry_set_filetype(dir_entry_t *entry, const char *desc);
bool dir_entry_is_dir(const dir_entry_t *entry);
bool dir_entry_is_selected(const dir_entry_t *entry);
void dir_entry_select(dir_entry_t *entry, bool selected);

/* --- Entry comparison (for sorting) --- */

typedef int (*entry_compare_fn)(const dir_entry_t *a, const dir_entry_t *b);

entry_compare_fn dir_entry_get_comparator(sort_field_t field);
int dir_entry_compare_name(const dir_entry_t *a, const dir_entry_t *b);
int dir_entry_compare_size(const dir_entry_t *a, const dir_entry_t *b);
int dir_entry_compare_date(const dir_entry_t *a, const dir_entry_t *b);
int dir_entry_compare_type(const dir_entry_t *a, const dir_entry_t *b);
int dir_entry_compare_extension(const dir_entry_t *a, const dir_entry_t *b);

#endif /* DIR_ENTRY_H */
