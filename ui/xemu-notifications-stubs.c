/*
 * Headless notification stubs for browser boot smoke builds.
 */

#include "qemu/osdep.h"
#include "ui/xemu-notifications.h"

void xemu_queue_notification(const char *msg)
{
    if (msg && msg[0]) {
        fprintf(stderr, "xemu notification: %s\n", msg);
    }
}

void xemu_queue_error_message(const char *msg)
{
    if (msg && msg[0]) {
        fprintf(stderr, "xemu error: %s\n", msg);
    }
}
