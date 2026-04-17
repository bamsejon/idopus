/*
 * iDOpus — Platform Abstraction Layer: File System
 *
 * Replaces AmigaDOS file operations:
 *   Lock/UnLock, Examine/ExNext, Open/Close/Read/Write/Seek,
 *   FilePart/PathPart/AddPart, ParsePattern/MatchPattern,
 *   DeleteFile, Rename, CreateDir, SetProtection, SetComment,
 *   SetFileDate, NameFromLock, ParentDir, CurrentDir
 *
 * macOS implementation: POSIX (opendir/readdir/stat) + Foundation
 */

#ifndef PAL_FILE_H
#define PAL_FILE_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <time.h>

/* --- File info (replaces FileInfoBlock) --- */

typedef enum {
    PAL_FILE_TYPE_FILE,
    PAL_FILE_TYPE_DIR,
    PAL_FILE_TYPE_LINK,
    PAL_FILE_TYPE_OTHER,
} pal_file_type_t;

typedef struct {
    char             name[1024];
    char             path[4096];       /* full path */
    pal_file_type_t  type;
    uint64_t         size;
    time_t           date_modified;
    time_t           date_created;
    time_t           date_accessed;
    uint32_t         permissions;      /* POSIX mode bits */
    bool             hidden;
    bool             readonly;
    char             comment[256];     /* extended attribute on macOS */
} pal_fileinfo_t;

/* --- Directory scanning (replaces Lock/Examine/ExNext) --- */

typedef struct pal_dir pal_dir_t;

pal_dir_t    *pal_dir_open(const char *path);
bool          pal_dir_next(pal_dir_t *dir, pal_fileinfo_t *info);
void          pal_dir_close(pal_dir_t *dir);

/* --- File info (replaces Examine on a single file) --- */

bool pal_file_stat(const char *path, pal_fileinfo_t *info);
bool pal_file_exists(const char *path);
bool pal_file_is_dir(const char *path);

/* --- File operations (replaces DeleteFile, Rename, CreateDir, etc.) --- */

bool pal_file_delete(const char *path);
bool pal_file_rename(const char *old_path, const char *new_path);
bool pal_file_copy(const char *src, const char *dst);
bool pal_file_move(const char *src, const char *dst);
bool pal_dir_create(const char *path);
bool pal_dir_create_recursive(const char *path);

/* --- Path manipulation (replaces FilePart/PathPart/AddPart) --- */

const char *pal_path_filename(const char *path);       /* "foo/bar.txt" → "bar.txt" */
void        pal_path_parent(const char *path, char *out, size_t out_size);
void        pal_path_join(const char *dir, const char *name, char *out, size_t out_size);
const char *pal_path_extension(const char *path);      /* ".txt" */
bool        pal_path_is_absolute(const char *path);

/* --- Pattern matching (replaces ParsePattern/MatchPattern) --- */

bool pal_path_match(const char *pattern, const char *name);  /* fnmatch-style */

/* --- Volume/mount enumeration (replaces DosList/device list) --- */

typedef struct {
    char    name[256];
    char    mount_point[4096];
    char    filesystem[64];
    uint64_t total_bytes;
    uint64_t free_bytes;
    bool    removable;
    bool    network;
} pal_volume_t;

int  pal_volumes_list(pal_volume_t *volumes, int max_count);

/* --- File I/O (replaces AmigaDOS Open/Read/Write/Seek) --- */
/* Using standard POSIX FILE* or file descriptors directly is fine.
   This thin wrapper exists only for consistency and future buffering. */

typedef struct pal_file pal_file_t;

pal_file_t *pal_file_open(const char *path, const char *mode);
void        pal_file_close(pal_file_t *f);
size_t      pal_file_read(pal_file_t *f, void *buf, size_t size);
size_t      pal_file_write(pal_file_t *f, const void *buf, size_t size);
int64_t     pal_file_seek(pal_file_t *f, int64_t offset, int whence);
int64_t     pal_file_tell(pal_file_t *f);
uint64_t    pal_file_size(pal_file_t *f);

#endif /* PAL_FILE_H */
