/*
 * iDOpus — PAL File System implementation (Windows)
 *
 * Covers the same pal_file.h surface as the POSIX implementation.
 * Paths in the pal_* API are UTF-8; we convert to UTF-16 and call
 * the W variants of the Win32 APIs so non-ASCII paths work.
 */

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shellapi.h>
#include <direct.h>
#include <sys/stat.h>

#include "pal/pal_file.h"
#include "pal/pal_strings.h"
#include "pal/pal_memory.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/* --- UTF-8 ↔ UTF-16 helpers (caller frees) --- */

static wchar_t *utf8_to_wide(const char *s)
{
    if (!s) return NULL;
    int len = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
    if (len <= 0) return NULL;
    wchar_t *w = (wchar_t *)pal_alloc((size_t)len * sizeof(wchar_t));
    if (!w) return NULL;
    if (MultiByteToWideChar(CP_UTF8, 0, s, -1, w, len) <= 0) {
        pal_free(w);
        return NULL;
    }
    return w;
}

static bool wide_to_utf8(const wchar_t *w, char *out, size_t out_size)
{
    if (!w || !out || out_size == 0) return false;
    int need = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (need <= 0 || (size_t)need > out_size) return false;
    return WideCharToMultiByte(CP_UTF8, 0, w, -1, out, (int)out_size, NULL, NULL) > 0;
}

/* Windows treats both '/' and '\' as separators; we normalise to '/' when
 * exposing paths through pal_*, but the file I/O APIs accept either. */

/* --- Directory scanning --- */

struct pal_dir {
    HANDLE  handle;     /* INVALID_HANDLE_VALUE until first next */
    wchar_t pattern[4096];  /* <path>\* */
    WIN32_FIND_DATAW first_data;
    bool    have_first;
    char    path[4096];
};

pal_dir_t *pal_dir_open(const char *path)
{
    if (!path) return NULL;
    pal_dir_t *dir = pal_alloc_clear(sizeof(pal_dir_t));
    if (!dir) return NULL;

    pal_strlcpy(dir->path, path, sizeof(dir->path));

    /* Build "path\*" wide-char pattern */
    wchar_t *w = utf8_to_wide(path);
    if (!w) { pal_free(dir); return NULL; }
    size_t wlen = wcslen(w);
    if (wlen + 3 >= (sizeof(dir->pattern) / sizeof(wchar_t))) {
        pal_free(w);
        pal_free(dir);
        return NULL;
    }
    wcscpy(dir->pattern, w);
    pal_free(w);
    if (wlen > 0 && dir->pattern[wlen-1] != L'\\' && dir->pattern[wlen-1] != L'/')
        dir->pattern[wlen++] = L'\\';
    dir->pattern[wlen++] = L'*';
    dir->pattern[wlen]   = L'\0';

    dir->handle = FindFirstFileW(dir->pattern, &dir->first_data);
    if (dir->handle == INVALID_HANDLE_VALUE) {
        pal_free(dir);
        return NULL;
    }
    dir->have_first = true;
    return dir;
}

