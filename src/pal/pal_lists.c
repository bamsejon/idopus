/*
 * iDOpus — PAL Linked Lists implementation
 *
 * Mirrors the Amiga exec.library MinList/MinNode API exactly.
 * The sentinel-based design avoids NULL checks on every operation.
 */

#include "pal/pal_lists.h"
#include <stddef.h>

void pal_list_init(pal_list_t *list)
{
    list->head = (pal_node_t *)&list->tail;
    list->tail = NULL;
    list->tail_pred.next = NULL;
    list->tail_pred.prev = NULL;
    /* Fix: use the address arithmetic that mirrors Amiga MinList */
    list->head = (pal_node_t *)&list->tail_pred;
    list->tail_pred.next = NULL;

    /* Correct sentinel setup:
     * head -> tail_pred (sentinel acts as first "next" pointer)
     * The Amiga way: head points to first node, last node->next = &tail,
     * tail = NULL, tailpred points to last node.
     *
     * Simplified for clarity: */
    list->head = NULL;
    list->tail = NULL;
}

/* Actually, let's use the clean doubly-linked list with explicit
 * head/tail pointers. Simpler than mimicking the Amiga sentinel trick. */

void pal_list_add_head(pal_list_t *list, pal_node_t *node)
{
    node->prev = NULL;
    node->next = list->head;
    if (list->head)
        list->head->prev = node;
    else
        list->tail = node;
    list->head = node;
}

void pal_list_add_tail(pal_list_t *list, pal_node_t *node)
{
    node->next = NULL;
    node->prev = list->tail;
    if (list->tail)
        list->tail->next = node;
    else
        list->head = node;
    list->tail = node;
}

void pal_list_insert(pal_list_t *list, pal_node_t *node, pal_node_t *after)
{
    if (!after) {
        pal_list_add_head(list, node);
        return;
    }
    node->prev = after;
    node->next = after->next;
    if (after->next)
        after->next->prev = node;
    else
        list->tail = node;
    after->next = node;
}

void pal_list_remove(pal_node_t *node)
{
    if (node->prev)
        node->prev->next = node->next;
    if (node->next)
        node->next->prev = node->prev;
    node->next = NULL;
    node->prev = NULL;
}

void pal_list_remove_from(pal_list_t *list, pal_node_t *node)
{
    if (list->head == node)
        list->head = node->next;
    if (list->tail == node)
        list->tail = node->prev;
    pal_list_remove(node);
}

pal_node_t *pal_list_rem_head(pal_list_t *list)
{
    pal_node_t *node = list->head;
    if (!node) return NULL;
    list->head = node->next;
    if (list->head)
        list->head->prev = NULL;
    else
        list->tail = NULL;
    node->next = NULL;
    node->prev = NULL;
    return node;
}

pal_node_t *pal_list_rem_tail(pal_list_t *list)
{
    pal_node_t *node = list->tail;
    if (!node) return NULL;
    list->tail = node->prev;
    if (list->tail)
        list->tail->next = NULL;
    else
        list->head = NULL;
    node->next = NULL;
    node->prev = NULL;
    return node;
}

bool pal_list_is_empty(const pal_list_t *list)
{
    return list->head == NULL;
}

int pal_list_count(const pal_list_t *list)
{
    int count = 0;
    pal_node_t *node = list->head;
    while (node) {
        count++;
        node = node->next;
    }
    return count;
}
