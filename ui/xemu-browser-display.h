#ifndef XEMU_BROWSER_DISPLAY_H
#define XEMU_BROWSER_DISPLAY_H

#include <stdint.h>

void xemu_browser_display_init(void);
void xemu_browser_display_post_frame(const char *source, int width, int height,
                                     int stride, const uint8_t *data);

#endif
