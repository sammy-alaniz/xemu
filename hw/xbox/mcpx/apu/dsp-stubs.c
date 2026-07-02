/*
 * Browser boot profile stubs for the MCPX DSP blocks.
 *
 * The first browser target keeps audio disabled and only needs the APU device
 * to realize cleanly enough for boot-path instrumentation.
 */

#include "qemu/osdep.h"
#include "apu_int.h"
#include "dsp/gp_ep.h"

static uint64_t dsp_stub_read(void *opaque, hwaddr addr, unsigned int size)
{
    return 0;
}

static void dsp_stub_write(void *opaque, hwaddr addr, uint64_t val,
                           unsigned int size)
{
}

const MemoryRegionOps gp_ops = {
    .read = dsp_stub_read,
    .write = dsp_stub_write,
};

const MemoryRegionOps ep_ops = {
    .read = dsp_stub_read,
    .write = dsp_stub_write,
};

void mcpx_apu_dsp_init(MCPXAPUState *d)
{
}

void mcpx_apu_update_dsp_preference(MCPXAPUState *d)
{
}

void mcpx_apu_dsp_frame(MCPXAPUState *d,
                        float mixbins[NUM_MIXBINS][NUM_SAMPLES_PER_FRAME])
{
}

void dsp_invalidate_opcache(DSPState *dsp)
{
}

void dsp_sync_to_vm(DSPState *dsp)
{
}

void dsp_sync_from_vm(DSPState *dsp)
{
}
