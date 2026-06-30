#ifndef UI_XEMU_BROWSER_DISPLAY_H
#define UI_XEMU_BROWSER_DISPLAY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

bool xemu_browser_display_submit_frame(uint32_t width,
                                       uint32_t height,
                                       uint32_t stride,
                                       uint32_t bpp,
                                       uint32_t format,
                                       const void *data,
                                       size_t bytes);

#endif
