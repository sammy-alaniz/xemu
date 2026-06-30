/*
 * QEMU Geforce NV2A implementation
 *
 * Copyright (c) 2012 espes
 * Copyright (c) 2015 Jannik Vogel
 * Copyright (c) 2018-2025 Matt Borgerson
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

#include "hw/xbox/nv2a/nv2a_int.h"
#include "qemu/main-loop.h"
#include "xemu-xbe.h"
#include "xemu-version.h"
#ifdef CONFIG_XEMU_BROWSER_BOOT
#include "ui/xemu-browser-display.h"
#endif

#ifdef CONFIG_XEMU_BROWSER_BOOT
#define XEMU_NV2A_IRQ_TRACE_DEFAULT_LIMIT 512
#define XEMU_NV2A_IRQ_LINE_TRACE_DEFAULT_LIMIT 256
#else
#define XEMU_NV2A_IRQ_TRACE_DEFAULT_LIMIT 128
#define XEMU_NV2A_IRQ_LINE_TRACE_DEFAULT_LIMIT 128
#endif
#define XEMU_NV2A_IRQ_LINE_LOW_PRIORITY_TRACE_DEFAULT_LIMIT 32

static bool nv2a_boot_trace_enabled(void)
{
#ifdef CONFIG_XEMU_BROWSER_BOOT
    return true;
#else
    const char *value = getenv("XEMU_BOOT_TRACE");

    return value && value[0] && strcmp(value, "0");
#endif
}

static const char *nv2a_boot_trace_context(void)
{
    static bool initialized;
    static char context[64];
    const char *env_context = getenv("XEMU_BOOT_TRACE_CONTEXT");
    const char *paths[] = {
        "/xemu-fixtures/boot_trace_context.txt",
        "/xemu-smoke/boot_trace_context.txt",
        "/xemu-smoke-out/boot_trace_context.txt",
        NULL,
    };

    if (initialized) {
        return context;
    }
    initialized = true;

    if (env_context && env_context[0]) {
        g_strlcpy(context, env_context, sizeof(context));
        return context;
    }

    for (int i = 0; paths[i]; i++) {
        FILE *fp = fopen(paths[i], "r");

        if (!fp) {
            continue;
        }

        if (fgets(context, sizeof(context), fp)) {
            context[strcspn(context, "\r\n")] = 0;
        }
        fclose(fp);

        if (context[0]) {
            return context;
        }
    }

#ifdef CONFIG_XEMU_BROWSER_BOOT
    g_strlcpy(context, "browser-boot", sizeof(context));
#else
    g_strlcpy(context, "native-headless", sizeof(context));
#endif
    return context;
}

static int64_t nv2a_irq_trace_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_NV2A_IRQ_TRACE_DEFAULT_LIMIT;
    const char *value;
    char *end = NULL;

    if (initialized) {
        return limit;
    }
    initialized = true;

    value = getenv("XEMU_BOOT_TRACE_NV2A_IRQ_LIMIT");
    if (!value || !value[0]) {
        return limit;
    }

    limit = g_ascii_strtoll(value, &end, 10);
    if (end == value || limit < 0) {
        limit = XEMU_NV2A_IRQ_TRACE_DEFAULT_LIMIT;
    }

    return limit;
}

static void nv2a_boot_trace_mark(const char *message)
{
    if (nv2a_boot_trace_enabled()) {
        fprintf(stderr, "BOOT_MARK %s\n", message);
    }
}

static int64_t nv2a_irq_line_trace_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_NV2A_IRQ_LINE_TRACE_DEFAULT_LIMIT;
    const char *value;
    char *end = NULL;

    if (initialized) {
        return limit;
    }
    initialized = true;

    value = getenv("XEMU_BOOT_TRACE_NV2A_IRQ_LINE_LIMIT");
    if (!value || !value[0]) {
        return limit;
    }

    limit = g_ascii_strtoll(value, &end, 10);
    if (end == value || limit < 0) {
        limit = XEMU_NV2A_IRQ_LINE_TRACE_DEFAULT_LIMIT;
    }

    return limit;
}

static int64_t nv2a_irq_line_low_priority_trace_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_NV2A_IRQ_LINE_LOW_PRIORITY_TRACE_DEFAULT_LIMIT;
    const char *value;
    char *end = NULL;

    if (initialized) {
        return limit;
    }
    initialized = true;

    value = getenv("XEMU_BOOT_TRACE_NV2A_IRQ_LINE_LOW_PRIORITY_LIMIT");
    if (!value || !value[0]) {
        value = getenv("XEMU_BOOT_TRACE_NV2A_IRQ_LINE_PCRTC_LIMIT");
    }
    if (!value || !value[0]) {
        return limit;
    }

    limit = g_ascii_strtoll(value, &end, 10);
    if (end == value || limit < 0) {
        limit = XEMU_NV2A_IRQ_LINE_LOW_PRIORITY_TRACE_DEFAULT_LIMIT;
    }

    return limit;
}

static const char *nv2a_irq_line_reason(NV2AState *d, bool *priority)
{
    bool pgraph_waiting = qatomic_read(&d->pgraph.waiting_for_nop) ||
                          qatomic_read(&d->pgraph.waiting_for_flip) ||
                          qatomic_read(&d->pgraph.waiting_for_context_switch);

    if (d->pgraph.pending_interrupts ||
        (d->pmc.pending_interrupts & NV_PMC_INTR_0_PGRAPH) ||
        pgraph_waiting) {
        *priority = true;
        return "pgraph";
    }

    if (d->pfifo.pending_interrupts ||
        (d->pmc.pending_interrupts & NV_PMC_INTR_0_PFIFO)) {
        *priority = true;
        return "pfifo";
    }

    *priority = false;
    if (d->pcrtc.pending_interrupts ||
        (d->pmc.pending_interrupts & NV_PMC_INTR_0_PCRTC)) {
        return "pcrtc";
    }
    if (d->pmc.pending_interrupts || d->pmc.enabled_interrupts) {
        return "pmc";
    }
    return "idle";
}

static void nv2a_boot_trace_irq_line(NV2AState *d, bool asserted)
{
    static uint64_t count;
    static uint64_t low_priority_count;
    static bool last_known;
    static bool last_asserted;
    static uint32_t last_pmc_pending;
    static uint32_t last_pmc_enabled;
    static uint32_t last_pfifo_pending;
    static uint32_t last_pcrtc_pending;
    static uint32_t last_pgraph_pending;
    int64_t limit;
    bool priority = false;
    const char *reason;

    if (!nv2a_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_dashboard_observed()) {
        return;
    }

    reason = nv2a_irq_line_reason(d, &priority);

    if (last_known && last_asserted == asserted &&
        last_pmc_pending == d->pmc.pending_interrupts &&
        last_pmc_enabled == d->pmc.enabled_interrupts &&
        last_pfifo_pending == d->pfifo.pending_interrupts &&
        last_pcrtc_pending == d->pcrtc.pending_interrupts &&
        last_pgraph_pending == d->pgraph.pending_interrupts) {
        return;
    }

    if (!priority) {
        int64_t low_priority_limit =
            nv2a_irq_line_low_priority_trace_limit();

        if (low_priority_limit == 0 ||
            low_priority_count >= (uint64_t)low_priority_limit) {
            return;
        }
        low_priority_count++;
    }

    limit = nv2a_irq_line_trace_limit();
    if (limit == 0 || count >= (uint64_t)limit) {
        return;
    }
    count++;

    last_known = true;
    last_asserted = asserted;
    last_pmc_pending = d->pmc.pending_interrupts;
    last_pmc_enabled = d->pmc.enabled_interrupts;
    last_pfifo_pending = d->pfifo.pending_interrupts;
    last_pcrtc_pending = d->pcrtc.pending_interrupts;
    last_pgraph_pending = d->pgraph.pending_interrupts;

    fprintf(stderr,
            "BOOT_MARK b6 nv2a=irq-line context=%s"
            " seq=%" PRIu64
            " line=%s"
            " reason=%s"
            " priority=%s"
            " pmc_pending=0x%08x"
            " pmc_enabled=0x%08x"
            " pfifo_pending=0x%08x"
            " pfifo_enabled=0x%08x"
            " pcrtc_pending=0x%08x"
            " pcrtc_enabled=0x%08x"
            " pgraph_pending=0x%08x"
            " pgraph_enabled=0x%08x\n",
            nv2a_boot_trace_context(), count,
            asserted ? "assert" : "deassert",
            reason, priority ? "yes" : "no",
            d->pmc.pending_interrupts, d->pmc.enabled_interrupts,
            d->pfifo.pending_interrupts, d->pfifo.enabled_interrupts,
            d->pcrtc.pending_interrupts, d->pcrtc.enabled_interrupts,
            d->pgraph.pending_interrupts, d->pgraph.enabled_interrupts);
}

void nv2a_irq_trace_capture(NV2AState *d, NV2AIrqTraceState *state)
{
    state->pmc_pending = d->pmc.pending_interrupts;
    state->pmc_enabled = d->pmc.enabled_interrupts;
    state->pcrtc_pending = d->pcrtc.pending_interrupts;
    state->pcrtc_enabled = d->pcrtc.enabled_interrupts;
    state->pgraph_pending = d->pgraph.pending_interrupts;
    state->pgraph_enabled = d->pgraph.enabled_interrupts;
}

void nv2a_boot_trace_irq_source(NV2AState *d, const char *source,
                                const char *op, uint64_t value,
                                const NV2AIrqTraceState *before)
{
    static uint64_t count;
    int64_t limit;

    if (!nv2a_boot_trace_enabled()) {
        return;
    }
    if (!xemu_xbe_boot_trace_dashboard_observed() &&
        !strcmp(source, "pcrtc") && !strcmp(op, "vblank-raise")) {
        return;
    }

    limit = nv2a_irq_trace_limit();
    if (limit == 0 || count >= (uint64_t)limit) {
        return;
    }
    count++;

    uint32_t dma_state = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_STATE];
    XemuXbeBootTraceNv2aWaitState wait_state = {
        .source = source,
        .op = op,
        .seq = count,
        .method = GET_MASK(dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD) << 2,
        .parameter = (uint32_t)value,
        .dma_get = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_GET],
        .dma_put = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUT],
        .dma_state_method =
            GET_MASK(dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD) << 2,
        .dma_state_count =
            GET_MASK(dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD_COUNT),
        .pmc_pending = d->pmc.pending_interrupts,
        .pmc_enabled = d->pmc.enabled_interrupts,
        .pfifo_pending = d->pfifo.pending_interrupts,
        .pfifo_enabled = d->pfifo.enabled_interrupts,
        .pcrtc_pending = d->pcrtc.pending_interrupts,
        .pcrtc_enabled = d->pcrtc.enabled_interrupts,
        .pgraph_pending = d->pgraph.pending_interrupts,
        .pgraph_enabled = d->pgraph.enabled_interrupts,
        .pfifo_known = false,
        .pgraph_waiting_flip = qatomic_read(&d->pgraph.waiting_for_flip),
        .pgraph_waiting_nop = qatomic_read(&d->pgraph.waiting_for_nop),
        .pgraph_waiting_context =
            qatomic_read(&d->pgraph.waiting_for_context_switch),
    };
    xemu_xbe_boot_trace_observe_nv2a_wait_state(&wait_state);

    fprintf(stderr,
            "BOOT_MARK b6 nv2a=irq-source context=%s"
            " seq=%" PRIu64
            " source=%s op=%s value=0x%08" PRIx64
            " pmc_pending_before=0x%08x"
            " pmc_enabled_before=0x%08x"
            " pmc_pending_after=0x%08x"
            " pmc_enabled_after=0x%08x"
            " pcrtc_pending_before=0x%08x"
            " pcrtc_enabled_before=0x%08x"
            " pcrtc_pending_after=0x%08x"
            " pcrtc_enabled_after=0x%08x"
            " pgraph_pending_before=0x%08x"
            " pgraph_enabled_before=0x%08x"
            " pgraph_pending_after=0x%08x"
            " pgraph_enabled_after=0x%08x"
            " pgraph_wait_nop=%s"
            " pgraph_wait_context=%s\n",
            nv2a_boot_trace_context(), count, source, op, value,
            before->pmc_pending, before->pmc_enabled,
            d->pmc.pending_interrupts, d->pmc.enabled_interrupts,
            before->pcrtc_pending, before->pcrtc_enabled,
            d->pcrtc.pending_interrupts, d->pcrtc.enabled_interrupts,
            before->pgraph_pending, before->pgraph_enabled,
            d->pgraph.pending_interrupts, d->pgraph.enabled_interrupts,
            d->pgraph.waiting_for_nop ? "yes" : "no",
            d->pgraph.waiting_for_context_switch ? "yes" : "no");
}

void nv2a_update_irq(NV2AState *d)
{
    /* PFIFO */
    if (d->pfifo.pending_interrupts & d->pfifo.enabled_interrupts) {
        d->pmc.pending_interrupts |= NV_PMC_INTR_0_PFIFO;
    } else {
        d->pmc.pending_interrupts &= ~NV_PMC_INTR_0_PFIFO;
    }

    /* PCRTC */
    if (d->pcrtc.pending_interrupts & d->pcrtc.enabled_interrupts) {
        d->pmc.pending_interrupts |= NV_PMC_INTR_0_PCRTC;
    } else {
        d->pmc.pending_interrupts &= ~NV_PMC_INTR_0_PCRTC;
    }

    /* PGRAPH */
    if (d->pgraph.pending_interrupts & d->pgraph.enabled_interrupts) {
        d->pmc.pending_interrupts |= NV_PMC_INTR_0_PGRAPH;
    } else {
        d->pmc.pending_interrupts &= ~NV_PMC_INTR_0_PGRAPH;
    }

    bool asserted = d->pmc.pending_interrupts && d->pmc.enabled_interrupts;

    nv2a_boot_trace_irq_line(d, asserted);

    if (asserted) {
        trace_nv2a_irq(d->pmc.pending_interrupts);
        pci_irq_assert(PCI_DEVICE(d));
    } else {
        pci_irq_deassert(PCI_DEVICE(d));
    }
}

