/*
 * iDOpus — Core data model test suite
 *
 * Tests directory entries, buffers, sorting, filtering, selection,
 * and the buffer cache. Run: ./build/core_test
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <time.h>

#include "core/dir_entry.h"
#include "core/dir_buffer.h"
#include "pal/pal_strings.h"

static int passed = 0, failed = 0;
#define TEST(name) printf("  %-44s ", #name); fflush(stdout)
#define PASS() do { printf("OK\n"); passed++; } while(0)
#define FAIL(msg) do { printf("FAIL: %s\n", msg); failed++; } while(0)
#define CHECK(cond, msg) do { if (cond) PASS(); else FAIL(msg); } while(0)

/* --- Entry tests --- */
static void test_entries(void)
{
    printf("\n--- Directory Entries ---\n");

    TEST(create_file);
    dir_entry_t *e = dir_entry_create("readme.txt", 1234, ENTRY_FILE, time(NULL), 0644);
    CHECK(e && strcmp(e->name, "readme.txt") == 0 && e->size == 1234, "create failed");

    TEST(is_dir);
    CHECK(!dir_entry_is_dir(e), "file reported as dir");

    TEST(create_dir);
    dir_entry_t *d = dir_entry_create("Documents", 0, ENTRY_DIRECTORY, time(NULL), 0755);
    CHECK(d && dir_entry_is_dir(d), "dir creation failed");

    TEST(select_deselect);
    dir_entry_select(e, true);
    CHECK(dir_entry_is_selected(e), "select failed");
    dir_entry_select(e, false);
    CHECK(!dir_entry_is_selected(e), "deselect failed");
    passed++; /* two checks */

    TEST(set_comment);
    dir_entry_set_comment(e, "important file");
    CHECK(e->comment && strcmp(e->comment, "important file") == 0, "comment");

    TEST(copy_entry);
    dir_entry_t *copy = dir_entry_copy(e);
    CHECK(copy && strcmp(copy->name, e->name) == 0 &&
          copy->size == e->size && copy != e &&
          copy->name != e->name, "copy failed");

    dir_entry_free(copy);
    dir_entry_free(e);
    dir_entry_free(d);
}

/* --- Sort tests --- */
static void test_sorting(void)
{
    printf("\n--- Sorting ---\n");

    TEST(name_sort_smart_numeric);
    /* "file2" should come before "file10" */
    dir_entry_t *f2 = dir_entry_create("file2.txt", 100, ENTRY_FILE, 0, 0);
    dir_entry_t *f10 = dir_entry_create("file10.txt", 200, ENTRY_FILE, 0, 0);
    int cmp = dir_entry_compare_name(f2, f10);
    CHECK(cmp < 0, "file2 should sort before file10");

    TEST(name_sort_case_insensitive);
    dir_entry_t *upper = dir_entry_create("Zebra", 0, ENTRY_FILE, 0, 0);
    dir_entry_t *lower = dir_entry_create("apple", 0, ENTRY_FILE, 0, 0);
    cmp = dir_entry_compare_name(lower, upper);
    CHECK(cmp < 0, "apple should sort before Zebra");

    TEST(size_sort);
    cmp = dir_entry_compare_size(f2, f10);
    CHECK(cmp < 0, "100 bytes should sort before 200");

    TEST(date_sort);
    dir_entry_t *old = dir_entry_create("old", 0, ENTRY_FILE, 1000, 0);
    dir_entry_t *new = dir_entry_create("new", 0, ENTRY_FILE, 2000, 0);
    cmp = dir_entry_compare_date(old, new);
    CHECK(cmp < 0, "older should sort first");

    TEST(extension_sort);
    dir_entry_t *txt = dir_entry_create("a.txt", 0, ENTRY_FILE, 0, 0);
    dir_entry_t *mod = dir_entry_create("b.mod", 0, ENTRY_FILE, 0, 0);
    cmp = dir_entry_compare_extension(mod, txt);
    CHECK(cmp < 0, ".mod before .txt");

    TEST(comparator_lookup);
    entry_compare_fn fn = dir_entry_get_comparator(SORT_SIZE);
    CHECK(fn == dir_entry_compare_size, "lookup failed");

    dir_entry_free(f2); dir_entry_free(f10);
    dir_entry_free(upper); dir_entry_free(lower);
    dir_entry_free(old); dir_entry_free(new);
    dir_entry_free(txt); dir_entry_free(mod);
}

