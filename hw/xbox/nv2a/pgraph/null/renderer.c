/*
 * Geforce NV2A PGRAPH Null Renderer
 *
 * Copyright (c) 2024 Matt Borgerson
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
 */

#include "qemu/osdep.h"
#include "qemu/thread.h"
#include "hw/hw.h"
#include "hw/xbox/nv2a/nv2a_int.h"
#include "ui/xemu-browser-display.h"

#if defined(CONFIG_XEMU_BROWSER_BOOT)

static bool pgraph_null_surface_bpp(unsigned int color_format,
                                    unsigned int *bpp,
                                    unsigned int *bytes_per_pixel)
{
    switch (color_format) {
    case NV097_SET_SURFACE_FORMAT_COLOR_LE_X1R5G5B5_Z1R5G5B5:
    case NV097_SET_SURFACE_FORMAT_COLOR_LE_X1R5G5B5_O1R5G5B5:
    case NV097_SET_SURFACE_FORMAT_COLOR_LE_R5G6B5:
        *bpp = 16;
        *bytes_per_pixel = 2;
        return true;
    case NV097_SET_SURFACE_FORMAT_COLOR_LE_X8R8G8B8_Z8R8G8B8:
    case NV097_SET_SURFACE_FORMAT_COLOR_LE_X8R8G8B8_O8R8G8B8:
    case NV097_SET_SURFACE_FORMAT_COLOR_LE_X1A7R8G8B8_Z1A7R8G8B8:
    case NV097_SET_SURFACE_FORMAT_COLOR_LE_X1A7R8G8B8_O1A7R8G8B8:
    case NV097_SET_SURFACE_FORMAT_COLOR_LE_A8R8G8B8:
        *bpp = 32;
        *bytes_per_pixel = 4;
        return true;
    case NV097_SET_SURFACE_FORMAT_COLOR_LE_B8:
        *bpp = 8;
        *bytes_per_pixel = 1;
        return true;
    case NV097_SET_SURFACE_FORMAT_COLOR_LE_G8B8:
        *bpp = 16;
        *bytes_per_pixel = 2;
        return true;
    default:
        return false;
    }
}

static bool pgraph_null_context_bpp(unsigned int color_format,
                                    unsigned int *bytes_per_pixel)
{
    switch (color_format) {
    case NV062_SET_COLOR_FORMAT_LE_Y8:
        *bytes_per_pixel = 1;
        return true;
    case NV062_SET_COLOR_FORMAT_LE_R5G6B5:
        *bytes_per_pixel = 2;
        return true;
    case NV062_SET_COLOR_FORMAT_LE_A8R8G8B8:
    case NV062_SET_COLOR_FORMAT_LE_X8R8G8B8:
    case NV062_SET_COLOR_FORMAT_LE_X8R8G8B8_Z8R8G8B8:
    case NV062_SET_COLOR_FORMAT_LE_Y32:
        *bytes_per_pixel = 4;
        return true;
    default:
        return false;
    }
}

static bool pgraph_null_color_surface(NV2AState *d,
                                      hwaddr *vram_addr,
                                      unsigned int *width,
                                      unsigned int *height,
                                      unsigned int *stride,
                                      unsigned int *bpp,
                                      unsigned int *bytes_per_pixel,
                                      unsigned int *format,
                                      size_t *bytes)
{
    PGRAPHState *pg = &d->pgraph;
    DMAObject dma;
    hwaddr addr;
    uint64_t end;
    uint64_t vram_size;
    uint64_t surface_bytes;

    if (!d->vram_ptr || !pg->surface_shape.color_format ||
        !pg->surface_color.pitch) {
        return false;
    }

    if (pg->surface_type == NV097_SET_SURFACE_FORMAT_TYPE_SWIZZLE) {
        return false;
    }

    if (!pgraph_null_surface_bpp(pg->surface_shape.color_format,
                                 bpp, bytes_per_pixel)) {
        return false;
    }

    *width = pg->surface_shape.clip_width;
    *height = pg->surface_shape.clip_height;
    pgraph_apply_anti_aliasing_factor(pg, width, height);

    *width += pg->surface_shape.clip_x;
    *height += pg->surface_shape.clip_y;
    if (*width == 0 || *height == 0) {
        return false;
    }

    *stride = pg->surface_color.pitch;
    if (*stride < *bytes_per_pixel) {
        return false;
    }
    if (*width > *stride / *bytes_per_pixel) {
        *width = *stride / *bytes_per_pixel;
    }

    dma = nv_dma_load(d, pg->dma_color);
    if (dma.dma_class != NV_DMA_IN_MEMORY_CLASS ||
        pg->surface_color.offset > dma.limit) {
        return false;
    }

    addr = (dma.address & 0x07FFFFFF) + pg->surface_color.offset;
    surface_bytes = (uint64_t)*stride * (uint64_t)*height;
    vram_size = memory_region_size(d->vram);
    end = (uint64_t)addr + surface_bytes;
    if (surface_bytes == 0 || surface_bytes > SIZE_MAX || end > vram_size) {
        return false;
    }

    *vram_addr = addr;
    *format = pg->surface_shape.color_format;
    *bytes = (size_t)surface_bytes;
    return true;
}

