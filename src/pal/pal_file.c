/*
 * iDOpus — PAL File System implementation (macOS/POSIX)
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE  /* needed on glibc for FNM_CASEFOLD */
#endif

#include "pal/pal_file.h"
#include "pal/pal_strings.h"
#include "pal/pal_memory.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>
#include <fnmatch.h>
#include <libgen.h>
#include <errno.h>

#ifdef __APPLE__
#include <sys/mount.h>
#include <copyfile.h>
#else
#include <mntent.h>
#endif

/* --- Directory scanning --- */

struct pal_dir {
    DIR  *dirp;
    char  path[4096];
};

pal_dir_t *pal_dir_open(const char *path)
{
    if (!path) return NULL;
    DIR *d = opendir(path);
    if (!d) return NULL;

    pal_dir_t *dir = pal_alloc_clear(sizeof(pal_dir_t));
    if (!dir) { closedir(d); return NULL; }
    dir->dirp = d;
    pal_strlcpy(dir->path, path, sizeof(dir->path));
    return dir;
}

static void fill_info_from_stat(const char *fullpath, const char *name,
                                 struct stat *st, pal_fileinfo_t *info)
{
    pal_strlcpy(info->name, name, sizeof(info->name));
    pal_strlcpy(info->path, fullpath, sizeof(info->path));
    info->size = st->st_size;
    info->date_modified = st->st_mtime;
#ifdef __APPLE__
    info->date_created = st->st_birthtime;  /* macOS-specific */
#else
    info->date_created = st->st_mtime;      /* Linux struct stat has no birthtime */
#endif
    info->date_accessed = st->st_atime;
    info->permissions = st->st_mode & 0777;
    info->hidden = (name[0] == '.');
    info->readonly = !(st->st_mode & S_IWUSR);
    info->comment[0] = '\0';

    if (S_ISDIR(st->st_mode))      info->type = PAL_FILE_TYPE_DIR;
    else if (S_ISLNK(st->st_mode)) info->type = PAL_FILE_TYPE_LINK;
    else if (S_ISREG(st->st_mode)) info->type = PAL_FILE_TYPE_FILE;
    else                            info->type = PAL_FILE_TYPE_OTHER;
}

bool pal_dir_next(pal_dir_t *dir, pal_fileinfo_t *info)
{
    if (!dir || !info) return false;
    struct dirent *ent;
    while ((ent = readdir(dir->dirp))) {
        if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0)
            continue;

        char fullpath[4096];
        pal_path_join(dir->path, ent->d_name, fullpath, sizeof(fullpath));

        struct stat st;
        if (lstat(fullpath, &st) != 0)
            continue;

        fill_info_from_stat(fullpath, ent->d_name, &st, info);
        return true;
    }
    return false;
}

void pal_dir_close(pal_dir_t *dir)
{
    if (!dir) return;
    if (dir->dirp) closedir(dir->dirp);
    pal_free(dir);
}

/* --- File info --- */

bool pal_file_stat(const char *path, pal_fileinfo_t *info)
{
    if (!path || !info) return false;
    struct stat st;
    if (lstat(path, &st) != 0) return false;
    const char *name = pal_path_filename(path);
    fill_info_from_stat(path, name ? name : path, &st, info);
    return true;
}

bool pal_file_exists(const char *path)
{
    return path && access(path, F_OK) == 0;
}

bool pal_file_is_dir(const char *path)
{
    struct stat st;
    return path && stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

/* --- File operations --- */

bool pal_file_delete(const char *path)
{
    if (!path) return false;
    if (pal_file_is_dir(path))
        return rmdir(path) == 0;
    return unlink(path) == 0;
}

bool pal_file_rename(const char *old_path, const char *new_path)
{
    return old_path && new_path && rename(old_path, new_path) == 0;
}

bool pal_file_copy(const char *src, const char *dst)
{
    if (!src || !dst) return false;
#ifdef __APPLE__
    /* macOS copyfile() handles metadata, xattrs, ACLs */
    return copyfile(src, dst, NULL, COPYFILE_ALL) == 0;
#else
    /* POSIX read/write loop. MVP only — xattrs/ACLs not preserved. */
    int s = open(src, O_RDONLY);
    if (s < 0) return false;
    struct stat st;
    if (fstat(s, &st) != 0) { close(s); return false; }
    int d = open(dst, O_WRONLY | O_CREAT | O_TRUNC, st.st_mode & 0777);
    if (d < 0) { close(s); return false; }
    char buf[65536];
    ssize_t n;
    bool ok = true;
    while ((n = read(s, buf, sizeof buf)) > 0) {
        ssize_t w = 0;
        while (w < n) {
            ssize_t k = write(d, buf + w, n - w);
            if (k <= 0) { ok = false; break; }
            w += k;
        }
        if (!ok) break;
    }
    if (n < 0) ok = false;
    close(s);
    close(d);
    if (!ok) unlink(dst);
    return ok;
#endif
}

bool pal_file_move(const char *src, const char *dst)
{
    /* Try rename first (atomic, same volume) */
    if (rename(src, dst) == 0) return true;
    /* Fall back to copy + delete */
    if (!pal_file_copy(src, dst)) return false;
    return pal_file_delete(src);
}

bool pal_dir_create(const char *path)
{
    return path && mkdir(path, 0755) == 0;
}

bool pal_dir_create_recursive(const char *path)
{
    if (!path) return false;
    char tmp[4096];
    pal_strlcpy(tmp, path, sizeof(tmp));
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            mkdir(tmp, 0755);  /* ignore errors on intermediate dirs */
            *p = '/';
        }
    }
    return mkdir(tmp, 0755) == 0 || errno == EEXIST;
}

