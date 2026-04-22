/*
 * iDOpus — Platform Abstraction Layer: Strings
 *
 * Replaces Amiga string utilities + lsprintf.asm:
 *   lsprintf (RawDoFmt wrapper), Stricmp, various custom string ops
 *
 * Also provides safe string operations for the port.
 */

#ifndef PAL_STRINGS_H
#define PAL_STRINGS_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

/* --- Safe string operations --- */

size_t pal_strlcpy(char *dst, const char *src, size_t size);
size_t pal_strlcat(char *dst, const char *src, size_t size);

/* --- Case-insensitive comparison (replaces Stricmp) --- */

int  pal_stricmp(const char *a, const char *b);
int  pal_strnicmp(const char *a, const char *b, size_t n);

/* --- Formatting (replaces lsprintf) --- */

#if defined(__GNUC__) || defined(__clang__)
#define PAL_PRINTF_FMT(a, b) __attribute__((format(printf, a, b)))
#else
#define PAL_PRINTF_FMT(a, b)
#endif

int  pal_sprintf(char *buf, size_t size, const char *fmt, ...)
     PAL_PRINTF_FMT(3, 4);

/* --- Utility --- */

char *pal_strdup(const char *s);
bool  pal_str_has_suffix(const char *s, const char *suffix);
bool  pal_str_has_prefix(const char *s, const char *prefix);
void  pal_str_to_upper(char *s);
void  pal_str_to_lower(char *s);
char *pal_str_trim(char *s);

/* --- Number formatting --- */

void pal_format_size(uint64_t bytes, char *buf, size_t buf_size);  /* "1.4 MB" */
void pal_format_date(long timestamp, char *buf, size_t buf_size);  /* localized */

#endif /* PAL_STRINGS_H */
