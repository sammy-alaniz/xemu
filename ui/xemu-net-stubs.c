/*
 * Browser boot network stubs.
 *
 * The reduced browser profile keeps the emulated NVNet device present for
 * boot coverage, but does not expose host networking backends.
 */

#include "qemu/osdep.h"
#include "xemu-net.h"
#include "xemu-settings.h"

void xemu_net_enable(void)
{
    g_config.net.enable = false;
}

void xemu_net_disable(void)
{
    g_config.net.enable = false;
}

int xemu_net_is_enabled(void)
{
    g_config.net.enable = false;
    return 0;
}