static bool pgraph_null_surface_visible_nonempty(const uint8_t *data,
                                                unsigned int width,
                                                unsigned int height,
                                                unsigned int stride,
                                                unsigned int bpp,
                                                unsigned int format)
{
    for (unsigned int y = 0; y < height; y++) {
        const uint8_t *row = data + y * stride;

        for (unsigned int x = 0; x < width; x++) {
            if (bpp == 32) {
                const uint8_t *pixel = row + x * 4;
                if (pixel[0] || pixel[1] || pixel[2]) {
                    return true;
                }
            } else if (bpp == 16) {
                uint16_t pixel = lduw_le_p(row + x * 2);
                uint16_t rgb_mask =
                    (format == NV097_SET_SURFACE_FORMAT_COLOR_LE_X1R5G5B5_Z1R5G5B5 ||
                     format == NV097_SET_SURFACE_FORMAT_COLOR_LE_X1R5G5B5_O1R5G5B5)
                    ? 0x7fff : 0xffff;
                if (pixel & rgb_mask) {
                    return true;
                }
            } else if (bpp == 8) {
                if (row[x]) {
                    return true;
                }
            }
        }
    }

    return false;
}

static bool pgraph_null_submit_color_surface(NV2AState *d)
{
    hwaddr vram_addr;
    unsigned int width, height, stride, bpp, bytes_per_pixel, format;
    size_t bytes;
    const uint8_t *data;

    if (!pgraph_null_color_surface(d, &vram_addr, &width, &height, &stride,
                                   &bpp, &bytes_per_pixel, &format, &bytes)) {
        return false;
    }

    data = d->vram_ptr + vram_addr;
    if (!pgraph_null_surface_visible_nonempty(data, width, height, stride, bpp,
                                              format)) {
        return false;
    }

    return xemu_browser_display_submit_frame(width, height, stride, bpp, format,
                                             data, bytes);
}

static uint32_t pgraph_null_clear_mask(unsigned int color_format,
                                       uint32_t parameter)
{
    uint32_t mask = 0;

    switch (color_format) {
    case NV097_SET_SURFACE_FORMAT_COLOR_LE_X1R5G5B5_Z1R5G5B5:
    case NV097_SET_SURFACE_FORMAT_COLOR_LE_X1R5G5B5_O1R5G5B5:
        if (parameter & NV097_CLEAR_SURFACE_R) {
            mask |= 0x00007c00;
        }
        if (parameter & NV097_CLEAR_SURFACE_G) {
            mask |= 0x000003e0;
        }
        if (parameter & NV097_CLEAR_SURFACE_B) {
            mask |= 0x0000001f;
        }
        if (parameter & NV097_CLEAR_SURFACE_A) {
            mask |= 0x00008000;
        }
        break;
    case NV097_SET_SURFACE_FORMAT_COLOR_LE_R5G6B5:
        if (parameter & NV097_CLEAR_SURFACE_R) {
            mask |= 0x0000f800;
        }
        if (parameter & NV097_CLEAR_SURFACE_G) {
            mask |= 0x000007e0;
        }
        if (parameter & NV097_CLEAR_SURFACE_B) {
            mask |= 0x0000001f;
        }
        break;
    case NV097_SET_SURFACE_FORMAT_COLOR_LE_B8:
        if (parameter & NV097_CLEAR_SURFACE_B) {
            mask |= 0x000000ff;
        }
        break;
    case NV097_SET_SURFACE_FORMAT_COLOR_LE_G8B8:
        if (parameter & NV097_CLEAR_SURFACE_B) {
            mask |= 0x000000ff;
        }
        if (parameter & NV097_CLEAR_SURFACE_G) {
            mask |= 0x0000ff00;
        }
        break;
    default:
        if (parameter & NV097_CLEAR_SURFACE_B) {
            mask |= 0x000000ff;
        }
        if (parameter & NV097_CLEAR_SURFACE_G) {
            mask |= 0x0000ff00;
        }
        if (parameter & NV097_CLEAR_SURFACE_R) {
            mask |= 0x00ff0000;
        }
        if (parameter & NV097_CLEAR_SURFACE_A) {
            mask |= 0xff000000;
        }
        break;
    }

    return mask;
}

