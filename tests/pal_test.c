/*
 * iDOpus — PAL smoke test
 *
 * Quick verification that the platform abstraction layer compiles
 * and works on macOS. Run: ./build/pal_test
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#ifndef _WIN32
#include <unistd.h>
#endif

#include "pal/pal_memory.h"
#include "pal/pal_lists.h"
#include "pal/pal_sync.h"
#include "pal/pal_ipc.h"
#include "pal/pal_strings.h"
#include "pal/pal_file.h"

static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) printf("  %-40s ", #name); fflush(stdout)
#define PASS() do { printf("OK\n"); tests_passed++; } while(0)
#define FAIL(msg) do { printf("FAIL: %s\n", msg); tests_failed++; } while(0)

/* --- Memory tests --- */
static void test_memory(void)
{
    printf("\n--- Memory ---\n");

    TEST(alloc_and_free);
    void *p = pal_alloc(256);
    assert(p != NULL);
    pal_free(p);
    PASS();

    TEST(alloc_clear);
    char *c = pal_alloc_clear(64);
    assert(c != NULL);
    int all_zero = 1;
    for (int i = 0; i < 64; i++) if (c[i] != 0) all_zero = 0;
    pal_free(c);
    if (all_zero) PASS(); else FAIL("memory not zeroed");

    TEST(pool_alloc);
    pal_pool_t *pool = pal_pool_create(4096, 256);
    assert(pool != NULL);
    void *pp = pal_pool_alloc(pool, 128);
    assert(pp != NULL);
    pal_pool_free(pool, pp, 128);
    pal_pool_destroy(pool);
    PASS();

    TEST(memcopy);
    char src[] = "hello world";
    char dst[32] = {0};
    pal_memcopy(src, dst, strlen(src) + 1);
    if (strcmp(dst, "hello world") == 0) PASS(); else FAIL("copy mismatch");
}

/* --- List tests --- */
static void test_lists(void)
{
    printf("\n--- Lists ---\n");

    typedef struct { pal_node_t node; int value; } item_t;

    TEST(init_empty);
    pal_list_t list;
    pal_list_init(&list);
    if (pal_list_is_empty(&list)) PASS(); else FAIL("not empty");

    TEST(add_head_tail);
    item_t a = { .value = 1 }, b = { .value = 2 }, c = { .value = 3 };
    pal_list_add_tail(&list, &a.node);
    pal_list_add_tail(&list, &b.node);
    pal_list_add_head(&list, &c.node);
    if (pal_list_count(&list) == 3) PASS(); else FAIL("count != 3");

    TEST(order);
    pal_node_t *n = pal_list_rem_head(&list);
    item_t *first = PAL_CONTAINER_OF(n, item_t, node);
    if (first->value == 3) PASS(); else FAIL("head should be 3");

    TEST(remove_all);
    pal_list_rem_head(&list);
    pal_list_rem_head(&list);
    if (pal_list_is_empty(&list)) PASS(); else FAIL("not empty after removing all");
}

/* --- String tests --- */
static void test_strings(void)
{
    printf("\n--- Strings ---\n");

    TEST(stricmp);
    if (pal_stricmp("Hello", "hello") == 0) PASS(); else FAIL("should be equal");

    TEST(has_suffix);
    if (pal_str_has_suffix("test.mod", ".mod")) PASS(); else FAIL("suffix not found");

    TEST(has_prefix);
    if (pal_str_has_prefix("DOpus", "dop")) PASS(); else FAIL("prefix not found");

    TEST(format_size);
    char buf[64];
    pal_format_size(1536, buf, sizeof(buf));
    if (strstr(buf, "KB")) PASS(); else FAIL(buf);

    TEST(sprintf_safe);
    char out[16];
    pal_sprintf(out, sizeof(out), "hello %s", "world of long strings");
    if (strlen(out) < sizeof(out)) PASS(); else FAIL("overflow");

    TEST(strdup);
    char *dup = pal_strdup("amiga");
    if (dup && strcmp(dup, "amiga") == 0) PASS(); else FAIL("strdup");
    free(dup);
}

/* --- File tests --- */

/* Pick platform-appropriate sentinel paths so this test runs unmodified on
 * POSIX and Windows. */
