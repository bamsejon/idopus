/*
 * iDOpus — PAL Strings implementation
 */

#include "pal/pal_strings.h"
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdarg.h>
#include <stdio.h>
#include <ctype.h>
#include <time.h>

size_t pal_strlcpy(char *dst, const char *src, size_t size)
{
    return strlcpy(dst, src, size);  /* available on macOS */
}

size_t pal_strlcat(char *dst, const char *src, size_t size)
{
    return strlcat(dst, src, size);
}

int pal_stricmp(const char *a, const char *b)
{
    return strcasecmp(a, b);
}

int pal_strnicmp(const char *a, const char *b, size_t n)
{
    return strncasecmp(a, b, n);
}

int pal_sprintf(char *buf, size_t size, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int ret = vsnprintf(buf, size, fmt, ap);
    va_end(ap);
    return ret;
}

char *pal_strdup(const char *s)
{
    return s ? strdup(s) : NULL;
}

bool pal_str_has_suffix(const char *s, const char *suffix)
{
    if (!s || !suffix) return false;
    size_t slen = strlen(s), sfxlen = strlen(suffix);
    if (sfxlen > slen) return false;
    return strcasecmp(s + slen - sfxlen, suffix) == 0;
}

bool pal_str_has_prefix(const char *s, const char *prefix)
{
    if (!s || !prefix) return false;
    return strncasecmp(s, prefix, strlen(prefix)) == 0;
}

void pal_str_to_upper(char *s)
{
    for (; s && *s; s++) *s = toupper((unsigned char)*s);
}

void pal_str_to_lower(char *s)
{
    for (; s && *s; s++) *s = tolower((unsigned char)*s);
}

char *pal_str_trim(char *s)
{
    if (!s) return NULL;
    while (isspace((unsigned char)*s)) s++;
    if (*s == '\0') return s;
    char *end = s + strlen(s) - 1;
    while (end > s && isspace((unsigned char)*end)) end--;
    end[1] = '\0';
    return s;
}

void pal_format_size(uint64_t bytes, char *buf, size_t buf_size)
{
    if (bytes < 1024)
        snprintf(buf, buf_size, "%llu B", bytes);
    else if (bytes < 1024 * 1024)
        snprintf(buf, buf_size, "%.1f KB", bytes / 1024.0);
    else if (bytes < 1024ULL * 1024 * 1024)
        snprintf(buf, buf_size, "%.1f MB", bytes / (1024.0 * 1024));
    else
        snprintf(buf, buf_size, "%.2f GB", bytes / (1024.0 * 1024 * 1024));
}

void pal_format_date(long timestamp, char *buf, size_t buf_size)
{
    time_t t = (time_t)timestamp;
    struct tm *tm = localtime(&t);
    if (tm)
        strftime(buf, buf_size, "%Y-%m-%d %H:%M", tm);
    else
        pal_strlcpy(buf, "???", buf_size);
}