static void fill_info_from_find(const char *fullpath, const WIN32_FIND_DATAW *fd,
                                 pal_fileinfo_t *info)
{
    /* Convert file name to UTF-8 for info->name */
    wide_to_utf8(fd->cFileName, info->name, sizeof(info->name));
    pal_strlcpy(info->path, fullpath, sizeof(info->path));

    ULARGE_INTEGER sz;
    sz.LowPart  = fd->nFileSizeLow;
    sz.HighPart = fd->nFileSizeHigh;
    info->size = (uint64_t)sz.QuadPart;

    /* FILETIME → Unix time (100-ns intervals since 1601, minus epoch offset) */
    #define FT2UNIX(ft) \
        (long)((((ULONGLONG)(ft).dwHighDateTime << 32 | (ft).dwLowDateTime) \
                - 116444736000000000ULL) / 10000000ULL)
    info->date_modified = FT2UNIX(fd->ftLastWriteTime);
    info->date_created  = FT2UNIX(fd->ftCreationTime);
    info->date_accessed = FT2UNIX(fd->ftLastAccessTime);
    #undef FT2UNIX

    /* Windows doesn't expose POSIX mode bits; synthesise a plausible set */
    bool is_ro = (fd->dwFileAttributes & FILE_ATTRIBUTE_READONLY) != 0;
    info->permissions = is_ro ? 0444 : 0644;
    info->hidden   = (fd->dwFileAttributes & FILE_ATTRIBUTE_HIDDEN) != 0
                     || info->name[0] == '.';
    info->readonly = is_ro;
    info->comment[0] = '\0';

    if (fd->dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)
        info->type = PAL_FILE_TYPE_LINK;
    else if (fd->dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
        info->type = PAL_FILE_TYPE_DIR;
    else
        info->type = PAL_FILE_TYPE_FILE;
}

bool pal_dir_next(pal_dir_t *dir, pal_fileinfo_t *info)
{
    if (!dir || !info || dir->handle == INVALID_HANDLE_VALUE) return false;

    WIN32_FIND_DATAW fd;
    for (;;) {
        if (dir->have_first) {
            fd = dir->first_data;
            dir->have_first = false;
        } else if (!FindNextFileW(dir->handle, &fd)) {
            return false;
        }

        /* Skip "." and ".." */
        if (fd.cFileName[0] == L'.' &&
            (fd.cFileName[1] == L'\0' ||
             (fd.cFileName[1] == L'.' && fd.cFileName[2] == L'\0'))) {
            continue;
        }

        char name_utf8[260];
        if (!wide_to_utf8(fd.cFileName, name_utf8, sizeof(name_utf8)))
            continue;

        char fullpath[4096];
        pal_path_join(dir->path, name_utf8, fullpath, sizeof(fullpath));
        fill_info_from_find(fullpath, &fd, info);
        return true;
    }
}

void pal_dir_close(pal_dir_t *dir)
{
    if (!dir) return;
    if (dir->handle != INVALID_HANDLE_VALUE) FindClose(dir->handle);
    pal_free(dir);
}

/* --- File info --- */

bool pal_file_stat(const char *path, pal_fileinfo_t *info)
{
    if (!path || !info) return false;
    wchar_t *w = utf8_to_wide(path);
    if (!w) return false;

    WIN32_FILE_ATTRIBUTE_DATA a;
    BOOL ok = GetFileAttributesExW(w, GetFileExInfoStandard, &a);
    pal_free(w);
    if (!ok) return false;

    /* Adapt WIN32_FILE_ATTRIBUTE_DATA to WIN32_FIND_DATAW so we can reuse
     * fill_info_from_find. cFileName must be the base name. */
    WIN32_FIND_DATAW fd = {0};
    fd.dwFileAttributes = a.dwFileAttributes;
    fd.ftCreationTime   = a.ftCreationTime;
    fd.ftLastAccessTime = a.ftLastAccessTime;
    fd.ftLastWriteTime  = a.ftLastWriteTime;
    fd.nFileSizeHigh    = a.nFileSizeHigh;
    fd.nFileSizeLow     = a.nFileSizeLow;

    const char *name = pal_path_filename(path);
    if (!name) name = path;
    wchar_t *wn = utf8_to_wide(name);
    if (wn) {
        wcsncpy(fd.cFileName, wn, (sizeof(fd.cFileName) / sizeof(wchar_t)) - 1);
        pal_free(wn);
    }
    fill_info_from_find(path, &fd, info);
    return true;
}

bool pal_file_exists(const char *path)
{
    if (!path) return false;
    wchar_t *w = utf8_to_wide(path);
    if (!w) return false;
    DWORD attrs = GetFileAttributesW(w);
    pal_free(w);
    return attrs != INVALID_FILE_ATTRIBUTES;
}

bool pal_file_is_dir(const char *path)
{
    if (!path) return false;
    wchar_t *w = utf8_to_wide(path);
    if (!w) return false;
    DWORD attrs = GetFileAttributesW(w);
    pal_free(w);
    return attrs != INVALID_FILE_ATTRIBUTES
        && (attrs & FILE_ATTRIBUTE_DIRECTORY);
}

/* --- File operations --- */

bool pal_file_delete(const char *path)
{
    if (!path) return false;
    wchar_t *w = utf8_to_wide(path);
    if (!w) return false;

    /* Strip read-only attribute so delete can succeed */
    DWORD attrs = GetFileAttributesW(w);
    if (attrs != INVALID_FILE_ATTRIBUTES) {
        if (attrs & FILE_ATTRIBUTE_READONLY)
            SetFileAttributesW(w, attrs & ~FILE_ATTRIBUTE_READONLY);

        BOOL ok;
        if (attrs & FILE_ATTRIBUTE_DIRECTORY)
            ok = RemoveDirectoryW(w);
        else
            ok = DeleteFileW(w);
        pal_free(w);
        return ok != 0;
    }
    pal_free(w);
    return false;
}

bool pal_file_rename(const char *old_path, const char *new_path)
{
    if (!old_path || !new_path) return false;
    wchar_t *wo = utf8_to_wide(old_path);
    wchar_t *wn = utf8_to_wide(new_path);
    BOOL ok = FALSE;
    if (wo && wn) {
        ok = MoveFileExW(wo, wn, MOVEFILE_REPLACE_EXISTING);
    }
    pal_free(wo);
    pal_free(wn);
    return ok != 0;
}

bool pal_file_copy(const char *src, const char *dst)
{
    if (!src || !dst) return false;
    wchar_t *ws = utf8_to_wide(src);
    wchar_t *wd = utf8_to_wide(dst);
    BOOL ok = FALSE;
    if (ws && wd) {
        /* FALSE = overwrite if exists */
        ok = CopyFileW(ws, wd, FALSE);
    }
    pal_free(ws);
    pal_free(wd);
    return ok != 0;
}

bool pal_file_move(const char *src, const char *dst)
{
    if (!src || !dst) return false;
    wchar_t *ws = utf8_to_wide(src);
    wchar_t *wd = utf8_to_wide(dst);
    BOOL ok = FALSE;
    if (ws && wd) {
        ok = MoveFileExW(ws, wd,
                         MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED);
    }
    pal_free(ws);
    pal_free(wd);
    return ok != 0;
}

bool pal_dir_create(const char *path)
{
    if (!path) return false;
    wchar_t *w = utf8_to_wide(path);
    if (!w) return false;
    BOOL ok = CreateDirectoryW(w, NULL);
    pal_free(w);
    return ok != 0;
}

bool pal_dir_create_recursive(const char *path)
{
    if (!path) return false;
    char tmp[4096];
    pal_strlcpy(tmp, path, sizeof(tmp));

    /* Normalise separators */
    for (char *p = tmp; *p; p++) if (*p == '\\') *p = '/';

    /* Skip drive prefix ("C:/") or UNC ("//host/share/") */
    char *p = tmp;
    if (p[0] && p[1] == ':' && p[2] == '/') p += 3;
    else if (p[0] == '/' && p[1] == '/') {
        p += 2;
        /* skip host + share */
        int slashes = 0;
        while (*p && slashes < 2) { if (*p == '/') slashes++; if (slashes < 2) p++; }
        if (*p == '/') p++;
    } else if (*p == '/') {
        p++;
    }

    for (; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            wchar_t *w = utf8_to_wide(tmp);
            if (w) { CreateDirectoryW(w, NULL); pal_free(w); }
            *p = '/';
        }
    }
    wchar_t *w = utf8_to_wide(tmp);
    bool ok = false;
    if (w) {
        ok = CreateDirectoryW(w, NULL) != 0
             || GetLastError() == ERROR_ALREADY_EXISTS;
        pal_free(w);
    }
    return ok;
}