#ifdef _WIN32
# define TEST_EXIST_PATH     "C:\\Windows\\System32\\cmd.exe"
# define TEST_DIR_PATH       "C:\\Windows"
# define TEST_SCAN_PATH      "C:\\Windows"
# define TEST_TMP_FILE_PATH  "C:\\Windows\\Temp\\idopus_test.tmp"
#else
# define TEST_EXIST_PATH     "/usr/bin/true"
# define TEST_DIR_PATH       "/tmp"
# define TEST_SCAN_PATH      "/tmp"
# define TEST_TMP_FILE_PATH  "/tmp/idopus_test.tmp"
#endif

static void test_files(void)
{
    printf("\n--- Files ---\n");

    TEST(file_exists);
    if (pal_file_exists(TEST_EXIST_PATH)) PASS(); else FAIL(TEST_EXIST_PATH " not found");

    TEST(is_dir);
    if (pal_file_is_dir(TEST_DIR_PATH)) PASS(); else FAIL(TEST_DIR_PATH " not a dir");

    TEST(path_filename);
    const char *fn = pal_path_filename("/foo/bar/baz.txt");
    if (fn && strcmp(fn, "baz.txt") == 0) PASS(); else FAIL(fn);

    TEST(path_parent);
    char parent[256];
    pal_path_parent("/foo/bar/baz.txt", parent, sizeof(parent));
    if (strcmp(parent, "/foo/bar") == 0) PASS(); else FAIL(parent);

    TEST(path_join);
    char joined[256];
    pal_path_join("/Users", "jon", joined, sizeof(joined));
    if (strcmp(joined, "/Users/jon") == 0) PASS(); else FAIL(joined);

    TEST(path_match);
    if (pal_path_match("*.mod", "banana.mod")) PASS(); else FAIL("pattern");

    TEST(dir_scan);
    pal_dir_t *dir = pal_dir_open(TEST_SCAN_PATH);
    if (dir) {
        pal_fileinfo_t info;
        int count = 0;
        while (pal_dir_next(dir, &info) && count < 100) count++;
        pal_dir_close(dir);
        if (count > 0) PASS(); else FAIL("no entries in " TEST_SCAN_PATH);
    } else FAIL("can't open " TEST_SCAN_PATH);

    TEST(volumes);
    pal_volume_t vols[16];
    int n = pal_volumes_list(vols, 16);
    if (n > 0) {
        printf("OK (%d volumes: %s", n, vols[0].mount_point);
        if (n > 1) printf(", %s", vols[1].mount_point);
        printf(")\n");
        tests_passed++;
    } else FAIL("no volumes");

    TEST(file_io);
    pal_file_t *f = pal_file_open(TEST_TMP_FILE_PATH, "w");
    if (f) {
        pal_file_write(f, "iDOpus", 6);
        pal_file_close(f);
        f = pal_file_open(TEST_TMP_FILE_PATH, "r");
        char buf[16] = {0};
        pal_file_read(f, buf, 6);
        pal_file_close(f);
        pal_file_delete(TEST_TMP_FILE_PATH);
        if (strcmp(buf, "iDOpus") == 0) PASS(); else FAIL(buf);
    } else FAIL("can't create temp file");
}

/* --- IPC tests --- */
static void test_ipc(void)
{
    printf("\n--- IPC ---\n");

    TEST(port_create_destroy);
    pal_port_t *port = pal_port_create("test");
    assert(port != NULL);
    pal_port_destroy(port);
    PASS();

    TEST(send_receive);
    port = pal_port_create("test");
    pal_message_t *msg = pal_message_create(42, NULL, 0);
    pal_port_send(port, msg);
    pal_message_t *got = pal_port_receive(port);
    if (got && got->command == 42) PASS(); else FAIL("wrong command");
    pal_message_free(got);
    pal_port_destroy(port);
}

/* --- Main --- */
int main(void)
{
    printf("iDOpus PAL Test Suite\n");
    printf("====================\n");

    test_memory();
    test_lists();
    test_strings();
    test_files();
    test_ipc();

    printf("\n====================\n");
    printf("Results: %d passed, %d failed\n\n", tests_passed, tests_failed);

    return tests_failed > 0 ? 1 : 0;
}