DMAObject nv_dma_load(NV2AState *d, hwaddr dma_obj_address)
{
    assert(dma_obj_address < memory_region_size(&d->ramin));

    uint32_t *dma_obj = (uint32_t *)(d->ramin_ptr + dma_obj_address);
    uint32_t flags = ldl_le_p(dma_obj);
    uint32_t limit = ldl_le_p(dma_obj + 1);
    uint32_t frame = ldl_le_p(dma_obj + 2);

    return (DMAObject){
        .dma_class  = GET_MASK(flags, NV_DMA_CLASS),
        .dma_target = GET_MASK(flags, NV_DMA_TARGET),
        .address    = (frame & NV_DMA_ADDRESS) | GET_MASK(flags, NV_DMA_ADJUST),
        .limit      = limit,
    };
}

void *nv_dma_map(NV2AState *d, hwaddr dma_obj_address, hwaddr *len)
{
    DMAObject dma = nv_dma_load(d, dma_obj_address);

    /* TODO: Handle targets and classes properly */
    trace_nv2a_dma_map(dma_obj_address, dma.dma_class, dma.dma_target,
                       dma.address, dma.limit);
    dma.address &= 0x07FFFFFF;

    assert(dma.address < memory_region_size(d->vram));
    // assert(dma.address + dma.limit < memory_region_size(d->vram));
    *len = dma.limit;
    return d->vram_ptr + dma.address;
}