/* --- Path manipulation --- */

const char *pal_path_filename(const char *path)
{
    if (!path) return NULL;
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

void pal_path_parent(const char *path, char *out, size_t out_size)
{
    if (!path || !out) return;
    char tmp[4096];
    pal_strlcpy(tmp, path, sizeof(tmp));
    /* Remove trailing slash */
    size_t len = strlen(tmp);
    if (len > 1 && tmp[len-1] == '/') tmp[len-1] = '\0';
    char *slash = strrchr(tmp, '/');
    if (slash) {
        if (slash == tmp) slash[1] = '\0';  /* root */
        else *slash = '\0';
    }
    pal_strlcpy(out, tmp, out_size);
}

void pal_path_join(const char *dir, const char *name, char *out, size_t out_size)
{
    if (!dir || !name || !out) return;
    size_t dlen = strlen(dir);
    if (dlen > 0 && dir[dlen-1] == '/')
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
    return path && path[0] == '/';
}

/* --- Pattern matching --- */

bool pal_path_match(const char *pattern, const char *name)
{
    if (!pattern || !name) return false;
    return fnmatch(pattern, name, FNM_CASEFOLD) == 0;
}

/* --- Volume enumeration --- */

int pal_volumes_list(pal_volume_t *volumes, int max_count)
{
#ifdef __APPLE__
    struct statfs *mounts;
    int n = getmntinfo(&mounts, MNT_NOWAIT);
    int count = 0;
    for (int i = 0; i < n && count < max_count; i++) {
        /* Skip pseudo-filesystems */
        if (strcmp(mounts[i].f_fstypename, "devfs") == 0) continue;
        if (strcmp(mounts[i].f_fstypename, "autofs") == 0) continue;

        pal_volume_t *v = &volumes[count++];
        pal_strlcpy(v->mount_point, mounts[i].f_mntonname, sizeof(v->mount_point));
        pal_strlcpy(v->filesystem, mounts[i].f_fstypename, sizeof(v->filesystem));
        /* Extract volume name from mount point */
        const char *name = pal_path_filename(mounts[i].f_mntonname);
        pal_strlcpy(v->name, (name && *name) ? name : "/", sizeof(v->name));
        v->total_bytes = (uint64_t)mounts[i].f_blocks * mounts[i].f_bsize;
        v->free_bytes = (uint64_t)mounts[i].f_bavail * mounts[i].f_bsize;
        v->removable = (mounts[i].f_flags & MNT_REMOVABLE) != 0;
        v->network = (strcmp(mounts[i].f_fstypename, "nfs") == 0 ||
                      strcmp(mounts[i].f_fstypename, "smbfs") == 0 ||
                      strcmp(mounts[i].f_fstypename, "afpfs") == 0);
    }
    return count;
#else
    /* Linux: parse /proc/mounts; include block-device and network mounts only. */
    FILE *fp = setmntent("/proc/mounts", "r");
    if (!fp) return 0;
    struct mntent *m;
    int count = 0;
    while ((m = getmntent(fp)) && count < max_count) {
        bool is_dev = (strncmp(m->mnt_fsname, "/dev/", 5) == 0);
        bool is_net = (strcmp(m->mnt_type, "nfs")    == 0 ||
                       strcmp(m->mnt_type, "nfs4")   == 0 ||
                       strcmp(m->mnt_type, "cifs")   == 0 ||
                       strcmp(m->mnt_type, "smbfs")  == 0);
        if (!is_dev && !is_net) continue;

        pal_volume_t *v = &volumes[count++];
        pal_strlcpy(v->mount_point, m->mnt_dir,  sizeof(v->mount_point));
        pal_strlcpy(v->filesystem,  m->mnt_type, sizeof(v->filesystem));
        const char *name = pal_path_filename(m->mnt_dir);
        pal_strlcpy(v->name, (name && *name) ? name : "/", sizeof(v->name));

        struct statvfs sf;
        if (statvfs(m->mnt_dir, &sf) == 0) {
            v->total_bytes = (uint64_t)sf.f_blocks * sf.f_frsize;
            v->free_bytes  = (uint64_t)sf.f_bavail * sf.f_frsize;
        } else {
            v->total_bytes = 0;
            v->free_bytes  = 0;
        }
        v->removable = false;   /* no reliable detection without udev */
        v->network   = is_net;
    }
    endmntent(fp);
    return count;
#endif
}

/* --- File I/O --- */

struct pal_file {
    FILE *fp;
};

pal_file_t *pal_file_open(const char *path, const char *mode)
{
    if (!path || !mode) return NULL;
    FILE *fp = fopen(path, mode);
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
    return fseeko(f->fp, offset, whence);
}

int64_t pal_file_tell(pal_file_t *f)
{
    return (f && f->fp) ? ftello(f->fp) : -1;
}

uint64_t pal_file_size(pal_file_t *f)
{
    if (!f || !f->fp) return 0;
    int64_t pos = ftello(f->fp);
    fseeko(f->fp, 0, SEEK_END);
    int64_t size = ftello(f->fp);
    fseeko(f->fp, pos, SEEK_SET);
    return (uint64_t)size;
}