static void pgraph_null_clear_pixel(uint8_t *pixel,
                                    unsigned int bytes_per_pixel,
                                    uint32_t clear_color,
                                    uint32_t mask)
{
    switch (bytes_per_pixel) {
    case 1: {
        uint8_t old = *pixel;
        uint8_t value = (old & ~(uint8_t)mask) |
                        ((uint8_t)clear_color & (uint8_t)mask);
        *pixel = value;
        break;
    }
    case 2: {
        uint16_t old = lduw_le_p(pixel);
        uint16_t value = (old & ~(uint16_t)mask) |
                         ((uint16_t)clear_color & (uint16_t)mask);
        stw_le_p(pixel, value);
        break;
    }
    case 4: {
        uint32_t old = ldl_le_p(pixel);
        uint32_t value = (old & ~mask) | (clear_color & mask);
        stl_le_p(pixel, value);
        break;
    }
    default:
        break;
    }
}

static void pgraph_null_mark_vram_dirty(NV2AState *d, hwaddr addr, size_t bytes)
{
    memory_region_set_client_dirty(d->vram, addr, bytes, DIRTY_MEMORY_VGA);
    memory_region_set_client_dirty(d->vram, addr, bytes, DIRTY_MEMORY_NV2A_TEX);
}

static void pgraph_null_browser_clear_surface(NV2AState *d, uint32_t parameter)
{
    PGRAPHState *pg = &d->pgraph;
    hwaddr vram_addr;
    unsigned int width, height, stride, bpp, bytes_per_pixel, format;
    size_t surface_bytes;
    uint8_t *base;
    uint32_t clear_color;
    uint32_t mask;
    uint32_t clearrectx;
    uint32_t clearrecty;
    unsigned int xmin, xmax, ymin, ymax;
    unsigned int clear_width, clear_height;

    if (!(parameter & NV097_CLEAR_SURFACE_COLOR)) {
        return;
    }

    if (!pgraph_null_color_surface(d, &vram_addr, &width, &height, &stride,
                                   &bpp, &bytes_per_pixel, &format,
                                   &surface_bytes)) {
        return;
    }

    clear_color = pgraph_reg_r(pg, NV_PGRAPH_COLORCLEARVALUE);
    mask = pgraph_null_clear_mask(format, parameter);
    if (!mask) {
        return;
    }

    clearrectx = pgraph_reg_r(pg, NV_PGRAPH_CLEARRECTX);
    clearrecty = pgraph_reg_r(pg, NV_PGRAPH_CLEARRECTY);

    xmin = GET_MASK(clearrectx, NV_PGRAPH_CLEARRECTX_XMIN);
    xmax = GET_MASK(clearrectx, NV_PGRAPH_CLEARRECTX_XMAX);
    ymin = GET_MASK(clearrecty, NV_PGRAPH_CLEARRECTY_YMIN);
    ymax = GET_MASK(clearrecty, NV_PGRAPH_CLEARRECTY_YMAX);

    xmin = MIN(xmin, width - 1);
    ymin = MIN(ymin, height - 1);
    xmax = MAX(xmin, MIN(xmax, width - 1));
    ymax = MAX(ymin, MIN(ymax, height - 1));

    clear_width = xmax - xmin + 1;
    clear_height = ymax - ymin + 1;
    pgraph_apply_anti_aliasing_factor(pg, &xmin, &ymin);
    pgraph_apply_anti_aliasing_factor(pg, &clear_width, &clear_height);

    if (xmin >= width || ymin >= height) {
        return;
    }
    clear_width = MIN(clear_width, width - xmin);
    clear_height = MIN(clear_height, height - ymin);

    base = d->vram_ptr + vram_addr;
    for (unsigned int y = 0; y < clear_height; y++) {
        uint8_t *row = base + (ymin + y) * stride +
                       xmin * bytes_per_pixel;
        for (unsigned int x = 0; x < clear_width; x++) {
            pgraph_null_clear_pixel(row + x * bytes_per_pixel,
                                    bytes_per_pixel, clear_color, mask);
        }
    }

    pgraph_null_mark_vram_dirty(d, vram_addr, surface_bytes);
    pgraph_null_submit_color_surface(d);
}

