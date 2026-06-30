/*
 * QEMU Geforce NV2A implementation
 *
 * Copyright (c) 2012 espes
 * Copyright (c) 2015 Jannik Vogel
 * Copyright (c) 2018-2021 Matt Borgerson
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

#include "nv2a_int.h"

#ifdef CONFIG_XEMU_BROWSER_BOOT
#define XEMU_NV2A_PMC_TRACE_DEFAULT_LIMIT 512
#else
#define XEMU_NV2A_PMC_TRACE_DEFAULT_LIMIT 64
#endif

static bool pmc_boot_trace_enabled(void)
{
#ifdef CONFIG_XEMU_BROWSER_BOOT
    return true;
#else
    const char *value = getenv("XEMU_BOOT_TRACE");

    return value && value[0] && strcmp(value, "0");
#endif
}

static const char *pmc_boot_trace_context(void)
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

static int64_t pmc_boot_trace_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_NV2A_PMC_TRACE_DEFAULT_LIMIT;
    const char *value;
    char *end = NULL;

    if (initialized) {
        return limit;
    }
    initialized = true;

    value = getenv("XEMU_BOOT_TRACE_NV2A_PMC_LIMIT");
    if (!value || !value[0]) {
        return limit;
    }

    limit = g_ascii_strtoll(value, &end, 10);
    if (end == value || limit < 0) {
        limit = XEMU_NV2A_PMC_TRACE_DEFAULT_LIMIT;
    }

    return limit;
}

static const char *pmc_boot_trace_reg_name(hwaddr addr)
{
    switch (addr) {
    case NV_PMC_INTR_0:
        return "NV_PMC_INTR_0";
    case NV_PMC_INTR_EN_0:
        return "NV_PMC_INTR_EN_0";
    default:
        return "unknown";
    }
}

static bool pmc_boot_trace_addr(hwaddr addr)
{
    return addr == NV_PMC_INTR_0 || addr == NV_PMC_INTR_EN_0;
}

typedef struct PmcBootTraceCpuContext {
    bool known;
    const char *source;
    const char *mode;
    uint32_t cpl;
    uint64_t eip;
    uint64_t esp;
    uint64_t eflags;
    uint64_t hflags;
    uint32_t cs_selector;
    uint32_t interrupt_request;
    bool interrupts_enabled;
    bool irq_inhibited;
    bool halted;
    bool exit_request;
    int32_t exception_index;
} PmcBootTraceCpuContext;

static const char *pmc_boot_trace_bool_str(bool value)
{
    return value ? "yes" : "no";
}

static void pmc_boot_trace_capture_cpu(PmcBootTraceCpuContext *ctx)
{
    memset(ctx, 0, sizeof(*ctx));
    ctx->source = "none";
    ctx->mode = "unsupported";
    ctx->exception_index = -1;

#if defined(TARGET_I386)
    CPUState *cs = current_cpu;
    X86CPU *cpu;
    CPUX86State *env;

    if (cs) {
        ctx->source = "current-cpu";
    } else {
        cs = qemu_get_cpu(0);
        ctx->source = cs ? "cpu0" : "none";
    }
    if (!cs) {
        ctx->mode = "no-cpu";
        return;
    }

    cpu = X86_CPU(cs);
    env = &cpu->env;

    ctx->known = true;
    ctx->mode = (env->hflags & HF_CS64_MASK) ? "long" :
                (env->hflags & HF_CS32_MASK) ? "protected32" :
                (env->cr[0] & CR0_PE_MASK) ? "protected16" :
                "real";
    ctx->cpl = env->hflags & HF_CPL_MASK;
    ctx->eip = env->eip;
    ctx->esp = env->regs[R_ESP];
    ctx->eflags = cpu_compute_eflags(env);
    ctx->hflags = env->hflags;
    ctx->cs_selector = env->segs[R_CS].selector;
    ctx->interrupt_request = cs->interrupt_request;
    ctx->interrupts_enabled = ctx->eflags & IF_MASK;
    ctx->irq_inhibited = ctx->hflags & HF_INHIBIT_IRQ_MASK;
    ctx->halted = cs->halted;
    ctx->exit_request = cs->exit_request;
    ctx->exception_index = cs->exception_index;
#else
    (void)ctx;
#endif
}

static void pmc_boot_trace_access(NV2AState *d,
                                  const char *op,
                                  hwaddr addr,
                                  unsigned int size,
                                  uint64_t value,
                                  uint32_t pmc_pending_before,
                                  uint32_t pmc_enabled_before)
{
    static uint64_t count;
    int64_t limit;
    PmcBootTraceCpuContext cpu_ctx;

    if (!pmc_boot_trace_enabled() || !pmc_boot_trace_addr(addr)) {
        return;
    }

    limit = pmc_boot_trace_limit();
    if (limit == 0 || count >= (uint64_t)limit) {
        return;
    }
    count++;
    pmc_boot_trace_capture_cpu(&cpu_ctx);

    fprintf(stderr,
            "BOOT_MARK b6 nv2a=pmc-access context=%s"
            " seq=%" PRIu64
            " op=%s reg=%s addr=0x%08" PRIx64
            " size=%u value=0x%08" PRIx64
            " pmc_pending_before=0x%08x"
            " pmc_enabled_before=0x%08x"
            " pmc_pending_after=0x%08x"
            " pmc_enabled_after=0x%08x"
            " pfifo_pending=0x%08x"
            " pfifo_enabled=0x%08x"
            " pcrtc_pending=0x%08x"
            " pcrtc_enabled=0x%08x"
            " pgraph_pending=0x%08x"
            " pgraph_enabled=0x%08x"
            " ptimer_pending=0x%08x"
            " ptimer_enabled=0x%08x"
            " cpu_known=%s"
            " cpu_source=%s"
            " cpu_mode=%s"
            " cpl=%" PRIu32
            " eip=0x%08" PRIx64
            " cs=0x%04" PRIx32
            " esp=0x%08" PRIx64
            " eflags=0x%08" PRIx64
            " interrupts_enabled=%s"
            " irq_inhibited=%s"
            " cpu_interrupt_request=0x%08" PRIx32
            " pending_interrupt=%s"
            " cpu_halted=%s"
            " cpu_exit_request=%s"
            " cpu_exception_index=%" PRId32 "\n",
            pmc_boot_trace_context(), count, op, pmc_boot_trace_reg_name(addr),
            (uint64_t)addr, size, value, pmc_pending_before,
            pmc_enabled_before, d->pmc.pending_interrupts,
            d->pmc.enabled_interrupts, d->pfifo.pending_interrupts,
            d->pfifo.enabled_interrupts, d->pcrtc.pending_interrupts,
            d->pcrtc.enabled_interrupts, d->pgraph.pending_interrupts,
            d->pgraph.enabled_interrupts, d->ptimer.pending_interrupts,
            d->ptimer.enabled_interrupts,
            pmc_boot_trace_bool_str(cpu_ctx.known),
            cpu_ctx.source, cpu_ctx.mode, cpu_ctx.cpl, cpu_ctx.eip,
            cpu_ctx.cs_selector, cpu_ctx.esp, cpu_ctx.eflags,
            pmc_boot_trace_bool_str(cpu_ctx.interrupts_enabled),
            pmc_boot_trace_bool_str(cpu_ctx.irq_inhibited),
            cpu_ctx.interrupt_request,
            pmc_boot_trace_bool_str(cpu_ctx.interrupt_request != 0),
            pmc_boot_trace_bool_str(cpu_ctx.halted),
            pmc_boot_trace_bool_str(cpu_ctx.exit_request),
            cpu_ctx.exception_index);
}

/* PMC - card master control */
uint64_t pmc_read(void *opaque, hwaddr addr, unsigned int size)
{
    NV2AState *d = (NV2AState *)opaque;
    uint32_t pmc_pending_before = d->pmc.pending_interrupts;
    uint32_t pmc_enabled_before = d->pmc.enabled_interrupts;

    uint64_t r = 0;
    switch (addr) {
    case NV_PMC_BOOT_0:
        /* chipset and stepping:
         * NV2A, A03, Rev 0 */

        r = 0x02A000A3;
        break;
    case NV_PMC_INTR_0:
        /* Shows which functional units have pending IRQ */
        r = d->pmc.pending_interrupts;
        break;
    case NV_PMC_INTR_EN_0:
        /* Selects which functional units can cause IRQs */
        r = d->pmc.enabled_interrupts;
        break;
    default:
        break;
    }

    nv2a_reg_log_read(NV_PMC, addr, size, r);
    pmc_boot_trace_access(d, "read", addr, size, r, pmc_pending_before,
                          pmc_enabled_before);
    return r;
}

void pmc_write(void *opaque, hwaddr addr, uint64_t val, unsigned int size)
{
    NV2AState *d = (NV2AState *)opaque;
    uint32_t pmc_pending_before = d->pmc.pending_interrupts;
    uint32_t pmc_enabled_before = d->pmc.enabled_interrupts;

    nv2a_reg_log_write(NV_PMC, addr, size, val);

    switch (addr) {
    case NV_PMC_INTR_0:
        /* the bits of the interrupts to clear are wrtten */
        d->pmc.pending_interrupts &= ~val;
        nv2a_update_irq(d);
        break;
    case NV_PMC_INTR_EN_0:
        d->pmc.enabled_interrupts = val;
        nv2a_update_irq(d);
        break;
    default:
        break;
    }

    pmc_boot_trace_access(d, "write", addr, size, val, pmc_pending_before,
                          pmc_enabled_before);
}
