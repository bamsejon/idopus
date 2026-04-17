/*
 * iDOpus — Platform Abstraction Layer: Linked Lists
 *
 * Replaces Amiga exec.library list primitives:
 *   MinList/MinNode, List/Node, NewList, AddHead, AddTail,
 *   Remove, RemHead, RemTail, Insert, IsListEmpty
 *
 * These are intrusive doubly-linked lists — the node struct is
 * embedded in the containing struct, same pattern as Amiga.
 */

#ifndef PAL_LISTS_H
#define PAL_LISTS_H

#include <stdbool.h>
#include <stddef.h>

/* --- Node (embeddable) --- */

typedef struct pal_node {
    struct pal_node *next;
    struct pal_node *prev;
} pal_node_t;

/* --- List head --- */

typedef struct pal_list {
    pal_node_t *head;
    pal_node_t *tail;
    pal_node_t  tail_pred; /* sentinel — mirrors Amiga MinList layout */
} pal_list_t;

/* --- Init --- */

void pal_list_init(pal_list_t *list);

/* --- Query --- */

bool pal_list_is_empty(const pal_list_t *list);
int  pal_list_count(const pal_list_t *list);

/* --- Insert/Remove --- */

void        pal_list_add_head(pal_list_t *list, pal_node_t *node);
void        pal_list_add_tail(pal_list_t *list, pal_node_t *node);
void        pal_list_insert(pal_list_t *list, pal_node_t *node, pal_node_t *after);
void        pal_list_remove(pal_node_t *node);  /* only safe if not head/tail */
void        pal_list_remove_from(pal_list_t *list, pal_node_t *node); /* safe always */
pal_node_t *pal_list_rem_head(pal_list_t *list);
pal_node_t *pal_list_rem_tail(pal_list_t *list);

/* --- Iteration macros --- */

#define PAL_LIST_FOR_EACH(list, node) \
    for ((node) = (list)->head; (node)->next; (node) = (node)->next)

#define PAL_LIST_FOR_EACH_SAFE(list, node, tmp) \
    for ((node) = (list)->head; ((tmp) = (node)->next); (node) = (tmp))

/* --- Container-of macro (get parent struct from embedded node) --- */

#define PAL_CONTAINER_OF(ptr, type, member) \
    ((type *)((char *)(ptr) - offsetof(type, member)))

#endif /* PAL_LISTS_H */