/* --- Path manipulation --- */

const char *pal_path_filename(const char *path)
{
    if (!path) return NULL;
    const char *last = path;
    for (const char *p = path; *p; p++) {
        if (*p == '/' || *p == '\\') last = p + 1;
    }
    return last;
}

void pal_path_parent(const char *path, char *out, size_t out_size)
{
    if (!path || !out) return;
    char tmp[4096];
    pal_strlcpy(tmp, path, sizeof(tmp));

    /* Strip trailing separator (unless it's the root, e.g. "C:/" or "/") */
    size_t len = strlen(tmp);
    if (len > 3 && (tmp[len-1] == '/' || tmp[len-1] == '\\'))
        tmp[len-1] = '\0';

    /* Find last separator */
    char *last = NULL;
    for (char *p = tmp; *p; p++)
        if (*p == '/' || *p == '\\') last = p;

    if (last) {
        /* Keep "C:/" intact */
        if (last == tmp + 2 && tmp[1] == ':') {
            last[1] = '\0';
        } else if (last == tmp) {
            last[1] = '\0';
        } else {
            *last = '\0';
        }
    }
    pal_strlcpy(out, tmp, out_size);
}

void pal_path_join(const char *dir, const char *name, char *out, size_t out_size)
{
    if (!dir || !name || !out) return;
    size_t dlen = strlen(dir);
    bool has_sep = (dlen > 0 && (dir[dlen-1] == '/' || dir[dlen-1] == '\\'));
    if (has_sep)
        pal_sprintf(out, out_size, "%s%s", dir, name);
    else
        pal_sprintf(out, out_size, "%s/%s", dir, name);
}

