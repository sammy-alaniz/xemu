/*
 * Browser display bridge for the reduced xemu browser boot profile.
 */

#include "qemu/osdep.h"
#include "ui/xemu-browser-display.h"

#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)

#include <emscripten/emscripten.h>
#include <emscripten/em_asm.h>

static uint32_t browser_display_frame_id;

bool xemu_browser_display_submit_frame(uint32_t width,
                                       uint32_t height,
                                       uint32_t stride,
                                       uint32_t bpp,
                                       uint32_t format,
                                       const void *data,
                                       size_t bytes)
{
    uint32_t frame_id;

    if (!data || width == 0 || height == 0 || stride == 0 || bpp == 0 ||
        bytes == 0 || bytes > INT_MAX) {
        return false;
    }

    frame_id = ++browser_display_frame_id;
    return MAIN_THREAD_EM_ASM_INT({
        globalThis.xemuBrowserDisplayHeap = HEAPU8;
        const cb = Module['xemuBrowserDisplayFrame'] || globalThis.xemuBrowserDisplayFrame;
        if (!cb) {
            return 0;
        }
        return cb($0, $1, $2, $3, $4, $5, $6, $7) ? 1 : 0;
    }, frame_id, width, height, stride, bpp, format, data, (int)bytes) != 0;
}

#else

bool xemu_browser_display_submit_frame(uint32_t width,
                                       uint32_t height,
                                       uint32_t stride,
                                       uint32_t bpp,
                                       uint32_t format,
                                       const void *data,
                                       size_t bytes)
{
    (void)width;
    (void)height;
    (void)stride;
    (void)bpp;
    (void)format;
    (void)data;
    (void)bytes;

    return false;
}

#endif
