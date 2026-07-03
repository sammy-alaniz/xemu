/*
 * Browser display bridge for experimental WASM boot builds.
 */

#include "qemu/osdep.h"
#include "ui/xemu-browser-display.h"
#include "ui/console.h"
#include "ui/qemu-pixman.h"
#include "ui/surface.h"

#ifdef CONFIG_OPENGL
#include "hw/xbox/nv2a/nv2a.h"
#include <epoxy/gl.h>
#endif

#include <emscripten.h>

static DisplayChangeListener browser_dcl;
static uint8_t *rgba_pixels;
static uint8_t *gl_pixels;
static int rgba_width;
static int rgba_height;
#ifdef CONFIG_OPENGL
static GLuint readback_fbo;
static bool warned_gl_readback;
#endif

static void xemu_browser_display_post_frame(int width, int height,
                                            int stride, const uint8_t *data)
{
    EM_ASM({
        if (Module.xemuBrowserDisplayUpdate) {
            Module.xemuBrowserDisplayUpdate($0, $1, $2, $3);
        }
    }, data, width, height, stride);
}

static bool xemu_browser_display_check_format(DisplayChangeListener *dcl,
                                              pixman_format_code_t format)
{
    int bpp = PIXMAN_FORMAT_BPP(format);

    return bpp == 16 || bpp == 24 || bpp == 32;
}

static void xemu_browser_display_ensure_rgba(int width, int height)
{
    if (rgba_pixels && rgba_width == width && rgba_height == height) {
        return;
    }

    rgba_width = width;
    rgba_height = height;
    rgba_pixels = g_realloc_n(rgba_pixels, width * height, 4);
}

static uint8_t scale_component(uint32_t value, uint8_t max)
{
    if (!max) {
        return 0;
    }

    return (value * 255 + max / 2) / max;
}

static uint32_t read_pixel(const uint8_t *src, int bytes_per_pixel)
{
    uint32_t pixel = 0;

    for (int i = 0; i < bytes_per_pixel; i++) {
        pixel |= (uint32_t)src[i] << (i * 8);
    }

    return pixel;
}

static void xemu_browser_display_convert(DisplaySurface *surface)
{
    int width = surface_width(surface);
    int height = surface_height(surface);
    int src_stride = surface_stride(surface);
    int bytes_per_pixel = surface_bytes_per_pixel(surface);
    const uint8_t *src = surface_data(surface);
    PixelFormat pf = qemu_pixelformat_from_pixman(surface_format(surface));

    xemu_browser_display_ensure_rgba(width, height);

    for (int y = 0; y < height; y++) {
        const uint8_t *src_row = src + y * src_stride;
        uint8_t *dst_row = rgba_pixels + y * width * 4;

        for (int x = 0; x < width; x++) {
            uint32_t pixel = read_pixel(src_row + x * bytes_per_pixel,
                                        bytes_per_pixel);
            uint32_t r = (pixel & pf.rmask) >> pf.rshift;
            uint32_t g = (pixel & pf.gmask) >> pf.gshift;
            uint32_t b = (pixel & pf.bmask) >> pf.bshift;
            uint32_t a = pf.abits ? (pixel & pf.amask) >> pf.ashift : pf.amax;
            uint8_t *dst = dst_row + x * 4;

            dst[0] = scale_component(r, pf.rmax);
            dst[1] = scale_component(g, pf.gmax);
            dst[2] = scale_component(b, pf.bmax);
            dst[3] = pf.abits ? scale_component(a, pf.amax) : 255;
        }
    }
}

static void xemu_browser_display_send_surface(DisplaySurface *surface)
{
    if (!surface || !surface_data(surface) ||
        surface_width(surface) <= 0 || surface_height(surface) <= 0) {
        return;
    }

    xemu_browser_display_convert(surface);
    xemu_browser_display_post_frame(rgba_width, rgba_height, rgba_width * 4,
                                    rgba_pixels);
}

#ifdef CONFIG_OPENGL
static bool xemu_browser_display_send_gl_frame(QemuConsole *con)
{
    DisplaySurface *surface = qemu_console_surface(con);
    int width = surface ? surface_width(surface) : 0;
    int height = surface ? surface_height(surface) : 0;
    GLuint tex;
    GLint previous_framebuffer = 0;
    GLenum status;
    bool sent = false;

    if (width <= 0 || height <= 0) {
        return false;
    }

    tex = nv2a_get_framebuffer_surface();
    if (!tex) {
        nv2a_release_framebuffer_surface();
        return false;
    }

    xemu_browser_display_ensure_rgba(width, height);
    gl_pixels = g_realloc_n(gl_pixels, width * height, 4);

    if (!readback_fbo) {
        glGenFramebuffers(1, &readback_fbo);
    }

    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &previous_framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, readback_fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D, tex, 0);

    status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status == GL_FRAMEBUFFER_COMPLETE) {
        glPixelStorei(GL_PACK_ALIGNMENT, 1);
        glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE,
                     gl_pixels);
        for (int y = 0; y < height; y++) {
            memcpy(rgba_pixels + y * width * 4,
                   gl_pixels + (height - 1 - y) * width * 4,
                   width * 4);
        }
        xemu_browser_display_post_frame(width, height, width * 4, rgba_pixels);
        sent = true;
    } else if (!warned_gl_readback) {
        fprintf(stderr,
                "Browser display: GL readback framebuffer incomplete: 0x%x\n",
                status);
        warned_gl_readback = true;
    }

    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D, 0, 0);
    glBindFramebuffer(GL_FRAMEBUFFER, previous_framebuffer);
    nv2a_release_framebuffer_surface();
    return sent;
}
#endif

static void xemu_browser_display_update(DisplayChangeListener *dcl,
                                        int x, int y, int w, int h)
{
#ifdef CONFIG_OPENGL
    if (xemu_browser_display_send_gl_frame(dcl->con)) {
        return;
    }
#endif
    xemu_browser_display_send_surface(qemu_console_surface(dcl->con));
}

static void xemu_browser_display_switch(DisplayChangeListener *dcl,
                                        DisplaySurface *new_surface)
{
    xemu_browser_display_send_surface(new_surface);
}

static void xemu_browser_display_refresh(DisplayChangeListener *dcl)
{
    graphic_hw_update(dcl->con);
#ifdef CONFIG_OPENGL
    if (xemu_browser_display_send_gl_frame(dcl->con)) {
        return;
    }
#endif
    xemu_browser_display_send_surface(qemu_console_surface(dcl->con));
}

static const DisplayChangeListenerOps browser_display_ops = {
    .dpy_name = "xemu-browser-display",
    .dpy_gfx_update = xemu_browser_display_update,
    .dpy_gfx_switch = xemu_browser_display_switch,
    .dpy_gfx_check_format = xemu_browser_display_check_format,
    .dpy_refresh = xemu_browser_display_refresh,
};

void xemu_browser_display_init(void)
{
    QemuConsole *con = qemu_console_lookup_by_index(0);

    if (!con || !qemu_console_is_graphic(con)) {
        fprintf(stderr, "Browser display: no graphic console available\n");
        return;
    }

    browser_dcl.con = con;
    browser_dcl.ops = &browser_display_ops;
    register_displaychangelistener(&browser_dcl);
    update_displaychangelistener(&browser_dcl, GUI_REFRESH_INTERVAL_DEFAULT);
    dpy_gfx_update_full(con);
    fprintf(stderr, "Browser display: registered software display listener\n");
}