hwaddr nv_clip_gpu_tile_blit(NV2AState *d, hwaddr blit_base_address, hwaddr len)
{
    const uint32_t *regs = d->pfb.regs;
    hwaddr blit_end = blit_base_address + len;
    for (int i = 0; i < NV_NUM_GPU_TILES; ++i) {
        uint32_t base_and_flags = regs[NV_PFB_TILE_BASE_ADDRESS_AND_FLAGS(i)];
        if (!(base_and_flags & NV_PFB_TILE_FLAGS_VALID)) {
            continue;
        }

        uint32_t limit = regs[NV_PFB_TILE_LIMIT(i)];

        if (blit_base_address < limit && blit_end > limit) {
            // TODO: Determine HW behavior if tiles are consecutive.
            return limit + 1 - blit_base_address;
        }
    }

    return len;
}

const NV2ABlockInfo blocktable[NV_NUM_BLOCKS] = {
    #define ENTRY(NAME, LNAME, OFFSET, SIZE) [NV_##NAME] = {            \
        .name   = #NAME,                                                \
        .offset = OFFSET,                                               \
        .size   = SIZE,                                                 \
        .ops    = { .read = LNAME ## _read, .write = LNAME ## _write }, \
    }
    ENTRY(PMC,      pmc,      0x000000, 0x001000),
    ENTRY(PBUS,     pbus,     0x001000, 0x001000),
    ENTRY(PFIFO,    pfifo,    0x002000, 0x002000),
    ENTRY(PRMA,     prma,     0x007000, 0x001000),
    ENTRY(PVIDEO,   pvideo,   0x008000, 0x001000),
    ENTRY(PTIMER,   ptimer,   0x009000, 0x001000),
    ENTRY(PCOUNTER, pcounter, 0x00a000, 0x001000),
    ENTRY(PVPE,     pvpe,     0x00b000, 0x001000),
    ENTRY(PTV,      ptv,      0x00d000, 0x001000),
    ENTRY(PRMFB,    prmfb,    0x0a0000, 0x020000),
    ENTRY(PRMVIO,   prmvio,   0x0c0000, 0x001000),
    ENTRY(PFB,      pfb,      0x100000, 0x001000),
    ENTRY(PSTRAPS,  pstraps,  0x101000, 0x001000),
    ENTRY(PGRAPH,   pgraph,   0x400000, 0x002000),
    ENTRY(PCRTC,    pcrtc,    0x600000, 0x001000),
    ENTRY(PRMCIO,   prmcio,   0x601000, 0x001000),
    ENTRY(PRAMDAC,  pramdac,  0x680000, 0x001000),
    ENTRY(PRMDIO,   prmdio,   0x681000, 0x001000),
    // ENTRY(PRAMIN,   pramin,   0x700000, 0x100000),
    ENTRY(USER,     user,     0x800000, 0x800000),
};
#undef ENTRY

static int nv2a_get_bpp(VGACommonState *s)
{
    NV2AState *d = container_of(s, NV2AState, vga);

    int depth = s->cr[0x28] & 3;

    int bpp;
    switch (depth) {
    case 0:
        /* FIXME: This case is sometimes hit during early Xbox startup.
         *        Presumably a race-condition where VGA isn't initialized, yet.
         *        `bpp = 0` mimics old code that did `bpp = depth * 8;`.
         *        This works around the issue of this mode being unhandled.
         *        However, QEMU VGA uses a 4bpp mode if `bpp = 0`.
         *        We don't know if Xbox hardware would do the same. */
        bpp = 0;
        break;
    case 2:
        bpp = d->pramdac.general_control &
              NV_PRAMDAC_GENERAL_CONTROL_ALT_MODE_SEL ? 16 : 15;
        break;
    case 3:
        bpp = 32;
        break;
    default:
        /* This is only a fallback path */
        bpp = depth * 8;
        fprintf(stderr, "Unknown VGA depth: %d\n", depth);
        assert(!"Unknown VGA depth - check logs for depth value");
        break;
    }

    return bpp;
}

static void nv2a_get_params(VGACommonState *s, VGADisplayParams *params)
{
    NV2AState *d = container_of(s, NV2AState, vga);
    params->line_offset = (s->cr[0x13] | ((s->cr[0x19] & 0xe0) << 3) |
                           ((s->cr[0x25] & 0x20) << 6))
                          << 3;
    params->start_addr = d->pcrtc.start / 4;
    params->line_compare = s->cr[VGA_CRTC_LINE_COMPARE] |
                           ((s->cr[VGA_CRTC_OVERFLOW] & 0x10) << 4) |
                           ((s->cr[VGA_CRTC_MAX_SCAN] & 0x40) << 3);
}

const uint8_t *nv2a_get_dac_palette(void)
{
    return g_nv2a->puserdac.palette;
}

int nv2a_get_screen_off(void)
{
    return g_nv2a->vga.sr[VGA_SEQ_CLOCK_MODE] & VGA_SR01_SCREEN_OFF;
}

static bool nv2a_browser_surface_format(DisplaySurface *surface,
                                        unsigned int *bpp,
                                        unsigned int *format)
{
    switch (surface_format(surface)) {
    case PIXMAN_x8r8g8b8:
    case PIXMAN_a8r8g8b8:
        *bpp = 32;
        *format = NV097_SET_SURFACE_FORMAT_COLOR_LE_X8R8G8B8_Z8R8G8B8;
        return true;
    case PIXMAN_r5g6b5:
        *bpp = 16;
        *format = NV097_SET_SURFACE_FORMAT_COLOR_LE_R5G6B5;
        return true;
    case PIXMAN_x1r5g5b5:
        *bpp = 16;
        *format = NV097_SET_SURFACE_FORMAT_COLOR_LE_X1R5G5B5_Z1R5G5B5;
        return true;
    default:
        return false;
    }
}

static bool nv2a_browser_surface_nonempty(const uint8_t *data,
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
            }
        }
    }

    return false;
}

#ifndef CONFIG_XEMU_BROWSER_BOOT
static uint8_t nv2a_surface_scale_to_u8(uint32_t value, uint32_t max)
{
    return (uint8_t)((value * 255 + max / 2) / max);
}

static bool nv2a_surface_rgba_sha256(const uint8_t *data,
                                     unsigned int width,
                                     unsigned int height,
                                     unsigned int stride,
                                     unsigned int bpp,
                                     unsigned int format,
                                     char hash_hex[65])
{
    GChecksum *checksum;
    guchar digest[32];
    gsize digest_len = sizeof(digest);
    uint8_t rgba[4];

    if (!data || !width || !height || !stride ||
        (bpp != 16 && bpp != 32)) {
        return false;
    }

    checksum = g_checksum_new(G_CHECKSUM_SHA256);
    if (!checksum) {
        return false;
    }

    for (unsigned int y = 0; y < height; y++) {
        const uint8_t *row = data + y * stride;

        for (unsigned int x = 0; x < width; x++) {
            if (bpp == 32) {
                const uint8_t *pixel = row + x * 4;

                rgba[0] = pixel[2];
                rgba[1] = pixel[1];
                rgba[2] = pixel[0];
                rgba[3] = 0xff;
            } else {
                uint16_t pixel = lduw_le_p(row + x * 2);
                bool x1r5g5b5 =
                    format == NV097_SET_SURFACE_FORMAT_COLOR_LE_X1R5G5B5_Z1R5G5B5 ||
                    format == NV097_SET_SURFACE_FORMAT_COLOR_LE_X1R5G5B5_O1R5G5B5;

                rgba[0] = nv2a_surface_scale_to_u8(
                    (pixel >> (x1r5g5b5 ? 10 : 11)) & 0x1f, 31);
                rgba[1] = nv2a_surface_scale_to_u8(
                    (pixel >> 5) & (x1r5g5b5 ? 0x1f : 0x3f),
                    x1r5g5b5 ? 31 : 63);
                rgba[2] = nv2a_surface_scale_to_u8(pixel & 0x1f, 31);
                rgba[3] = 0xff;
            }

            g_checksum_update(checksum, rgba, sizeof(rgba));
        }
    }

    g_checksum_get_digest(checksum, digest, &digest_len);
    g_checksum_free(checksum);
    if (digest_len != sizeof(digest)) {
        return false;
    }

    for (size_t i = 0; i < sizeof(digest); i++) {
        snprintf(hash_hex + i * 2, 3, "%02x", digest[i]);
    }
    hash_hex[64] = 0;
    return true;
}