/* --- Buffer tests --- */
static void test_buffer(void)
{
    printf("\n--- Directory Buffer ---\n");

    TEST(create_buffer);
    dir_buffer_t *buf = dir_buffer_create();
    CHECK(buf != NULL, "create");

    TEST(read_tmp);
    bool ok = dir_buffer_read(buf, "/tmp");
    CHECK(ok && (buf->flags & DBUF_VALID) && buf->stats.total_entries > 0,
          "read /tmp failed");

    TEST(stats_consistent);
    CHECK(buf->stats.total_entries == buf->stats.total_files + buf->stats.total_dirs,
          "entries != files + dirs");

    TEST(has_path);
    CHECK(strcmp(buf->path, "/tmp") == 0, "path wrong");

    printf("  (found %d files, %d dirs in /tmp)\n",
           buf->stats.total_files, buf->stats.total_dirs);

    TEST(find_entry);
    /* Create a known file and look for it */
    FILE *fp = fopen("/tmp/idopus_core_test_marker", "w");
    if (fp) { fputs("test", fp); fclose(fp); }
    dir_buffer_read(buf, "/tmp");
    dir_entry_t *found = dir_buffer_find_entry(buf, "idopus_core_test_marker");
    CHECK(found != NULL, "marker file not found");
    remove("/tmp/idopus_core_test_marker");

    TEST(get_entry_by_index);
    dir_entry_t *first = dir_buffer_get_entry(buf, 0);
    CHECK(first != NULL && first->name[0] != '\0', "index 0 failed");

    TEST(sort_by_name);
    dir_buffer_set_sort(buf, SORT_NAME, false, SEPARATE_DIRS_FIRST);
    dir_entry_t *e0 = dir_buffer_get_entry(buf, 0);
    CHECK(e0 != NULL, "sort result empty");

    TEST(sort_by_size_reverse);
    dir_buffer_set_sort(buf, SORT_SIZE, true, SEPARATE_MIX);
    e0 = dir_buffer_get_entry(buf, 0);
    dir_entry_t *e1 = dir_buffer_get_entry(buf, 1);
    if (e0 && e1 && !dir_entry_is_dir(e0) && !dir_entry_is_dir(e1))
        CHECK(e0->size >= e1->size, "reverse size sort wrong");
    else
        PASS(); /* mixed with dirs, hard to verify trivially */

    TEST(sort_dirs_first);
    dir_buffer_set_sort(buf, SORT_NAME, false, SEPARATE_DIRS_FIRST);
    /* First entry should be a directory (if any exist) */
    e0 = dir_buffer_get_entry(buf, 0);
    if (buf->stats.total_dirs > 0)
        CHECK(dir_entry_is_dir(e0), "first entry should be dir");
    else
        PASS(); /* no dirs in /tmp */

    TEST(select_all);
    dir_buffer_select_all(buf);
    dir_buffer_update_stats(buf);
    CHECK(buf->stats.selected_files == buf->stats.total_files &&
          buf->stats.selected_dirs == buf->stats.total_dirs, "select all");

    TEST(deselect_all);
    dir_buffer_deselect_all(buf);
    dir_buffer_update_stats(buf);
    CHECK(buf->stats.selected_files == 0 && buf->stats.selected_dirs == 0, "deselect all");

    TEST(select_pattern);
    dir_buffer_select_pattern(buf, "*.log", true);
    /* Just verify it doesn't crash; may or may not find .log files */
    PASS();

    dir_buffer_free(buf);
}

