/*
 * Headless input stubs for browser boot smoke builds.
 */

#include "qemu/osdep.h"
#include "ui/xemu-input.h"

ControllerStateList available_controllers =
    QTAILQ_HEAD_INITIALIZER(available_controllers);
ControllerState *bound_controllers[4];
const char *bound_drivers[4];
int *g_keyboard_scancode_map[25];

void xemu_input_init(void)
{
}

void xemu_input_update_controllers(void)
{
}

void xemu_input_update_controller(ControllerState *state)
{
}

void xemu_input_update_rumble(ControllerState *state)
{
}

ControllerState *xemu_input_get_bound(int index)
{
    return NULL;
}

void xemu_input_bind(int index, ControllerState *state, int save)
{
}

bool xemu_input_bind_xmu(int player_index, int peripheral_port_index,
                         const char *filename, bool is_rebind)
{
    return false;
}

void xemu_input_rebind_xmu(int port)
{
}

void xemu_input_unbind_xmu(int player_index, int peripheral_port_index)
{
}

int xemu_input_get_controller_default_bind_port(ControllerState *state,
                                                int start)
{
    return -1;
}

void xemu_save_peripheral_settings(int player_index, int peripheral_index,
                                   int peripheral_type,
                                   const char *peripheral_parameter)
{
}

void xemu_input_set_test_mode(int enabled)
{
}

int xemu_input_get_test_mode(void)
{
    return 0;
}

void xemu_input_reset_input_mapping(ControllerState *state)
{
}
