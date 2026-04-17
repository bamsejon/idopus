/*
 * iDOpus — PAL IPC implementation (macOS/POSIX)
 *
 * Thread-based message passing that mirrors the Amiga architecture
 * where each Lister ran as its own process with a message port.
 */

#include "pal/pal_ipc.h"
#include "pal/pal_memory.h"
#include "pal/pal_strings.h"
#include <stdlib.h>
#include <string.h>

/* Command ID for shutdown */
#define PAL_IPC_CMD_QUIT  0xFFFFFFFF

/* --- Message allocation --- */

pal_message_t *pal_message_create(uint32_t command, void *data, size_t data_size)
{
    pal_message_t *msg = pal_alloc_clear(sizeof(pal_message_t));
    if (!msg) return NULL;
    msg->command = command;
    msg->data = data;
    msg->data_size = data_size;
    msg->replied = false;
    return msg;
}

void pal_message_free(pal_message_t *msg)
{
    if (!msg) return;
    /* If data was allocated with the message, free it */
    if (msg->data && msg->data_size > 0)
        pal_free(msg->data);
    pal_free(msg);
}

/* --- Port lifecycle --- */

pal_port_t *pal_port_create(const char *name)
{
    pal_port_t *port = pal_alloc_clear(sizeof(pal_port_t));
    if (!port) return NULL;
    if (name)
        pal_strlcpy(port->name, name, sizeof(port->name));
    pal_list_init(&port->queue);
    pal_mutex_init(&port->lock);
    pal_cond_init(&port->signal);
    port->closed = false;
    return port;
}

void pal_port_destroy(pal_port_t *port)
{
    if (!port) return;
    pal_mutex_lock(&port->lock);
    port->closed = true;
    pal_cond_broadcast(&port->signal);
    /* Drain remaining messages */
    pal_node_t *node;
    while ((node = pal_list_rem_head(&port->queue))) {
        pal_message_t *msg = PAL_CONTAINER_OF(node, pal_message_t, node);
        pal_message_free(msg);
    }
    pal_mutex_unlock(&port->lock);
    pal_mutex_destroy(&port->lock);
    pal_cond_destroy(&port->signal);
    pal_free(port);
}

/* --- Send/receive --- */

void pal_port_send(pal_port_t *port, pal_message_t *msg)
{
    if (!port || !msg) return;
    pal_mutex_lock(&port->lock);
    if (!port->closed) {
        pal_list_add_tail(&port->queue, &msg->node);
        pal_cond_signal(&port->signal);
    }
    pal_mutex_unlock(&port->lock);
}

pal_message_t *pal_port_receive(pal_port_t *port)
{
    if (!port) return NULL;
    pal_mutex_lock(&port->lock);
    pal_node_t *node = pal_list_rem_head(&port->queue);
    pal_mutex_unlock(&port->lock);
    return node ? PAL_CONTAINER_OF(node, pal_message_t, node) : NULL;
}

pal_message_t *pal_port_wait(pal_port_t *port)
{
    if (!port) return NULL;
    pal_mutex_lock(&port->lock);
    while (pal_list_is_empty(&port->queue) && !port->closed)
        pal_cond_wait(&port->signal, &port->lock);
    pal_node_t *node = pal_list_rem_head(&port->queue);
    pal_mutex_unlock(&port->lock);
    return node ? PAL_CONTAINER_OF(node, pal_message_t, node) : NULL;
}

pal_message_t *pal_port_timedwait(pal_port_t *port, unsigned int timeout_ms)
{
    if (!port) return NULL;
    pal_mutex_lock(&port->lock);
    if (pal_list_is_empty(&port->queue) && !port->closed)
        pal_cond_timedwait(&port->signal, &port->lock, timeout_ms);
    pal_node_t *node = pal_list_rem_head(&port->queue);
    pal_mutex_unlock(&port->lock);
    return node ? PAL_CONTAINER_OF(node, pal_message_t, node) : NULL;
}

void pal_port_reply(pal_message_t *msg, int32_t result)
{
    if (!msg) return;
    msg->result = result;
    msg->replied = true;
    /* If a reply port was specified, send the message back */
    if (msg->reply_port) {
        pal_port_send((pal_port_t *)msg->reply_port, msg);
    }
}

/* --- Synchronous command --- */

int32_t pal_ipc_command(pal_port_t *port, uint32_t command, void *data, size_t size)
{
    pal_port_t *reply_port = pal_port_create("reply");
    if (!reply_port) return -1;

    pal_message_t *msg = pal_message_create(command, data, 0); /* borrowed data */
    if (!msg) {
        pal_port_destroy(reply_port);
        return -1;
    }
    msg->reply_port = reply_port;

    pal_port_send(port, msg);
    pal_message_t *reply = pal_port_wait(reply_port);
    int32_t result = reply ? reply->result : -1;

    if (reply) pal_message_free(reply);
    pal_port_destroy(reply_port);
    return result;
}

/* --- IPC Process (thread with message port) --- */

static void *ipc_thread_func(void *arg)
{
    pal_ipc_proc_t *proc = (pal_ipc_proc_t *)arg;
    proc->running = true;
    proc->func(proc->port, proc->userdata);
    proc->running = false;
    return NULL;
}

pal_ipc_proc_t *pal_ipc_launch(const char *name, pal_ipc_func_t func, void *userdata)
{
    pal_ipc_proc_t *proc = pal_alloc_clear(sizeof(pal_ipc_proc_t));
    if (!proc) return NULL;

    proc->port = pal_port_create(name);
    if (!proc->port) {
        pal_free(proc);
        return NULL;
    }

    proc->func = func;
    proc->userdata = userdata;

    if (pthread_create(&proc->thread, NULL, ipc_thread_func, proc) != 0) {
        pal_port_destroy(proc->port);
        pal_free(proc);
        return NULL;
    }

    return proc;
}

void pal_ipc_shutdown(pal_ipc_proc_t *proc)
{
    if (!proc) return;
    /* Send quit command */
    pal_message_t *quit = pal_message_create(PAL_IPC_CMD_QUIT, NULL, 0);
    if (quit)
        pal_port_send(proc->port, quit);
    /* Wait for thread to finish */
    pthread_join(proc->thread, NULL);
}

void pal_ipc_free(pal_ipc_proc_t *proc)
{
    if (!proc) return;
    pal_port_destroy(proc->port);
    pal_free(proc);
}