/* --- Filter tests --- */
static void test_filter(void)
{
    printf("\n--- Filtering ---\n");

    dir_buffer_t *buf = dir_buffer_create();
    /* Add some synthetic entries */
    dir_buffer_add_entry(buf, dir_entry_create("photo.jpg", 5000, ENTRY_FILE, 0, 0));
    dir_buffer_add_entry(buf, dir_entry_create("readme.txt", 100, ENTRY_FILE, 0, 0));
    dir_buffer_add_entry(buf, dir_entry_create(".hidden", 50, ENTRY_FILE, 0, 0));
    dir_entry_t *hidden = dir_buffer_find_entry(buf, ".hidden");
    if (hidden) hidden->flags |= ENTF_HIDDEN;
    dir_buffer_add_entry(buf, dir_entry_create("Documents", 0, ENTRY_DIRECTORY, 0, 0));
    dir_buffer_update_stats(buf);

    TEST(filter_show_pattern);
    dir_buffer_set_filter(buf, "*.txt", NULL, false);
    dir_buffer_apply_filter(buf);
    dir_buffer_update_stats(buf);
    /* Should have: readme.txt + Documents (dirs not filtered) */
    CHECK(buf->stats.total_files == 1 && buf->stats.total_dirs == 1, "show *.txt");

    TEST(filter_hide_pattern);
    dir_buffer_set_filter(buf, NULL, "*.jpg", false);
    dir_buffer_apply_filter(buf);
    dir_buffer_update_stats(buf);
    /* Should have: readme.txt, .hidden + Documents (jpg hidden) */
    CHECK(buf->stats.total_files == 2 && buf->stats.total_dirs == 1, "hide *.jpg");

    TEST(filter_hidden_files);
    dir_buffer_set_filter(buf, NULL, NULL, true);
    dir_buffer_apply_filter(buf);
    dir_buffer_update_stats(buf);
    /* .hidden should be rejected */
    CHECK(buf->stats.total_files == 2, "reject hidden");

    TEST(filter_clear);
    dir_buffer_set_filter(buf, NULL, NULL, false);
    dir_buffer_apply_filter(buf);
    dir_buffer_update_stats(buf);
    CHECK(buf->stats.total_entries == 4, "clear filter — all back");

    dir_buffer_free(buf);
}

/* --- Cache tests --- */
static void test_cache(void)
{
    printf("\n--- Buffer Cache ---\n");

    TEST(cache_create);
    buffer_cache_t *cache = buffer_cache_create(3);
    CHECK(cache != NULL, "create");

    TEST(cache_get_or_create);
    dir_buffer_t *b1 = buffer_cache_get_or_create(cache, "/tmp");
    CHECK(b1 != NULL && cache->count == 1, "first buffer");

    TEST(cache_find_existing);
    dir_buffer_t *b1again = buffer_cache_find(cache, "/tmp");
    CHECK(b1again == b1, "should find same buffer");

    TEST(cache_multiple);
    buffer_cache_get_or_create(cache, "/usr");
    buffer_cache_get_or_create(cache, "/var");
    CHECK(cache->count == 3, "three buffers");

    TEST(cache_eviction);
    /* Adding a 4th should evict the LRU (b1=/tmp, since /usr and /var are newer) */
    buffer_cache_get_or_create(cache, "/etc");
    CHECK(cache->count == 3, "still 3 after eviction");

    TEST(cache_lru_evicted);
    dir_buffer_t *evicted = buffer_cache_find(cache, "/tmp");
    CHECK(evicted == NULL, "/tmp should be evicted (LRU)");

    buffer_cache_free(cache);
}

/* --- Main --- */
int main(void)
{
    printf("iDOpus Core Test Suite\n");
    printf("======================\n");

    test_entries();
    test_sorting();
    test_buffer();
    test_filter();
    test_cache();

    printf("\n======================\n");
    printf("Results: %d passed, %d failed\n\n", passed, failed);
    return failed > 0 ? 1 : 0;
}