const char *pal_path_extension(const char *path)
{
    const char *name = pal_path_filename(path);
    if (!name) return NULL;
    const char *dot = strrchr(name, '.');
    return dot ? dot : NULL;
}

bool pal_path_is_absolute(const char *path)
{
    if (!path || !*path) return false;
    /* Drive letter: "C:\" or "C:/" */
    if (((path[0] >= 'A' && path[0] <= 'Z') || (path[0] >= 'a' && path[0] <= 'z'))
        && path[1] == ':'
        && (path[2] == '/' || path[2] == '\\'))
        return true;
    /* UNC: "\\host\share" */
    if ((path[0] == '/' || path[0] == '\\') && (path[1] == '/' || path[1] == '\\'))
        return true;
    return false;
}

/* --- Pattern matching --- */

static bool wild_match(const char *pat, const char *s, bool icase)
{
    for (; *pat; pat++) {
        if (*pat == '*') {
            /* Collapse consecutive stars */
            while (*pat == '*') pat++;
            if (!*pat) return true;
            for (const char *q = s; *q; q++)
                if (wild_match(pat, q, icase)) return true;
            /* also allow zero chars */
            return wild_match(pat, s + strlen(s), icase);
        }
        if (!*s) return false;
        if (*pat == '?') {
            s++;
            continue;
        }
        char a = *pat, b = *s;
        if (icase) {
            if (a >= 'A' && a <= 'Z') a = (char)(a - 'A' + 'a');
            if (b >= 'A' && b <= 'Z') b = (char)(b - 'A' + 'a');
        }
        if (a != b) return false;
        s++;
    }
    return !*s;
}

bool pal_path_match(const char *pattern, const char *name)
{
    if (!pattern || !name) return false;
    return wild_match(pattern, name, /* icase */ true);
}

/* --- Volume enumeration --- */