static void nv2a_native_reference_submit_console_surface(NV2AState *d)
{
    static bool emitted;
    static uint64_t frame_id;
    DisplaySurface *surface;
    const char *context;
    unsigned int width;
    unsigned int height;
    unsigned int stride;
    unsigned int bpp;
    unsigned int format;
    uint8_t *data;
    char hash_hex[65];

    if (emitted || !nv2a_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_executed()) {
        return;
    }

    context = nv2a_boot_trace_context();
    if (strcmp(context, "native-headless")) {
        return;
    }

    surface = qemu_console_surface(d->vga.con);
    if (!surface || surface_is_placeholder(surface) ||
        !nv2a_browser_surface_format(surface, &bpp, &format)) {
        return;
    }

    width = surface_width(surface);
    height = surface_height(surface);
    stride = surface_stride(surface);
    data = surface_data(surface);
    if (!data || width == 0 || height == 0 || stride == 0 ||
        !nv2a_browser_surface_nonempty(data, width, height, stride, bpp,
                                       format) ||
        !nv2a_surface_rgba_sha256(data, width, height, stride, bpp, format,
                                  hash_hex)) {
        return;
    }

    emitted = true;
    frame_id++;
    fprintf(stderr,
            "NATIVE_DASHBOARD_REFERENCE result=pass context=%s"
            " source=native-framebuffer"
            " hash=%s"
            " width=%u"
            " height=%u"
            " dashboard=xbe-executed"
            " frame=%" PRIu64
            " bpp=%u"
            " format=%u"
            " stride=%u"
            " build_id=%s\n",
            context, hash_hex, width, height, frame_id, bpp, format, stride,
            xemu_commit ? xemu_commit : "unknown");
}
#endif

#ifdef CONFIG_XEMU_BROWSER_BOOT
static bool nv2a_browser_trace_sample(unsigned int count)
{
    return count <= 8 || (count & (count - 1)) == 0;
}

static void nv2a_browser_trace_skip(const char *reason,
                                    unsigned int width,
                                    unsigned int height,
                                    unsigned int stride,
                                    unsigned int bpp,
                                    unsigned int format,
                                    pixman_format_code_t pixman_format)
{
    static unsigned int null_surface_count;
    static unsigned int placeholder_count;
    static unsigned int bad_format_count;
    static unsigned int empty_count;
    static unsigned int bad_geometry_count;
    unsigned int count;

    if (!strcmp(reason, "null-surface")) {
        count = ++null_surface_count;
    } else if (!strcmp(reason, "placeholder")) {
        count = ++placeholder_count;
    } else if (!strcmp(reason, "bad-format")) {
        count = ++bad_format_count;
    } else if (!strcmp(reason, "empty")) {
        count = ++empty_count;
    } else {
        count = ++bad_geometry_count;
    }

    if (!nv2a_browser_trace_sample(count)) {
        return;
    }

    fprintf(stderr,
            "BROWSER_DISPLAY_SCANOUT result=skip reason=%s count=%u "
            "width=%u height=%u stride=%u bpp=%u format=%u pixman=0x%x\n",
            reason, count, width, height, stride, bpp, format,
            pixman_format);
}

static uint32_t nv2a_browser_surface_sample_hash(const uint8_t *data,
                                                 unsigned int height,
                                                 unsigned int stride)
{
    uint32_t hash = 2166136261u;
    unsigned int step = MAX(stride / 64, 1u);

    for (unsigned int y = 0; y < height; y += MAX(height / 32, 1u)) {
        const uint8_t *row = data + y * stride;

        for (unsigned int x = 0; x < stride; x += step) {
            hash ^= row[x];
            hash *= 16777619u;
        }
    }

    return hash;
}

typedef enum XemuBrowserPcrtcVblankMode {
    XEMU_BROWSER_PCRTC_VBLANK_NORMAL,
    XEMU_BROWSER_PCRTC_VBLANK_OFF,
    XEMU_BROWSER_PCRTC_VBLANK_SUPPRESS_UNTIL_DASHBOARD,
    XEMU_BROWSER_PCRTC_VBLANK_SUPPRESS_UNTIL_ENTRY_READY,
} XemuBrowserPcrtcVblankMode;

static const char *nv2a_browser_pcrtc_vblank_mode_name(
    XemuBrowserPcrtcVblankMode mode)
{
    switch (mode) {
    case XEMU_BROWSER_PCRTC_VBLANK_OFF:
        return "off";
    case XEMU_BROWSER_PCRTC_VBLANK_SUPPRESS_UNTIL_DASHBOARD:
        return "suppress-until-dashboard-observed";
    case XEMU_BROWSER_PCRTC_VBLANK_SUPPRESS_UNTIL_ENTRY_READY:
        return "suppress-until-entry-ready";
    case XEMU_BROWSER_PCRTC_VBLANK_NORMAL:
    default:
        return "normal";
    }
}

static bool nv2a_browser_read_pcrtc_vblank_mode_file(char *buffer,
                                                     size_t buffer_len)
{
    const char *paths[] = {
        "/xemu-fixtures/pcrtc_vblank_mode.txt",
        "/xemu-smoke/pcrtc_vblank_mode.txt",
        "/xemu-smoke-out/pcrtc_vblank_mode.txt",
        NULL,
    };

    for (int i = 0; paths[i]; i++) {
        FILE *fp = fopen(paths[i], "r");

        if (!fp) {
            continue;
        }

        if (fgets(buffer, buffer_len, fp)) {
            fclose(fp);
            buffer[strcspn(buffer, "\r\n")] = 0;
            return buffer[0] != 0;
        }
        fclose(fp);
    }

    return false;
}

static XemuBrowserPcrtcVblankMode nv2a_browser_pcrtc_vblank_mode(void)
{
    static bool initialized;
    static XemuBrowserPcrtcVblankMode mode =
        XEMU_BROWSER_PCRTC_VBLANK_NORMAL;
    const char *value;
    char file_value[128];

    if (initialized) {
        return mode;
    }
    initialized = true;

    value = getenv("XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE");
    if ((!value || !value[0]) &&
        nv2a_browser_read_pcrtc_vblank_mode_file(file_value,
                                                 sizeof(file_value))) {
        value = file_value;
    }
    if (!value || !value[0] || !strcmp(value, "normal")) {
        mode = XEMU_BROWSER_PCRTC_VBLANK_NORMAL;
    } else if (!strcmp(value, "off")) {
        mode = XEMU_BROWSER_PCRTC_VBLANK_OFF;
    } else if (!strcmp(value, "suppress-until-dashboard-observed")) {
        mode = XEMU_BROWSER_PCRTC_VBLANK_SUPPRESS_UNTIL_DASHBOARD;
    } else if (!strcmp(value, "suppress-until-entry-ready")) {
        mode = XEMU_BROWSER_PCRTC_VBLANK_SUPPRESS_UNTIL_ENTRY_READY;
    } else {
        mode = XEMU_BROWSER_PCRTC_VBLANK_NORMAL;
    }

    return mode;
}