static void pgraph_null_perform_blit(int operation, uint8_t *source,
                                     uint8_t *dest, size_t width,
                                     size_t height, size_t width_bytes,
                                     size_t source_pitch, size_t dest_pitch,
                                     BetaState *beta)
{
    if (operation == NV09F_SET_OPERATION_SRCCOPY) {
        for (unsigned int y = 0; y < height; y++) {
            memmove(dest, source, width_bytes);
            source += source_pitch;
            dest += dest_pitch;
        }
    } else if (operation == NV09F_SET_OPERATION_BLEND_AND) {
        uint32_t max_beta_mult = 0x7f80;
        uint32_t beta_mult = beta->beta >> 16;
        uint32_t inv_beta_mult = max_beta_mult - beta_mult;

        for (unsigned int y = 0; y < height; y++) {
            uint8_t *s = source;
            uint8_t *dptr = dest;
            for (unsigned int x = 0; x < width; x++) {
                for (unsigned int ch = 0; ch < 3; ch++) {
                    uint32_t a = s[x * 4 + ch] * beta_mult;
                    uint32_t b = dptr[x * 4 + ch] * inv_beta_mult;
                    dptr[x * 4 + ch] = (a + b) / max_beta_mult;
                }
            }
            source += source_pitch;
            dest += dest_pitch;
        }
    }
}

static void pgraph_null_patch_alpha(uint8_t *dest, size_t width_pixels,
                                    size_t height, size_t dest_pitch,
                                    uint8_t alpha_val)
{
    for (unsigned int y = 0; y < height; y++) {
        uint8_t *dptr = dest;
        for (unsigned int x = 0; x < width_pixels; x++) {
            dptr[x * 4 + 3] = alpha_val;
        }
        dest += dest_pitch;
    }
}

static bool pgraph_null_addr_overlaps_color_surface(NV2AState *d,
                                                    hwaddr addr,
                                                    size_t bytes)
{
    hwaddr surface_addr;
    unsigned int width, height, stride, bpp, bytes_per_pixel, format;
    size_t surface_bytes;

    if (!pgraph_null_color_surface(d, &surface_addr, &width, &height, &stride,
                                   &bpp, &bytes_per_pixel, &format,
                                   &surface_bytes)) {
        return false;
    }

    return addr < surface_addr + surface_bytes &&
           surface_addr < addr + bytes;
}

