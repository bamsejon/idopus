/*
 * iDOpus — Platform Abstraction Layer: IPC (Inter-Process Communication)
 *
 * Replaces Amiga exec message ports + DOpus IPC system:
 *   MsgPort, PutMsg/GetMsg/ReplyMsg/WaitPort,
 *   IPC_Launch, IPC_Command, IPC_Reply, IPC_Free
 *
 * macOS implementation: thread-based with message queues.
 * Each "port" is a mutex-protected FIFO queue with a condition
 * variable for blocking wait. Maps closely to the Amiga model
 * but uses pthreads instead of exec signals.
 *
 * The original DOpus 5 ran each Lister as a separate Amiga process
 * communicating via message ports. We preserve this architecture
 * using threads + message queues, which gives us the same
 * isolation and message-driven design.
 */

#ifndef PAL_IPC_H
#define PAL_IPC_H

#include <stdbool.h>
#include <stdint.h>
#include "pal_lists.h"
#include "pal_sync.h"

/* --- Message (replaces Amiga Message + IPCMessage) --- */

typedef struct pal_message {
    pal_node_t    node;         /* linkage in queue */
    uint32_t      command;      /* message command ID */
    uint32_t      flags;        /* message flags */
    void         *data;         /* payload pointer */
    size_t        data_size;    /* payload size (0 if data is borrowed) */
    int32_t       result;       /* reply result code */
    void         *reply_port;   /* port to reply to (NULL = no reply expected) */
    bool          replied;      /* set by pal_ipc_reply */
} pal_message_t;

/* --- Message Port (replaces Amiga MsgPort) --- */

typedef struct pal_port {
    char          name[64];     /* port name (for debugging/lookup) */
    pal_list_t    queue;        /* pending messages */
    pal_mutex_t   lock;         /* protects queue */
    pal_cond_t    signal;       /* wakes up waiters */
    bool          closed;       /* port is shutting down */
} pal_port_t;

/* --- Port lifecycle --- */

pal_port_t *pal_port_create(const char *name);
void        pal_port_destroy(pal_port_t *port);

/* --- Send/receive (replaces PutMsg/GetMsg/WaitPort/ReplyMsg) --- */

void            pal_port_send(pal_port_t *port, pal_message_t *msg);
pal_message_t  *pal_port_receive(pal_port_t *port);             /* non-blocking */
pal_message_t  *pal_port_wait(pal_port_t *port);                /* blocking */
pal_message_t  *pal_port_timedwait(pal_port_t *port, unsigned int timeout_ms);
void            pal_port_reply(pal_message_t *msg, int32_t result);

/* --- Message allocation --- */

pal_message_t *pal_message_create(uint32_t command, void *data, size_t data_size);
void           pal_message_free(pal_message_t *msg);

/* --- Synchronous command (send + wait for reply, replaces IPC_Command) --- */

int32_t pal_ipc_command(pal_port_t *port, uint32_t command, void *data, size_t size);

/* --- IPC Process (replaces IPC_Launch — thread with its own port) --- */

typedef void (*pal_ipc_func_t)(pal_port_t *port, void *userdata);

typedef struct pal_ipc_proc {
    pthread_t      thread;
    pal_port_t    *port;        /* this process's message port */
    pal_ipc_func_t func;        /* entry point */
    void          *userdata;
    bool           running;
} pal_ipc_proc_t;

pal_ipc_proc_t *pal_ipc_launch(const char *name, pal_ipc_func_t func, void *userdata);
void             pal_ipc_shutdown(pal_ipc_proc_t *proc);  /* sends quit + joins */
void             pal_ipc_free(pal_ipc_proc_t *proc);

#endif /* PAL_IPC_H */