static bool nv2a_browser_pcrtc_vblank_should_raise(const char **reason)
{
    XemuBrowserPcrtcVblankMode mode = nv2a_browser_pcrtc_vblank_mode();

    switch (mode) {
    case XEMU_BROWSER_PCRTC_VBLANK_OFF:
        *reason = "diagnostic-off";
        return false;
    case XEMU_BROWSER_PCRTC_VBLANK_SUPPRESS_UNTIL_DASHBOARD:
        if (!xemu_xbe_boot_trace_dashboard_observed()) {
            *reason = "dashboard-not-observed";
            return false;
        }
        break;
    case XEMU_BROWSER_PCRTC_VBLANK_SUPPRESS_UNTIL_ENTRY_READY:
        if (!xemu_xbe_boot_trace_entry_ready()) {
            *reason = "entry-not-ready";
            return false;
        }
        break;
    case XEMU_BROWSER_PCRTC_VBLANK_NORMAL:
    default:
        break;
    }

    *reason = "allowed";
    return true;
}

static void nv2a_browser_trace_pcrtc_vblank_gate(NV2AState *d,
                                                 const char *action,
                                                 const char *reason)
{
    static uint64_t suppress_count;
    static uint64_t allow_count;
    uint64_t count;
    XemuBrowserPcrtcVblankMode mode = nv2a_browser_pcrtc_vblank_mode();

    if (mode == XEMU_BROWSER_PCRTC_VBLANK_NORMAL ||
        !nv2a_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_dashboard_observed()) {
        return;
    }

    if (!strcmp(action, "suppress")) {
        count = ++suppress_count;
        XemuXbeBootTraceNv2aWaitState wait_state = {
            .source = "pcrtc",
            .op = "vblank-suppress",
            .seq = count,
            .parameter = NV_PCRTC_INTR_0_VBLANK,
            .dma_get = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_GET],
            .dma_put = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUT],
            .pmc_pending = d->pmc.pending_interrupts,
            .pmc_enabled = d->pmc.enabled_interrupts,
            .pfifo_pending = d->pfifo.pending_interrupts,
            .pfifo_enabled = d->pfifo.enabled_interrupts,
            .pcrtc_pending = d->pcrtc.pending_interrupts,
            .pcrtc_enabled = d->pcrtc.enabled_interrupts,
            .pgraph_pending = d->pgraph.pending_interrupts,
            .pgraph_enabled = d->pgraph.enabled_interrupts,
            .pfifo_known = false,
            .pgraph_waiting_flip =
                qatomic_read(&d->pgraph.waiting_for_flip),
            .pgraph_waiting_nop =
                qatomic_read(&d->pgraph.waiting_for_nop),
            .pgraph_waiting_context =
                qatomic_read(&d->pgraph.waiting_for_context_switch),
        };
        xemu_xbe_boot_trace_observe_nv2a_wait_state(&wait_state);
        if (!nv2a_browser_trace_sample(count)) {
            return;
        }
    } else {
        count = ++allow_count;
        if (count != 1) {
            return;
        }
    }

    fprintf(stderr,
            "BOOT_MARK b6 nv2a=pcrtc-vblank-gate context=%s"
            " mode=%s action=%s reason=%s count=%" PRIu64
            " pmc_pending=0x%08x"
            " pmc_enabled=0x%08x"
            " pcrtc_pending=0x%08x"
            " pcrtc_enabled=0x%08x"
            " entry_ready=%s"
            " dashboard_observed=%s\n",
            nv2a_boot_trace_context(),
            nv2a_browser_pcrtc_vblank_mode_name(mode),
            action, reason, count,
            d->pmc.pending_interrupts, d->pmc.enabled_interrupts,
            d->pcrtc.pending_interrupts, d->pcrtc.enabled_interrupts,
            xemu_xbe_boot_trace_entry_ready() ? "yes" : "no",
            xemu_xbe_boot_trace_dashboard_observed() ? "yes" : "no");
}

static void nv2a_browser_submit_console_surface(NV2AState *d)
{
    static uint32_t last_hash;
    static unsigned int last_width;
    static unsigned int last_height;
    static unsigned int last_stride;
    static unsigned int last_bpp;
    static unsigned int submitted_frames;
    DisplaySurface *surface = qemu_console_surface(d->vga.con);
    unsigned int width;
    unsigned int height;
    unsigned int stride;
    unsigned int bpp;
    unsigned int format;
    uint8_t *data;
    size_t bytes;
    uint32_t hash;

    if (!surface) {
        nv2a_browser_trace_skip("null-surface", 0, 0, 0, 0, 0, 0);
        return;
    }
    if (surface_is_placeholder(surface)) {
        nv2a_browser_trace_skip("placeholder", surface_width(surface),
                                surface_height(surface),
                                surface_stride(surface), 0, 0,
                                surface_format(surface));
        return;
    }
    if (!nv2a_browser_surface_format(surface, &bpp, &format)) {
        nv2a_browser_trace_skip("bad-format", surface_width(surface),
                                surface_height(surface),
                                surface_stride(surface), 0, 0,
                                surface_format(surface));
        return;
    }

    width = surface_width(surface);
    height = surface_height(surface);
    stride = surface_stride(surface);
    data = surface_data(surface);
    if (!data || width == 0 || height == 0 || stride == 0) {
        nv2a_browser_trace_skip("bad-geometry", width, height, stride, bpp,
                                format, surface_format(surface));
        return;
    }

    bytes = (size_t)stride * height;
    if (bytes == 0 || bytes > SIZE_MAX) {
        nv2a_browser_trace_skip("bad-geometry", width, height, stride, bpp,
                                format, surface_format(surface));
        return;
    }
    if (!nv2a_browser_surface_nonempty(data, width, height, stride, bpp,
                                       format)) {
        nv2a_browser_trace_skip("empty", width, height, stride, bpp, format,
                                surface_format(surface));
        return;
    }

    hash = nv2a_browser_surface_sample_hash(data, height, stride);
    if (submitted_frames >= 16 &&
        hash == last_hash &&
        width == last_width &&
        height == last_height &&
        stride == last_stride &&
        bpp == last_bpp) {
        return;
    }

    if (xemu_browser_display_submit_frame(width, height, stride, bpp, format,
                                          data, bytes)) {
        submitted_frames++;
        last_hash = hash;
        last_width = width;
        last_height = height;
        last_stride = stride;
        last_bpp = bpp;
    }
}
#endif

static void nv2a_vga_gfx_update(void *opaque)
{
    VGACommonState *vga = opaque;
    vga->hw_ops->gfx_update(vga);

    NV2AState *d = container_of(vga, NV2AState, vga);
    NV2AIrqTraceState irq_before;
#ifdef CONFIG_XEMU_BROWSER_BOOT
    const char *pcrtc_vblank_reason = NULL;

    nv2a_browser_submit_console_surface(d);
#else
    nv2a_native_reference_submit_console_surface(d);
#endif
#ifdef CONFIG_XEMU_BROWSER_BOOT
    if (!nv2a_browser_pcrtc_vblank_should_raise(&pcrtc_vblank_reason)) {
        nv2a_browser_trace_pcrtc_vblank_gate(d, "suppress",
                                             pcrtc_vblank_reason);
        return;
    }
    nv2a_browser_trace_pcrtc_vblank_gate(d, "allow", pcrtc_vblank_reason);
#endif
    nv2a_irq_trace_capture(d, &irq_before);
    d->pcrtc.pending_interrupts |= NV_PCRTC_INTR_0_VBLANK;
    d->pcrtc.raster = 0;

    nv2a_update_irq(d);
    nv2a_boot_trace_irq_source(d, "pcrtc", "vblank-raise",
                               NV_PCRTC_INTR_0_VBLANK, &irq_before);
}