static void pgraph_null_browser_image_blit(NV2AState *d)
{
    PGRAPHState *pg = &d->pgraph;
    ContextSurfaces2DState *context_surfaces = &pg->context_surfaces_2d;
    ImageBlitState *image_blit = &pg->image_blit;
    BetaState *beta = &pg->beta;
    unsigned int bytes_per_pixel;
    hwaddr source_dma_len, dest_dma_len;
    uint8_t *source, *dest;
    hwaddr dest_addr;
    hwaddr source_offset, dest_offset;
    size_t max_row_pixels, row_pixels, row_bytes;
    size_t dest_size, adjusted_height, leftover_bytes;
    hwaddr clipped_dest_size;

    if (context_surfaces->object_instance != image_blit->context_surfaces ||
        !pgraph_null_context_bpp(context_surfaces->color_format,
                                 &bytes_per_pixel) ||
        context_surfaces->source_pitch == 0 ||
        context_surfaces->dest_pitch == 0 ||
        image_blit->operation != NV09F_SET_OPERATION_SRCCOPY) {
        return;
    }

    source = (uint8_t *)nv_dma_map(d, context_surfaces->dma_image_source,
                                   &source_dma_len);
    dest = (uint8_t *)nv_dma_map(d, context_surfaces->dma_image_dest,
                                 &dest_dma_len);
    if (context_surfaces->source_offset >= source_dma_len ||
        context_surfaces->dest_offset >= dest_dma_len) {
        return;
    }

    source += context_surfaces->source_offset;
    dest += context_surfaces->dest_offset;
    dest_addr = dest - d->vram_ptr;

    source_offset = image_blit->in_y * context_surfaces->source_pitch +
                    image_blit->in_x * bytes_per_pixel;
    dest_offset = image_blit->out_y * context_surfaces->dest_pitch +
                  image_blit->out_x * bytes_per_pixel;

    if (source_offset >= source_dma_len || dest_offset >= dest_dma_len) {
        return;
    }

    max_row_pixels = MIN(context_surfaces->source_pitch,
                         context_surfaces->dest_pitch) / bytes_per_pixel;
    row_pixels = MIN(max_row_pixels, image_blit->width);
    if (row_pixels == 0 || image_blit->height == 0) {
        return;
    }

    dest_size = (image_blit->height - 1) * context_surfaces->dest_pitch +
                image_blit->width * bytes_per_pixel;
    clipped_dest_size =
        nv_clip_gpu_tile_blit(d, dest_addr + dest_offset, dest_size);
    adjusted_height = image_blit->height;
    leftover_bytes = 0;
    if (clipped_dest_size < dest_size) {
        adjusted_height = clipped_dest_size / context_surfaces->dest_pitch;
        leftover_bytes = clipped_dest_size -
                         adjusted_height * context_surfaces->dest_pitch;
    }

    row_bytes = row_pixels * bytes_per_pixel;
    if (adjusted_height > 0) {
        pgraph_null_perform_blit(image_blit->operation,
                                 source + source_offset,
                                 dest + dest_offset,
                                 row_pixels,
                                 adjusted_height,
                                 row_bytes,
                                 context_surfaces->source_pitch,
                                 context_surfaces->dest_pitch,
                                 beta);
    }

    if (leftover_bytes > 0) {
        pgraph_null_perform_blit(image_blit->operation,
                                 source + source_offset +
                                     adjusted_height *
                                     context_surfaces->source_pitch,
                                 dest + dest_offset +
                                     adjusted_height *
                                     context_surfaces->dest_pitch,
                                 leftover_bytes / bytes_per_pixel,
                                 1,
                                 leftover_bytes,
                                 context_surfaces->source_pitch,
                                 context_surfaces->dest_pitch,
                                 beta);
    }

    if (bytes_per_pixel == 4) {
        uint8_t alpha_override = 0;
        bool patch_alpha = false;

        if (context_surfaces->color_format == NV062_SET_COLOR_FORMAT_LE_X8R8G8B8) {
            alpha_override = 0xff;
            patch_alpha = true;
        } else if (context_surfaces->color_format ==
                   NV062_SET_COLOR_FORMAT_LE_X8R8G8B8_Z8R8G8B8) {
            alpha_override = 0;
            patch_alpha = true;
        }

        if (patch_alpha && adjusted_height > 0) {
            pgraph_null_patch_alpha(dest + dest_offset, row_pixels,
                                    adjusted_height,
                                    context_surfaces->dest_pitch,
                                    alpha_override);
        }
        if (patch_alpha && leftover_bytes > 0) {
            pgraph_null_patch_alpha(dest + dest_offset +
                                        adjusted_height *
                                        context_surfaces->dest_pitch,
                                    leftover_bytes / 4, 1, 0,
                                    alpha_override);
        }
    }

    dest_addr += dest_offset;
    pgraph_null_mark_vram_dirty(d, dest_addr, clipped_dest_size);

    if (pgraph_null_addr_overlaps_color_surface(d, dest_addr,
                                                clipped_dest_size)) {
        pgraph_null_submit_color_surface(d);
    }
}

#endif