int pal_volumes_list(pal_volume_t *volumes, int max_count)
{
    if (!volumes || max_count <= 0) return 0;

    DWORD drives = GetLogicalDrives();
    int count = 0;
    for (int i = 0; i < 26 && count < max_count; i++) {
        if (!(drives & (1u << i))) continue;

        char root[4] = { (char)('A' + i), ':', '\\', '\0' };
        UINT type = GetDriveTypeA(root);
        if (type == DRIVE_NO_ROOT_DIR || type == DRIVE_UNKNOWN) continue;

        pal_volume_t *v = &volumes[count++];
        /* Mount point exposed as "C:/" so the rest of the code can concatenate. */
        pal_sprintf(v->mount_point, sizeof(v->mount_point), "%c:/", 'A' + i);

        /* Volume name (label) */
        char label[MAX_PATH + 1] = {0};
        char fs[MAX_PATH + 1] = {0};
        DWORD serial = 0, maxlen = 0, flags = 0;
        if (GetVolumeInformationA(root, label, sizeof(label), &serial,
                                   &maxlen, &flags, fs, sizeof(fs))) {
            pal_strlcpy(v->filesystem, fs, sizeof(v->filesystem));
            if (label[0])
                pal_sprintf(v->name, sizeof(v->name), "%s (%c:)", label, 'A' + i);
            else
                pal_sprintf(v->name, sizeof(v->name), "%c:", 'A' + i);
        } else {
            pal_strlcpy(v->filesystem, "?", sizeof(v->filesystem));
            pal_sprintf(v->name, sizeof(v->name), "%c:", 'A' + i);
        }

        /* Free/total space */
        ULARGE_INTEGER free_to_caller, total, total_free;
        if (GetDiskFreeSpaceExA(root, &free_to_caller, &total, &total_free)) {
            v->total_bytes = (uint64_t)total.QuadPart;
            v->free_bytes  = (uint64_t)free_to_caller.QuadPart;
        } else {
            v->total_bytes = 0;
            v->free_bytes  = 0;
        }

        v->removable = (type == DRIVE_REMOVABLE || type == DRIVE_CDROM);
        v->network   = (type == DRIVE_REMOTE);
    }
    return count;
}

/* --- File I/O (portable C stdio) --- */

struct pal_file {
    FILE *fp;
};

pal_file_t *pal_file_open(const char *path, const char *mode)
{
    if (!path || !mode) return NULL;
    wchar_t *wp = utf8_to_wide(path);
    wchar_t *wm = utf8_to_wide(mode);
    FILE *fp = NULL;
    if (wp && wm) fp = _wfopen(wp, wm);
    pal_free(wp);
    pal_free(wm);
    if (!fp) return NULL;

    pal_file_t *f = pal_alloc(sizeof(pal_file_t));
    if (!f) { fclose(fp); return NULL; }
    f->fp = fp;
    return f;
}

void pal_file_close(pal_file_t *f)
{
    if (!f) return;
    if (f->fp) fclose(f->fp);
    pal_free(f);
}

size_t pal_file_read(pal_file_t *f, void *buf, size_t size)
{
    return (f && f->fp) ? fread(buf, 1, size, f->fp) : 0;
}

size_t pal_file_write(pal_file_t *f, const void *buf, size_t size)
{
    return (f && f->fp) ? fwrite(buf, 1, size, f->fp) : 0;
}

int64_t pal_file_seek(pal_file_t *f, int64_t offset, int whence)
{
    if (!f || !f->fp) return -1;
    return _fseeki64(f->fp, offset, whence);
}

int64_t pal_file_tell(pal_file_t *f)
{
    return (f && f->fp) ? _ftelli64(f->fp) : -1;
}

uint64_t pal_file_size(pal_file_t *f)
{
    if (!f || !f->fp) return 0;
    int64_t pos = _ftelli64(f->fp);
    _fseeki64(f->fp, 0, SEEK_END);
    int64_t size = _ftelli64(f->fp);
    _fseeki64(f->fp, pos, SEEK_SET);
    return (uint64_t)size;
}