static void nv2a_init_memory(NV2AState *d, MemoryRegion *ram)
{
    /* xbox is UMA - vram *is* ram */
    d->vram = ram;

     /* PCI exposed vram */
    memory_region_init_alias(&d->vram_pci, OBJECT(d), "nv2a-vram-pci", d->vram,
                             0, memory_region_size(d->vram));
    pci_register_bar(PCI_DEVICE(d), 1, PCI_BASE_ADDRESS_MEM_PREFETCH, &d->vram_pci);


    /* RAMIN - should be in vram somewhere, but not quite sure where atm */
    memory_region_init_ram(&d->ramin, OBJECT(d), "nv2a-ramin", 0x100000, &error_fatal);
    /* memory_region_init_alias(&d->ramin, "nv2a-ramin", &d->vram,
                         memory_region_size(d->vram) - 0x100000,
                         0x100000); */

    memory_region_add_subregion(&d->mmio, 0x700000, &d->ramin);


    d->vram_ptr = memory_region_get_ram_ptr(d->vram);
    d->ramin_ptr = memory_region_get_ram_ptr(&d->ramin);

    memory_region_set_log(d->vram, true, DIRTY_MEMORY_NV2A);
    memory_region_set_log(d->vram, true, DIRTY_MEMORY_NV2A_TEX);
    memory_region_set_dirty(d->vram, 0, memory_region_size(d->vram));

    pgraph_init(d);

    /* fire up pfifo */
    qemu_thread_create(&d->pfifo.thread, "nv2a.pfifo_thread",
                       pfifo_thread, d, QEMU_THREAD_JOINABLE);
    nv2a_boot_trace_mark("b2 thread=nv2a-pfifo created");
}

static void nv2a_init_vga(NV2AState *d)
{
    VGACommonState *vga = &d->vga;
    vga->vram_size_mb = memory_region_size(d->vram) / MiB;

    vga_common_init(vga, OBJECT(d), &error_fatal);
    vga->get_bpp = nv2a_get_bpp;
    vga->get_params = nv2a_get_params;
    // vga->overlay_draw_line = nv2a_overlay_draw_line;

    d->hw_ops = *vga->hw_ops;
    d->hw_ops.gfx_update = nv2a_vga_gfx_update;
    vga->con = graphic_console_init(DEVICE(d), 0, &d->hw_ops, vga);

    /* hacky. swap out vga's vram */
    memory_region_destroy(&vga->vram);
    // memory_region_unref(&vga->vram); // FIXME: Is ths right?
    memory_region_init_alias(&vga->vram, OBJECT(d), "vga.vram",
                             d->vram, 0, memory_region_size(d->vram));
    vga->vram_ptr = memory_region_get_ram_ptr(&vga->vram);
    vga_dirty_log_start(vga);
}

static void nv2a_lock_fifo(NV2AState *d)
{
    qemu_mutex_lock(&d->pfifo.lock);
    qemu_cond_broadcast(&d->pfifo.fifo_cond);
    bql_unlock();
    qemu_cond_wait(&d->pfifo.fifo_idle_cond, &d->pfifo.lock);
    bql_lock();
    qemu_mutex_lock(&d->pgraph.lock);
}

static void nv2a_unlock_fifo(NV2AState *d)
{
    pfifo_kick(d);
    qemu_mutex_unlock(&d->pgraph.lock);
    qemu_mutex_unlock(&d->pfifo.lock);
}

static void nv2a_reset(NV2AState *d)
{
    nv2a_lock_fifo(d);
    bool halted = qatomic_read(&d->pfifo.halt);
    if (!halted) {
        qatomic_set(&d->pfifo.halt, true);
    }
    qemu_event_reset(&d->pgraph.flush_complete);
    qatomic_set(&d->pgraph.flush_pending, true);
    nv2a_unlock_fifo(d);
    bql_unlock();
    qemu_event_wait(&d->pgraph.flush_complete);
    bql_lock();
    nv2a_lock_fifo(d);
    if (!halted) {
        qatomic_set(&d->pfifo.halt, false);
    }

    memset(d->pfifo.regs, 0, sizeof(d->pfifo.regs));
    memset(d->pgraph.regs_, 0, sizeof(d->pgraph.regs_));
    memset(d->pvideo.regs, 0, sizeof(d->pvideo.regs));

    d->pcrtc.start = 0;
    d->pramdac.core_clock_coeff = 0x00011C01; /* 189MHz...? */
    d->pramdac.core_clock_freq = 233333324;
    d->pramdac.memory_clock_coeff = 0;
    d->pramdac.video_clock_coeff = 0x0003C20D; /* 25182Khz...? */

    d->pfifo.regs[NV_PFIFO_CACHE1_STATUS] |= NV_PFIFO_CACHE1_STATUS_LOW_MARK;

    vga_common_reset(&d->vga);
    /* seems to start in color mode */
    d->vga.msr = VGA_MIS_COLOR;

    d->pgraph.waiting_for_nop = false;
    d->pgraph.waiting_for_flip = false;
    d->pgraph.waiting_for_context_switch = false;

    d->pmc.pending_interrupts = 0;
    d->pfifo.pending_interrupts = 0;
    d->ptimer.pending_interrupts = 0;
    d->pcrtc.pending_interrupts = 0;

    for (int i = 0; i < 256; i++) {
        d->puserdac.palette[i*3]   = i;
        d->puserdac.palette[i*3+1] = i;
        d->puserdac.palette[i*3+2] = i;
    }

    nv2a_unlock_fifo(d);
}

static void nv2a_realize(PCIDevice *dev, Error **errp)
{
    NV2AState *d = NV2A_DEVICE(dev);

    /* setting subsystem ids again, see comment in nv2a_class_init() */
    pci_set_word(dev->config + PCI_SUBSYSTEM_VENDOR_ID, 0);
    pci_set_word(dev->config + PCI_SUBSYSTEM_ID, 0);
    dev->config[PCI_INTERRUPT_PIN] = 0x01;

    /* mmio */
    memory_region_init(&d->mmio, OBJECT(dev), "nv2a-mmio", 0x1000000);
    pci_register_bar(PCI_DEVICE(d), 0, PCI_BASE_ADDRESS_SPACE_MEMORY, &d->mmio);

    for (int i=0; i < ARRAY_SIZE(blocktable); i++) {
        if (!blocktable[i].name) continue;
        memory_region_init_io(&d->block_mmio[i], OBJECT(dev),
                              &blocktable[i].ops, d,
                              blocktable[i].name, blocktable[i].size);
        memory_region_add_subregion(&d->mmio, blocktable[i].offset,
                                    &d->block_mmio[i]);
    }

    qemu_mutex_init(&d->pfifo.lock);
    qemu_cond_init(&d->pfifo.fifo_cond);
    qemu_cond_init(&d->pfifo.fifo_idle_cond);
}

static void nv2a_exitfn(PCIDevice *dev)
{
    NV2AState *d;
    d = NV2A_DEVICE(dev);

    d->exiting = true;

    qemu_cond_broadcast(&d->pfifo.fifo_cond);
    qemu_thread_join(&d->pfifo.thread);

    pgraph_destroy(&d->pgraph);
}

static void nv2a_reset_hold(Object *obj, ResetType type)
{
    NV2AState *s = NV2A_DEVICE(obj);
    nv2a_reset(s);
}