static void pgraph_null_sync(NV2AState *d)
{
    qatomic_set(&d->pgraph.sync_pending, false);
    qemu_event_set(&d->pgraph.sync_complete);
}

static void pgraph_null_flush(NV2AState *d)
{
    qatomic_set(&d->pgraph.flush_pending, false);
    qemu_event_set(&d->pgraph.flush_complete);
}

static void pgraph_null_process_pending(NV2AState *d)
{
    if (
        qatomic_read(&d->pgraph.sync_pending) ||
        qatomic_read(&d->pgraph.flush_pending)
        ) {
        qemu_mutex_unlock(&d->pfifo.lock);
        qemu_mutex_lock(&d->pgraph.lock);
        if (qatomic_read(&d->pgraph.sync_pending)) {
            pgraph_null_sync(d);
        }
        if (qatomic_read(&d->pgraph.flush_pending)) {
            pgraph_null_flush(d);
        }
        qemu_mutex_unlock(&d->pgraph.lock);
        qemu_mutex_lock(&d->pfifo.lock);
    }
}

static void pgraph_null_clear_report_value(NV2AState *d)
{
}

static void pgraph_null_clear_surface(NV2AState *d, uint32_t parameter)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT)
    pgraph_null_browser_clear_surface(d, parameter);
#endif
}

static void pgraph_null_draw_begin(NV2AState *d)
{
}

static void pgraph_null_draw_end(NV2AState *d)
{
}

static void pgraph_null_flip_stall(NV2AState *d)
{
    PGRAPHState *pg = &d->pgraph;
    uint32_t surface = pgraph_reg_r(pg, NV_PGRAPH_SURFACE);
    uint32_t write = GET_MASK(surface, NV_PGRAPH_SURFACE_WRITE_3D);

    SET_MASK(surface, NV_PGRAPH_SURFACE_READ_3D, (write + 1) & 0x7);
    pgraph_reg_w(pg, NV_PGRAPH_SURFACE, surface);
}

static void pgraph_null_flush_draw(NV2AState *d)
{
}

static void pgraph_null_get_report(NV2AState *d, uint32_t parameter)
{
    pgraph_write_zpass_pixel_cnt_report(d, parameter, 0);
}

static void pgraph_null_image_blit(NV2AState *d)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT)
    pgraph_null_browser_image_blit(d);
#endif
}

static void pgraph_null_pre_savevm_trigger(NV2AState *d)
{
}

static void pgraph_null_pre_savevm_wait(NV2AState *d)
{
}

static void pgraph_null_pre_shutdown_trigger(NV2AState *d)
{
}

static void pgraph_null_pre_shutdown_wait(NV2AState *d)
{
}

static void pgraph_null_process_pending_reports(NV2AState *d)
{
}

static void pgraph_null_surface_update(NV2AState *d, bool upload,
                                       bool color_write, bool zeta_write)
{
}

static void pgraph_null_init(NV2AState *d, Error **errp)
{
    PGRAPHState *pg = &d->pgraph;
    pg->null_renderer_state = NULL;
}

static PGRAPHRenderer pgraph_null_renderer = {
    .type = CONFIG_DISPLAY_RENDERER_NULL,
    .name = "Null",
    .ops = {
        .init = pgraph_null_init,
        .clear_report_value = pgraph_null_clear_report_value,
        .clear_surface = pgraph_null_clear_surface,
        .draw_begin = pgraph_null_draw_begin,
        .draw_end = pgraph_null_draw_end,
        .flip_stall = pgraph_null_flip_stall,
        .flush_draw = pgraph_null_flush_draw,
        .get_report = pgraph_null_get_report,
        .image_blit = pgraph_null_image_blit,
        .pre_savevm_trigger = pgraph_null_pre_savevm_trigger,
        .pre_savevm_wait = pgraph_null_pre_savevm_wait,
        .pre_shutdown_trigger = pgraph_null_pre_shutdown_trigger,
        .pre_shutdown_wait = pgraph_null_pre_shutdown_wait,
        .process_pending = pgraph_null_process_pending,
        .process_pending_reports = pgraph_null_process_pending_reports,
        .surface_update = pgraph_null_surface_update,
    }
};

static void __attribute__((constructor)) register_renderer(void)
{
    pgraph_renderer_register(&pgraph_null_renderer);
}