// Note: This is handled as a VM state change and not as a `pre_save` callback
// because we want to halt the FIFO before any VM state is saved/restored to
// avoid corruption.
static void nv2a_vm_state_change(void *opaque, bool running, RunState state)
{
    NV2AState *d = opaque;
    if (state == RUN_STATE_SAVE_VM) {
        nv2a_lock_fifo(d);
        qatomic_set(&d->pfifo.halt, true);
        pgraph_pre_savevm_trigger(d);
        nv2a_unlock_fifo(d);
        bql_unlock();
        pgraph_pre_savevm_wait(d);
        bql_lock();
        nv2a_lock_fifo(d);
    } else if (state == RUN_STATE_RESTORE_VM) {
        nv2a_lock_fifo(d);
        qatomic_set(&d->pfifo.halt, true);
        nv2a_unlock_fifo(d);
    } else if (state == RUN_STATE_RUNNING) {
        nv2a_lock_fifo(d);
        qatomic_set(&d->pfifo.halt, false);
        nv2a_unlock_fifo(d);
    } else if (state == RUN_STATE_SHUTDOWN) {
        nv2a_lock_fifo(d);
        pgraph_pre_shutdown_trigger(d);
        nv2a_unlock_fifo(d);
        bql_unlock();
        pgraph_pre_shutdown_wait(d);
        bql_lock();
    }
}

static int nv2a_post_save(void *opaque)
{
    NV2AState *d = opaque;
    nv2a_unlock_fifo(d);
    return 0;
}

static int nv2a_pre_load(void *opaque)
{
    NV2AState *d = opaque;
    nv2a_lock_fifo(d);
    return 0;
}

static int nv2a_post_load(void *opaque, int version_id)
{
    NV2AState *d = opaque;
    qatomic_set(&d->pgraph.flush_pending, true);
    nv2a_unlock_fifo(d);
    return 0;
}

const VMStateDescription vmstate_nv2a_pgraph_vertex_attributes = {
    .name = "nv2a/pgraph/vertex-attr",
    .version_id = 1,
    .minimum_version_id = 1,
    .fields = (VMStateField[]) {
        // FIXME
        VMSTATE_END_OF_LIST()
    }
};

static const VMStateDescription vmstate_nv2a = {
    .name = "nv2a",
    .version_id = 3,
    .minimum_version_id = 1,
    .post_save = nv2a_post_save,
    .post_load = nv2a_post_load,
    .pre_load = nv2a_pre_load,
    .fields = (VMStateField[]) {
        // FIXME: Split this up into subsections
        VMSTATE_PCI_DEVICE(parent_obj, NV2AState),
        VMSTATE_STRUCT(vga, NV2AState, 0, vmstate_vga_common, VGACommonState),
        VMSTATE_UINT32(pgraph.pending_interrupts, NV2AState),
        VMSTATE_UINT32(pgraph.enabled_interrupts, NV2AState),
        VMSTATE_UINT64(pgraph.context_surfaces_2d.object_instance, NV2AState),
        VMSTATE_UINT64(pgraph.context_surfaces_2d.dma_image_source, NV2AState),
        VMSTATE_UINT64(pgraph.context_surfaces_2d.dma_image_dest, NV2AState),
        VMSTATE_UINT32(pgraph.context_surfaces_2d.color_format, NV2AState),
        VMSTATE_UINT32(pgraph.context_surfaces_2d.source_pitch, NV2AState),
        VMSTATE_UINT32(pgraph.context_surfaces_2d.dest_pitch, NV2AState),
        VMSTATE_UINT64(pgraph.context_surfaces_2d.source_offset, NV2AState),
        VMSTATE_UINT64(pgraph.context_surfaces_2d.dest_offset, NV2AState),
        VMSTATE_UINT64(pgraph.image_blit.object_instance, NV2AState),
        VMSTATE_UINT64(pgraph.image_blit.context_surfaces, NV2AState),
        VMSTATE_UINT32(pgraph.image_blit.operation, NV2AState),
        VMSTATE_UINT32(pgraph.image_blit.in_x, NV2AState),
        VMSTATE_UINT32(pgraph.image_blit.in_y, NV2AState),
        VMSTATE_UINT32(pgraph.image_blit.out_x, NV2AState),
        VMSTATE_UINT32(pgraph.image_blit.out_y, NV2AState),
        VMSTATE_UINT32(pgraph.image_blit.width, NV2AState),
        VMSTATE_UINT32(pgraph.image_blit.height, NV2AState),
        VMSTATE_UINT64(pgraph.kelvin.object_instance, NV2AState),
        VMSTATE_UINT64(pgraph.dma_color, NV2AState),
        VMSTATE_UINT64(pgraph.dma_zeta, NV2AState),
        VMSTATE_BOOL(pgraph.surface_color.draw_dirty, NV2AState),
        VMSTATE_BOOL(pgraph.surface_zeta.draw_dirty, NV2AState),
        VMSTATE_BOOL(pgraph.surface_color.buffer_dirty, NV2AState),
        VMSTATE_BOOL(pgraph.surface_zeta.buffer_dirty, NV2AState),
        VMSTATE_BOOL(pgraph.surface_color.write_enabled_cache, NV2AState),
        VMSTATE_BOOL(pgraph.surface_zeta.write_enabled_cache, NV2AState),
        VMSTATE_UINT32(pgraph.surface_color.pitch, NV2AState),
        VMSTATE_UINT32(pgraph.surface_zeta.pitch, NV2AState),
        VMSTATE_UINT64(pgraph.surface_color.offset, NV2AState),
        VMSTATE_UINT64(pgraph.surface_zeta.offset, NV2AState),
        VMSTATE_UINT32(pgraph.surface_type, NV2AState),
        VMSTATE_UINT32(pgraph.surface_shape.z_format, NV2AState),
        VMSTATE_UINT32(pgraph.surface_shape.color_format, NV2AState),
        VMSTATE_UINT32(pgraph.surface_shape.zeta_format, NV2AState),
        VMSTATE_UINT32(pgraph.surface_shape.log_width, NV2AState),
        VMSTATE_UINT32(pgraph.surface_shape.log_height, NV2AState),
        VMSTATE_UINT32(pgraph.surface_shape.clip_x, NV2AState),
        VMSTATE_UINT32_V(pgraph.surface_shape.clip_y, NV2AState, 2),
        VMSTATE_UINT32(pgraph.surface_shape.clip_width, NV2AState),
        VMSTATE_UINT32(pgraph.surface_shape.clip_height, NV2AState),
        VMSTATE_UINT32(pgraph.surface_shape.anti_aliasing, NV2AState),
        VMSTATE_UINT32(pgraph.last_surface_shape.z_format, NV2AState),
        VMSTATE_UINT32(pgraph.last_surface_shape.color_format, NV2AState),
        VMSTATE_UINT32(pgraph.last_surface_shape.zeta_format, NV2AState),
        VMSTATE_UINT32(pgraph.last_surface_shape.log_width, NV2AState),
        VMSTATE_UINT32(pgraph.last_surface_shape.log_height, NV2AState),
        VMSTATE_UINT32(pgraph.last_surface_shape.clip_x, NV2AState),
        VMSTATE_UINT32_V(pgraph.last_surface_shape.clip_y, NV2AState, 2),
        VMSTATE_UINT32(pgraph.last_surface_shape.clip_width, NV2AState),
        VMSTATE_UINT32(pgraph.last_surface_shape.clip_height, NV2AState),
        VMSTATE_UINT32(pgraph.last_surface_shape.anti_aliasing, NV2AState),
        VMSTATE_UINT64(pgraph.dma_a, NV2AState),
        VMSTATE_UINT64(pgraph.dma_b, NV2AState),
        VMSTATE_UINT64(pgraph.dma_state, NV2AState),
        VMSTATE_UINT64(pgraph.dma_notifies, NV2AState),
        VMSTATE_UINT64(pgraph.dma_semaphore, NV2AState),
        VMSTATE_UINT64(pgraph.dma_report, NV2AState),
        VMSTATE_UINT64(pgraph.report_offset, NV2AState),
        VMSTATE_UINT64(pgraph.dma_vertex_a, NV2AState),
        VMSTATE_UINT64(pgraph.dma_vertex_b, NV2AState),
        VMSTATE_UINT32(pgraph.primitive_mode, NV2AState),
        VMSTATE_UINT32_ARRAY(pgraph.vertex_state_shader_v0, NV2AState, 4),
        VMSTATE_UINT32_2DARRAY(pgraph.program_data, NV2AState, NV2A_MAX_TRANSFORM_PROGRAM_LENGTH, VSH_TOKEN_SIZE),
        VMSTATE_UINT32_2DARRAY(pgraph.vsh_constants, NV2AState, NV2A_VERTEXSHADER_CONSTANTS, 4),
        VMSTATE_BOOL_ARRAY(pgraph.vsh_constants_dirty, NV2AState, NV2A_VERTEXSHADER_CONSTANTS),
        VMSTATE_UINT32_2DARRAY(pgraph.ltctxa, NV2AState, NV2A_LTCTXA_COUNT, 4),
        VMSTATE_BOOL_ARRAY(pgraph.ltctxa_dirty, NV2AState, NV2A_LTCTXA_COUNT),
        VMSTATE_UINT32_2DARRAY(pgraph.ltctxb, NV2AState, NV2A_LTCTXB_COUNT, 4),
        VMSTATE_BOOL_ARRAY(pgraph.ltctxb_dirty, NV2AState, NV2A_LTCTXB_COUNT),
        VMSTATE_UINT32_2DARRAY(pgraph.ltc1, NV2AState, NV2A_LTC1_COUNT, 4),
        VMSTATE_BOOL_ARRAY(pgraph.ltc1_dirty, NV2AState, NV2A_LTC1_COUNT),
        VMSTATE_STRUCT_ARRAY(pgraph.vertex_attributes, NV2AState, NV2A_VERTEXSHADER_ATTRIBUTES, 1, vmstate_nv2a_pgraph_vertex_attributes, VertexAttribute),
        VMSTATE_UINT32(pgraph.inline_array_length, NV2AState),
        VMSTATE_UINT32_SUB_ARRAY(pgraph.inline_array, NV2AState, 0, NV2A_MAX_BATCH_LENGTH_V2),
        VMSTATE_UINT32_SUB_ARRAY_V(pgraph.inline_array, NV2AState, NV2A_MAX_BATCH_LENGTH_V2, NV2A_MAX_BATCH_LENGTH - NV2A_MAX_BATCH_LENGTH_V2, 3),
        VMSTATE_UINT32(pgraph.inline_elements_length, NV2AState), // fixme
        VMSTATE_UINT32_SUB_ARRAY(pgraph.inline_elements, NV2AState, 0, NV2A_MAX_BATCH_LENGTH_V2),
        VMSTATE_UINT32_SUB_ARRAY_V(pgraph.inline_elements, NV2AState, NV2A_MAX_BATCH_LENGTH_V2, NV2A_MAX_BATCH_LENGTH - NV2A_MAX_BATCH_LENGTH_V2, 3),
        VMSTATE_UINT32(pgraph.inline_buffer_length, NV2AState), // fixme
        VMSTATE_UINT32(pgraph.draw_arrays_length, NV2AState),
        VMSTATE_UINT32(pgraph.draw_arrays_max_count, NV2AState),
        VMSTATE_INT32_ARRAY(pgraph.draw_arrays_start, NV2AState, 1250),
        VMSTATE_INT32_ARRAY(pgraph.draw_arrays_count, NV2AState, 1250),
        VMSTATE_UINT32_ARRAY(pgraph.regs_, NV2AState, 0x2000),
        VMSTATE_UINT32(pmc.pending_interrupts, NV2AState),
        VMSTATE_UINT32(pmc.enabled_interrupts, NV2AState),
        VMSTATE_UINT32(pfifo.pending_interrupts, NV2AState),
        VMSTATE_UINT32(pfifo.enabled_interrupts, NV2AState),
        VMSTATE_UINT32_ARRAY(pfifo.regs, NV2AState, 0x2000),
        VMSTATE_UINT32_ARRAY(pvideo.regs, NV2AState, 0x1000),
        VMSTATE_UINT32(ptimer.pending_interrupts, NV2AState),
        VMSTATE_UINT32(ptimer.enabled_interrupts, NV2AState),
        VMSTATE_UINT32(ptimer.numerator, NV2AState),
        VMSTATE_UINT32(ptimer.denominator, NV2AState),
        VMSTATE_UINT32(ptimer.alarm_time, NV2AState),
        VMSTATE_UINT32_ARRAY(pfb.regs, NV2AState, 0x1000),
        VMSTATE_UINT32(pcrtc.pending_interrupts, NV2AState),
        VMSTATE_UINT32(pcrtc.enabled_interrupts, NV2AState),
        VMSTATE_UINT64(pcrtc.start, NV2AState),
        VMSTATE_UINT32(pramdac.core_clock_coeff, NV2AState),
        VMSTATE_UINT64(pramdac.core_clock_freq, NV2AState),
        VMSTATE_UINT32(pramdac.memory_clock_coeff, NV2AState),
        VMSTATE_UINT32(pramdac.video_clock_coeff, NV2AState),
        VMSTATE_UINT16(puserdac.write_mode_address, NV2AState),
        VMSTATE_UINT8_ARRAY(puserdac.palette, NV2AState, 256*3),
        VMSTATE_BOOL(pgraph.waiting_for_flip, NV2AState),
        VMSTATE_BOOL(pgraph.waiting_for_nop, NV2AState),
        VMSTATE_UNUSED(1),
        VMSTATE_BOOL(pgraph.waiting_for_context_switch, NV2AState),
        VMSTATE_END_OF_LIST()
    },
};

static void nv2a_class_init(ObjectClass *klass, const void *data)
{
    DeviceClass *dc = DEVICE_CLASS(klass);
    ResettableClass *rc = RESETTABLE_CLASS(klass);
    PCIDeviceClass *k = PCI_DEVICE_CLASS(klass);

    k->vendor_id = PCI_VENDOR_ID_NVIDIA;
    k->device_id = PCI_DEVICE_ID_NVIDIA_GEFORCE_NV2A;
    k->revision  = 0xA1;
    k->class_id  = PCI_CLASS_DISPLAY_VGA;
    /* When both subsystem ids are set to 0, QEMU sets them to its own
     * default values. However we set them anyway in case upstream decides
     * to change this behavior. */
    k->subsystem_vendor_id = 0;
    k->subsystem_id = 0;
    k->realize   = nv2a_realize;
    k->exit      = nv2a_exitfn;

    rc->phases.hold = nv2a_reset_hold;

    dc->desc = "GeForce NV2A Integrated Graphics";
    dc->vmsd = &vmstate_nv2a;
}

static const TypeInfo nv2a_info = {
    .name          = "nv2a",
    .parent        = TYPE_PCI_DEVICE,
    .instance_size = sizeof(NV2AState),
    .class_init    = nv2a_class_init,
    .interfaces          = (InterfaceInfo[]) {
        { INTERFACE_CONVENTIONAL_PCI_DEVICE },
        { },
    },
};

static void nv2a_register(void)
{
    type_register_static(&nv2a_info);
}
type_init(nv2a_register);

void nv2a_init(PCIBus *bus, int devfn, MemoryRegion *ram)
{
    PCIDevice *dev = pci_create_simple(bus, devfn, "nv2a");
    NV2AState *d = NV2A_DEVICE(dev);
    nv2a_init_memory(d, ram);
    nv2a_init_vga(d);
    qemu_add_vm_change_state_handler(nv2a_vm_state_change, d);
}
