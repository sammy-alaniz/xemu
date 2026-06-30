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

#include "nv2a_int.h"
#include "xemu-xbe.h"
#include "qemu/timer.h"

#define XEMU_NV2A_PFIFO_TRACE_DEFAULT_LIMIT 128
#define XEMU_NV2A_PFIFO_TRACE_WINDOW_DEFAULT_START 0x03880e00u
#define XEMU_NV2A_PFIFO_TRACE_WINDOW_DEFAULT_LIMIT 512

static bool pfifo_boot_trace_enabled(void)
{
#ifdef CONFIG_XEMU_BROWSER_BOOT
    return true;
#else
    const char *value = getenv("XEMU_BOOT_TRACE");

    return value && value[0] && strcmp(value, "0");
#endif
}

static void pfifo_boot_trace_mark(const char *message)
{
    if (pfifo_boot_trace_enabled()) {
        fprintf(stderr, "BOOT_MARK %s\n", message);
    }
}

static bool can_fifo_access(NV2AState *d);

static const char *pfifo_boot_trace_context(void)
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

static int64_t pfifo_boot_trace_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_NV2A_PFIFO_TRACE_DEFAULT_LIMIT;
    const char *value;
    char *end = NULL;

    if (initialized) {
        return limit;
    }
    initialized = true;

    value = getenv("XEMU_BOOT_TRACE_NV2A_PFIFO_LIMIT");
    if (!value || !value[0]) {
        return limit;
    }

    limit = g_ascii_strtoll(value, &end, 10);
    if (end == value || limit < 0) {
        limit = XEMU_NV2A_PFIFO_TRACE_DEFAULT_LIMIT;
    }

    return limit;
}

static uint32_t pfifo_boot_trace_window_start(void)
{
    static bool initialized;
    static uint32_t start = XEMU_NV2A_PFIFO_TRACE_WINDOW_DEFAULT_START;
    const char *value;
    char *end = NULL;
    uint64_t parsed;

    if (initialized) {
        return start;
    }
    initialized = true;

    value = getenv("XEMU_BOOT_TRACE_NV2A_PFIFO_WINDOW_START");
    if (!value || !value[0]) {
        return start;
    }

    parsed = g_ascii_strtoull(value, &end, 0);
    if (end == value || parsed > UINT32_MAX) {
        start = XEMU_NV2A_PFIFO_TRACE_WINDOW_DEFAULT_START;
    } else {
        start = parsed;
    }

    return start;
}

static int64_t pfifo_boot_trace_window_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_NV2A_PFIFO_TRACE_WINDOW_DEFAULT_LIMIT;
    const char *value;
    char *end = NULL;

    if (initialized) {
        return limit;
    }
    initialized = true;

    value = getenv("XEMU_BOOT_TRACE_NV2A_PFIFO_WINDOW_LIMIT");
    if (!value || !value[0]) {
        return limit;
    }

    limit = g_ascii_strtoll(value, &end, 10);
    if (end == value || limit < 0) {
        limit = XEMU_NV2A_PFIFO_TRACE_WINDOW_DEFAULT_LIMIT;
    }

    return limit;
}

static void pfifo_boot_trace_window_state(NV2AState *d, const char *op,
                                          uint32_t method_entry,
                                          uint32_t parameter,
                                          size_t available,
                                          int64_t processed)
{
    static uint64_t count;
    int64_t limit;
    uint32_t dma_get = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_GET];

    if (!pfifo_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_dashboard_observed()) {
        return;
    }

    limit = pfifo_boot_trace_window_limit();
    if (limit == 0 || count >= (uint64_t)limit ||
        dma_get < pfifo_boot_trace_window_start()) {
        return;
    }
    count++;

    uint32_t push0 = d->pfifo.regs[NV_PFIFO_CACHE1_PUSH0];
    uint32_t push1 = d->pfifo.regs[NV_PFIFO_CACHE1_PUSH1];
    uint32_t pull0 = d->pfifo.regs[NV_PFIFO_CACHE1_PULL0];
    uint32_t status = d->pfifo.regs[NV_PFIFO_CACHE1_STATUS];
    uint32_t dma_push = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUSH];
    uint32_t dma_put = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUT];
    uint32_t dma_state = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_STATE];
    uint32_t method = method_entry & 0x1FFC;
    uint32_t subchannel =
        GET_MASK(method_entry, NV_PFIFO_CACHE1_METHOD_SUBCHANNEL);
    unsigned int channel_id = GET_MASK(push1, NV_PFIFO_CACHE1_PUSH1_CHID);
    bool push_access = GET_MASK(push0, NV_PFIFO_CACHE1_PUSH0_ACCESS);
    bool pull_access = GET_MASK(pull0, NV_PFIFO_CACHE1_PULL0_ACCESS);
    bool dma_push_access = GET_MASK(dma_push, NV_PFIFO_CACHE1_DMA_PUSH_ACCESS);
    bool dma_push_status = GET_MASK(dma_push, NV_PFIFO_CACHE1_DMA_PUSH_STATUS);
    bool low_mark = status & NV_PFIFO_CACHE1_STATUS_LOW_MARK;
    bool fifo_access = can_fifo_access(d);
    bool waiting_flip = qatomic_read(&d->pgraph.waiting_for_flip);
    bool waiting_nop = qatomic_read(&d->pgraph.waiting_for_nop);
    bool waiting_context =
        qatomic_read(&d->pgraph.waiting_for_context_switch);
    XemuXbeBootTraceNv2aWaitState wait_state = {
        .source = "pfifo-window",
        .op = op,
        .seq = count,
        .method = method,
        .parameter = parameter,
        .dma_get = dma_get,
        .dma_put = dma_put,
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
        .pfifo_known = true,
        .fifo_access = fifo_access,
        .pfifo_halt = d->pfifo.halt,
        .pfifo_kick = d->pfifo.fifo_kick,
        .pgraph_waiting_flip = waiting_flip,
        .pgraph_waiting_nop = waiting_nop,
        .pgraph_waiting_context = waiting_context,
    };
    xemu_xbe_boot_trace_observe_nv2a_wait_state(&wait_state);
    xemu_xbe_boot_trace_observe_pfifo_stream_idle_boundary(&wait_state);

    fprintf(stderr,
            "BOOT_MARK b6 pfifo=window context=%s"
            " seq=%" PRIu64
            " op=%s"
            " channel=%u"
            " window_start=0x%08x"
            " method_entry=0x%08x"
            " method=0x%04x"
            " subchannel=%u"
            " parameter=0x%08x"
            " available=%zu"
            " processed=%" PRId64
            " dma_get=0x%08x"
            " dma_put=0x%08x"
            " dma_state_method=0x%04x"
            " dma_state_count=%u"
            " dma_state_type=%u"
            " dma_state_subchannel=%u"
            " push_access=%s"
            " pull_access=%s"
            " dma_push_access=%s"
            " dma_push_status=%s"
            " low_mark=%s"
            " fifo_access=%s"
            " waiting_flip=%s"
            " waiting_nop=%s"
            " waiting_context=%s"
            " halt=%s"
            " fifo_kick=%s"
            " pmc_pending=0x%08x"
            " pmc_enabled=0x%08x"
            " pgraph_pending=0x%08x"
            " pgraph_enabled=0x%08x\n",
            pfifo_boot_trace_context(), count, op, channel_id,
            pfifo_boot_trace_window_start(), method_entry, method, subchannel,
            parameter, available, processed, dma_get, dma_put,
            GET_MASK(dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD) << 2,
            GET_MASK(dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD_COUNT),
            GET_MASK(dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD_TYPE),
            GET_MASK(dma_state, NV_PFIFO_CACHE1_DMA_STATE_SUBCHANNEL),
            push_access ? "yes" : "no",
            pull_access ? "yes" : "no",
            dma_push_access ? "yes" : "no",
            dma_push_status ? "yes" : "no",
            low_mark ? "yes" : "no",
            fifo_access ? "yes" : "no",
            waiting_flip ? "yes" : "no",
            waiting_nop ? "yes" : "no",
            waiting_context ? "yes" : "no",
            d->pfifo.halt ? "yes" : "no",
            d->pfifo.fifo_kick ? "yes" : "no",
            d->pmc.pending_interrupts, d->pmc.enabled_interrupts,
            d->pgraph.pending_interrupts, d->pgraph.enabled_interrupts);
}

static void pfifo_boot_trace_activity_state(NV2AState *d, const char *phase,
                                            uint32_t method_entry,
                                            uint32_t parameter,
                                            size_t available,
                                            int64_t processed,
                                            bool active,
                                            bool dma_get_local_known,
                                            uint32_t dma_get_local,
                                            bool commit_range_known,
                                            uint32_t dma_get_before,
                                            uint32_t dma_get_after,
                                            bool pfifo_lock_released,
                                            bool pgraph_locked)
{
    static uint64_t seq;
    uint32_t dma_state;
    uint32_t method;

    if (!pfifo_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_dashboard_observed()) {
        return;
    }

    seq++;
    dma_state = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_STATE];
    method = method_entry & 0x1FFC;
    XemuXbeBootTracePfifoActivityState state = {
        .source = "pfifo",
        .phase = phase,
        .seq = seq,
        .method_entry = method_entry,
        .method = method,
        .parameter = parameter,
        .dma_get_reg = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_GET],
        .dma_get_local = dma_get_local,
        .dma_get_before = dma_get_before,
        .dma_get_after = dma_get_after,
        .dma_put = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUT],
        .dma_state_method =
            GET_MASK(dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD) << 2,
        .dma_state_count =
            GET_MASK(dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD_COUNT),
        .available = available,
        .processed = processed,
        .active = active,
        .dma_get_local_known = dma_get_local_known,
        .commit_range_known = commit_range_known,
        .pfifo_lock_released = pfifo_lock_released,
        .pgraph_locked = pgraph_locked,
        .final_transition_candidate =
            commit_range_known && dma_get_before != dma_get_after &&
            dma_get_after == d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUT],
        .fifo_access = can_fifo_access(d),
        .pgraph_waiting_flip = qatomic_read(&d->pgraph.waiting_for_flip),
        .pgraph_waiting_nop = qatomic_read(&d->pgraph.waiting_for_nop),
        .pgraph_waiting_context =
            qatomic_read(&d->pgraph.waiting_for_context_switch),
    };

    xemu_xbe_boot_trace_observe_pfifo_activity(&state);
}

static void pfifo_boot_trace_pre_commit_timer_pump(NV2AState *d,
                                                   const char *phase,
                                                   uint32_t method_entry,
                                                   uint32_t parameter,
                                                   size_t available,
                                                   int64_t processed,
                                                   uint32_t dma_get_before,
                                                   uint32_t dma_get_after)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    static bool pumped;
    static uint64_t observed_pumps;
    uint32_t dma_put = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUT];
    uint32_t dma_state;
    uint32_t method;
    XemuXbeBootTracePfifoActivityState state;
    int64_t interval_tbs;
    int64_t virtual_now_before;
    int64_t virtual_deadline_before;
    int64_t virtual_now_after;
    int64_t virtual_deadline_after;
    bool virtual_has_timers_before;
    bool virtual_expired_before;
    bool virtual_has_timers_after;
    bool virtual_expired_after;
    bool progress;

    if (pumped ||
        !pfifo_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_dashboard_observed() ||
        dma_get_before == dma_get_after ||
        dma_get_after != dma_put) {
        return;
    }

    dma_state = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_STATE];
    method = method_entry & 0x1FFC;
    state = (XemuXbeBootTracePfifoActivityState) {
        .source = "pfifo",
        .phase = phase,
        .seq = observed_pumps + 1,
        .method_entry = method_entry,
        .method = method,
        .parameter = parameter,
        .dma_get_reg = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_GET],
        .dma_get_local = dma_get_after,
        .dma_get_before = dma_get_before,
        .dma_get_after = dma_get_after,
        .dma_put = dma_put,
        .dma_state_method =
            GET_MASK(dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD) << 2,
        .dma_state_count =
            GET_MASK(dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD_COUNT),
        .available = available,
        .processed = processed,
        .active = true,
        .dma_get_local_known = true,
        .commit_range_known = true,
        .pfifo_lock_released = false,
        .pgraph_locked = false,
        .final_transition_candidate = true,
        .fifo_access = can_fifo_access(d),
        .pgraph_waiting_flip = qatomic_read(&d->pgraph.waiting_for_flip),
        .pgraph_waiting_nop = qatomic_read(&d->pgraph.waiting_for_nop),
        .pgraph_waiting_context =
            qatomic_read(&d->pgraph.waiting_for_context_switch),
    };
    if (!xemu_xbe_boot_trace_pfifo_pre_commit_timer_pump_ready(&state)) {
        return;
    }

    pumped = true;
    observed_pumps++;
    interval_tbs = xemu_xbe_boot_trace_tcg_timer_pump_interval();
    virtual_now_before = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL);
    virtual_deadline_before =
        qemu_clock_deadline_ns_all(QEMU_CLOCK_VIRTUAL, QEMU_TIMER_ATTR_ALL);
    virtual_has_timers_before = qemu_clock_has_timers(QEMU_CLOCK_VIRTUAL);
    virtual_expired_before = qemu_clock_expired(QEMU_CLOCK_VIRTUAL);

    /*
     * Diagnostic-only wasm path: drop the PFIFO mutex before taking BQL so the
     * PIT callback satisfies cpu_interrupt()'s lock contract without inverting
     * the normal CPU/MMIO BQL -> PFIFO ordering. The pump is one-shot and
     * restricted to the PIT-attributed timer.
     */
    qemu_mutex_unlock(&d->pfifo.lock);
    bql_lock();
    xemu_xbe_boot_trace_enter_tcg_timer_pump(
        observed_pumps, interval_tbs, virtual_now_before,
        virtual_deadline_before, virtual_has_timers_before,
        virtual_expired_before);
    progress = qemu_clock_run_timers_with_attrs_limit(
        QEMU_CLOCK_VIRTUAL,
        QEMU_TIMER_ATTR_XEMU_TCG_PUMP,
        QEMU_TIMER_ATTR_XEMU_TCG_PUMP,
        1);
    xemu_xbe_boot_trace_leave_tcg_timer_pump();
    virtual_now_after = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL);
    virtual_deadline_after =
        qemu_clock_deadline_ns_all(QEMU_CLOCK_VIRTUAL, QEMU_TIMER_ATTR_ALL);
    virtual_has_timers_after = qemu_clock_has_timers(QEMU_CLOCK_VIRTUAL);
    virtual_expired_after = qemu_clock_expired(QEMU_CLOCK_VIRTUAL);
    bql_unlock();
    qemu_mutex_lock(&d->pfifo.lock);

    xemu_xbe_boot_trace_observe_pfifo_pre_commit_timer_pump(
        &state, observed_pumps, interval_tbs, virtual_now_before,
        virtual_deadline_before, virtual_has_timers_before,
        virtual_expired_before, progress, virtual_now_after,
        virtual_deadline_after, virtual_has_timers_after,
        virtual_expired_after);
#else
    (void)d;
    (void)phase;
    (void)method_entry;
    (void)parameter;
    (void)available;
    (void)processed;
    (void)dma_get_before;
    (void)dma_get_after;
#endif
}

static void pfifo_boot_trace_ready_edge_timer_pump(NV2AState *d)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    static bool pumped;
    int64_t virtual_now_before;
    int64_t virtual_deadline_before;
    int64_t virtual_now_after;
    int64_t virtual_deadline_after;
    bool virtual_has_timers_before;
    bool virtual_expired_before;
    bool virtual_has_timers_after;
    bool virtual_expired_after;
    const char *source = "browser-ready-edge-qemu-pump";
    bool progress;

    if (pumped ||
        !pfifo_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_main_loop_timer_pump_ready_edge_enabled()) {
        return;
    }

    pumped = true;

    /*
     * Diagnostic-only browser path: run the same main-loop timer primitive as
     * the headless host pump, but place it at the PFIFO stream-idle edge. Drop
     * the PFIFO mutex before taking BQL to avoid inverting the usual lock order.
     */
    qemu_mutex_unlock(&d->pfifo.lock);
    bql_lock();
    virtual_now_before = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL);
    virtual_deadline_before =
        qemu_clock_deadline_ns_all(QEMU_CLOCK_VIRTUAL, QEMU_TIMER_ATTR_ALL);
    virtual_has_timers_before = qemu_clock_has_timers(QEMU_CLOCK_VIRTUAL);
    virtual_expired_before = qemu_clock_expired(QEMU_CLOCK_VIRTUAL);
    if (xemu_xbe_boot_trace_main_loop_timer_pump_ready_edge_all_timers()) {
        source = "browser-ready-edge-qemu-pump-all";
        progress = qemu_clock_run_all_timers();
    } else {
        progress = qemu_clock_run_timers_with_attrs_limit(
            QEMU_CLOCK_VIRTUAL, 0, 0, 1);
    }
    virtual_now_after = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL);
    virtual_deadline_after =
        qemu_clock_deadline_ns_all(QEMU_CLOCK_VIRTUAL, QEMU_TIMER_ATTR_ALL);
    virtual_has_timers_after = qemu_clock_has_timers(QEMU_CLOCK_VIRTUAL);
    virtual_expired_after = qemu_clock_expired(QEMU_CLOCK_VIRTUAL);
    xemu_xbe_boot_trace_observe_main_loop_timers(
        source, 0, 0, virtual_now_before, virtual_deadline_before,
        virtual_has_timers_before, virtual_expired_before, progress,
        virtual_now_after, virtual_deadline_after, virtual_has_timers_after,
        virtual_expired_after);
    bql_unlock();
    qemu_mutex_lock(&d->pfifo.lock);
#else
    (void)d;
#endif
}

static void pfifo_boot_trace_stream_idle_transition(NV2AState *d,
                                                    uint32_t method_entry,
                                                    uint32_t parameter,
                                                    size_t available,
                                                    int64_t processed,
                                                    uint32_t dma_get_before,
                                                    uint32_t dma_get_after)
{
    static uint64_t count;
    int64_t limit;
    uint32_t dma_put = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUT];

    if (!pfifo_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_dashboard_observed() ||
        dma_get_before == dma_get_after ||
        dma_get_after != dma_put) {
        return;
    }

    limit = pfifo_boot_trace_window_limit();
    if (limit == 0 || count >= (uint64_t)limit ||
        dma_get_after < pfifo_boot_trace_window_start()) {
        return;
    }
    count++;

    uint32_t dma_state = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_STATE];
    uint32_t method = method_entry & 0x1FFC;
    bool fifo_access = can_fifo_access(d);
    bool waiting_flip = qatomic_read(&d->pgraph.waiting_for_flip);
    bool waiting_nop = qatomic_read(&d->pgraph.waiting_for_nop);
    bool waiting_context =
        qatomic_read(&d->pgraph.waiting_for_context_switch);
    XemuXbeBootTraceNv2aWaitState wait_state = {
        .source = "pfifo-transition",
        .op = "pusher-empty-transition",
        .seq = count,
        .method = method,
        .parameter = parameter,
        .dma_get = dma_get_after,
        .dma_put = dma_put,
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
        .pfifo_known = true,
        .fifo_access = fifo_access,
        .pfifo_halt = d->pfifo.halt,
        .pfifo_kick = d->pfifo.fifo_kick,
        .pgraph_waiting_flip = waiting_flip,
        .pgraph_waiting_nop = waiting_nop,
        .pgraph_waiting_context = waiting_context,
    };

    xemu_xbe_boot_trace_observe_pfifo_stream_idle_transition(
        &wait_state, dma_get_before, dma_get_after, dma_put, available,
        processed);
}

static void pfifo_boot_trace_state(NV2AState *d, const char *op,
                                   uint32_t method_entry,
                                   uint32_t parameter,
                                   size_t available,
                                   int64_t processed)
{
    static uint64_t count;
    int64_t limit;

    if (!pfifo_boot_trace_enabled() || !xemu_xbe_boot_trace_loaded()) {
        return;
    }

    pfifo_boot_trace_window_state(d, op, method_entry, parameter, available,
                                  processed);

    limit = pfifo_boot_trace_limit();
    if (limit == 0 || count >= (uint64_t)limit) {
        return;
    }
    count++;

    uint32_t push0 = d->pfifo.regs[NV_PFIFO_CACHE1_PUSH0];
    uint32_t push1 = d->pfifo.regs[NV_PFIFO_CACHE1_PUSH1];
    uint32_t pull0 = d->pfifo.regs[NV_PFIFO_CACHE1_PULL0];
    uint32_t status = d->pfifo.regs[NV_PFIFO_CACHE1_STATUS];
    uint32_t dma_push = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUSH];
    uint32_t dma_get = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_GET];
    uint32_t dma_put = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUT];
    uint32_t dma_state = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_STATE];
    uint32_t method = method_entry & 0x1FFC;
    uint32_t subchannel =
        GET_MASK(method_entry, NV_PFIFO_CACHE1_METHOD_SUBCHANNEL);
    unsigned int channel_id = GET_MASK(push1, NV_PFIFO_CACHE1_PUSH1_CHID);
    bool push_access = GET_MASK(push0, NV_PFIFO_CACHE1_PUSH0_ACCESS);
    bool pull_access = GET_MASK(pull0, NV_PFIFO_CACHE1_PULL0_ACCESS);
    bool dma_push_access = GET_MASK(dma_push, NV_PFIFO_CACHE1_DMA_PUSH_ACCESS);
    bool dma_push_status = GET_MASK(dma_push, NV_PFIFO_CACHE1_DMA_PUSH_STATUS);
    bool low_mark = status & NV_PFIFO_CACHE1_STATUS_LOW_MARK;
    bool fifo_access = can_fifo_access(d);
    bool waiting_flip = qatomic_read(&d->pgraph.waiting_for_flip);
    bool waiting_nop = qatomic_read(&d->pgraph.waiting_for_nop);
    bool waiting_context =
        qatomic_read(&d->pgraph.waiting_for_context_switch);
    XemuXbeBootTraceNv2aWaitState wait_state = {
        .source = "pfifo",
        .op = op,
        .seq = count,
        .method = method,
        .parameter = parameter,
        .dma_get = dma_get,
        .dma_put = dma_put,
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
        .pfifo_known = true,
        .fifo_access = fifo_access,
        .pfifo_halt = d->pfifo.halt,
        .pfifo_kick = d->pfifo.fifo_kick,
        .pgraph_waiting_flip = waiting_flip,
        .pgraph_waiting_nop = waiting_nop,
        .pgraph_waiting_context = waiting_context,
    };
    xemu_xbe_boot_trace_observe_nv2a_wait_state(&wait_state);

    fprintf(stderr,
            "BOOT_MARK b6 pfifo=progress context=%s"
            " seq=%" PRIu64
            " op=%s"
            " channel=%u"
            " method_entry=0x%08x"
            " method=0x%04x"
            " subchannel=%u"
            " parameter=0x%08x"
            " available=%zu"
            " processed=%" PRId64
            " dma_get=0x%08x"
            " dma_put=0x%08x"
            " dma_state_method=0x%04x"
            " dma_state_count=%u"
            " dma_state_type=%u"
            " dma_state_subchannel=%u"
            " push_access=%s"
            " pull_access=%s"
            " dma_push_access=%s"
            " dma_push_status=%s"
            " low_mark=%s"
            " fifo_access=%s"
            " waiting_flip=%s"
            " waiting_nop=%s"
            " waiting_context=%s"
            " halt=%s"
            " fifo_kick=%s"
            " pmc_pending=0x%08x"
            " pmc_enabled=0x%08x"
            " pgraph_pending=0x%08x"
            " pgraph_enabled=0x%08x\n",
            pfifo_boot_trace_context(), count, op, channel_id, method_entry,
            method, subchannel, parameter, available, processed, dma_get,
            dma_put,
            GET_MASK(dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD) << 2,
            GET_MASK(dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD_COUNT),
            GET_MASK(dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD_TYPE),
            GET_MASK(dma_state, NV_PFIFO_CACHE1_DMA_STATE_SUBCHANNEL),
            push_access ? "yes" : "no",
            pull_access ? "yes" : "no",
            dma_push_access ? "yes" : "no",
            dma_push_status ? "yes" : "no",
            low_mark ? "yes" : "no",
            fifo_access ? "yes" : "no",
            waiting_flip ? "yes" : "no",
            waiting_nop ? "yes" : "no",
            waiting_context ? "yes" : "no",
            d->pfifo.halt ? "yes" : "no",
            d->pfifo.fifo_kick ? "yes" : "no",
            d->pmc.pending_interrupts, d->pmc.enabled_interrupts,
            d->pgraph.pending_interrupts, d->pgraph.enabled_interrupts);
}

typedef struct RAMHTEntry {
    uint32_t handle;
    hwaddr instance;
    enum FIFOEngine engine;
    unsigned int channel_id : 5;
    bool valid;
} RAMHTEntry;

static void pfifo_run_pusher(NV2AState *d);
static uint32_t ramht_hash(NV2AState *d, uint32_t handle);
static RAMHTEntry ramht_lookup(NV2AState *d, uint32_t handle);

/* PFIFO - MMIO and DMA FIFO submission to PGRAPH and VPE */
uint64_t pfifo_read(void *opaque, hwaddr addr, unsigned int size)
{
    NV2AState *d = (NV2AState *)opaque;

    qemu_mutex_lock(&d->pfifo.lock);

    uint64_t r = 0;
    switch (addr) {
    case NV_PFIFO_INTR_0:
        r = d->pfifo.pending_interrupts;
        break;
    case NV_PFIFO_INTR_EN_0:
        r = d->pfifo.enabled_interrupts;
        break;
    case NV_PFIFO_RUNOUT_STATUS:
        r = NV_PFIFO_RUNOUT_STATUS_LOW_MARK; /* low mark empty */
        break;
    default:
        r = d->pfifo.regs[addr];
        break;
    }

    qemu_mutex_unlock(&d->pfifo.lock);

    nv2a_reg_log_read(NV_PFIFO, addr, size, r);
    return r;
}

void pfifo_write(void *opaque, hwaddr addr, uint64_t val, unsigned int size)
{
    NV2AState *d = (NV2AState *)opaque;

    nv2a_reg_log_write(NV_PFIFO, addr, size, val);

    qemu_mutex_lock(&d->pfifo.lock);

    switch (addr) {
    case NV_PFIFO_INTR_0:
        d->pfifo.pending_interrupts &= ~val;
        nv2a_update_irq(d);
        break;
    case NV_PFIFO_INTR_EN_0:
        d->pfifo.enabled_interrupts = val;
        nv2a_update_irq(d);
        break;
    default:
        d->pfifo.regs[addr] = val;
        break;
    }

    pfifo_kick(d);

    qemu_mutex_unlock(&d->pfifo.lock);
}

void pfifo_kick(NV2AState *d)
{
    d->pfifo.fifo_kick = true;
    qemu_cond_broadcast(&d->pfifo.fifo_cond);
}

static bool can_fifo_access(NV2AState *d) {
    return qatomic_read(&d->pgraph.regs_[NV_PGRAPH_FIFO]) &
           NV_PGRAPH_FIFO_ACCESS;
}

/* If NV097_FLIP_STALL was executed, check if the flip has completed.
 * This will usually happen in the VSYNC interrupt handler.
 */
static bool is_flip_stall_complete(NV2AState *d)
{
    PGRAPHState *pg = &d->pgraph;

    uint32_t s = pgraph_reg_r(pg, NV_PGRAPH_SURFACE);

    NV2A_DPRINTF("flip stall read: %d, write: %d, modulo: %d\n",
        GET_MASK(s, NV_PGRAPH_SURFACE_READ_3D),
        GET_MASK(s, NV_PGRAPH_SURFACE_WRITE_3D),
        GET_MASK(s, NV_PGRAPH_SURFACE_MODULO_3D));

    if (GET_MASK(s, NV_PGRAPH_SURFACE_READ_3D)
        != GET_MASK(s, NV_PGRAPH_SURFACE_WRITE_3D)) {
        return true;
    }

    return false;
}

static bool pfifo_stall_for_flip(NV2AState *d)
{
    bool should_stall = false;

    if (qatomic_read(&d->pgraph.waiting_for_flip)) {
        qemu_mutex_lock(&d->pgraph.lock);
        if (!is_flip_stall_complete(d)) {
            should_stall = true;
        } else {
            d->pgraph.waiting_for_flip = false;
        }
        qemu_mutex_unlock(&d->pgraph.lock);
    }

    return should_stall;
}

static bool pfifo_puller_should_stall(NV2AState *d)
{
    return pfifo_stall_for_flip(d) || qatomic_read(&d->pgraph.waiting_for_nop) ||
           qatomic_read(&d->pgraph.waiting_for_context_switch) ||
           !can_fifo_access(d);
}

static ssize_t pfifo_run_puller(NV2AState *d, uint32_t method_entry,
                                uint32_t parameter, uint32_t *parameters,
                                size_t num_words_available,
                                size_t max_lookahead_words)
{
    if (pfifo_puller_should_stall(d)) {
        pfifo_boot_trace_state(d, "puller-stall", method_entry, parameter,
                               num_words_available, -1);
        return -1;
    }

    uint32_t *pull0 = &d->pfifo.regs[NV_PFIFO_CACHE1_PULL0];
    uint32_t *pull1 = &d->pfifo.regs[NV_PFIFO_CACHE1_PULL1];
    uint32_t *engine_reg = &d->pfifo.regs[NV_PFIFO_CACHE1_ENGINE];
    uint32_t *status = &d->pfifo.regs[NV_PFIFO_CACHE1_STATUS];
    ssize_t num_proc = -1;

    // TODO think more about locking

    if (!GET_MASK(*pull0, NV_PFIFO_CACHE1_PULL0_ACCESS) ||
        (*status & NV_PFIFO_CACHE1_STATUS_LOW_MARK)) {
        pfifo_boot_trace_state(d, "puller-skip", method_entry, parameter,
                               num_words_available, -1);
        return -1;
    }

    uint32_t method = method_entry & 0x1FFC;
    uint32_t subchannel =
        GET_MASK(method_entry, NV_PFIFO_CACHE1_METHOD_SUBCHANNEL);
    bool inc = !GET_MASK(method_entry, NV_PFIFO_CACHE1_METHOD_TYPE);

    if (method == 0) {
        RAMHTEntry entry = ramht_lookup(d, parameter);
        assert(entry.valid);
        // assert(entry.channel_id == state->channel_id);
        assert(entry.engine == ENGINE_GRAPHICS);
        pfifo_boot_trace_state(d, "puller-bind", method_entry, parameter,
                               num_words_available, -1);

        /* the engine is bound to the subchannel */
        assert(subchannel < 8);
        SET_MASK(*engine_reg, 3 << (4*subchannel), entry.engine);
        SET_MASK(*pull1, NV_PFIFO_CACHE1_PULL1_ENGINE, entry.engine);

        // TODO: this is fucked
        pfifo_boot_trace_activity_state(d, "puller-bind-before-pgraph-call",
                                        method_entry, parameter,
                                        num_words_available, -1, true, false,
                                        0, false, 0, 0, false, false);
        qemu_mutex_unlock(&d->pfifo.lock);
        qemu_mutex_lock(&d->pgraph.lock);

        // Switch contexts if necessary
        if (can_fifo_access(d)) {
            pfifo_boot_trace_activity_state(d, "puller-bind-pgraph-call",
                                            method_entry, parameter,
                                            num_words_available, -1, true,
                                            false, 0, false, 0, 0, true,
                                            true);
            pgraph_context_switch(d, entry.channel_id);
            if (!d->pgraph.waiting_for_context_switch) {
                num_proc =
                    pgraph_method(d, subchannel, 0, entry.instance, parameters,
                                  num_words_available, max_lookahead_words, inc);
                pfifo_boot_trace_activity_state(d, "puller-bind-pgraph-return",
                                                method_entry, parameter,
                                                num_words_available, num_proc,
                                                true, false, 0, false, 0, 0,
                                                true, true);
                pfifo_boot_trace_state(d, "puller-bind-done", method_entry,
                                       parameter, num_words_available,
                                       num_proc);
            } else {
                pfifo_boot_trace_state(d, "puller-context-wait",
                                       method_entry, parameter,
                                       num_words_available, -1);
            }
        } else {
            pfifo_boot_trace_state(d, "puller-no-access", method_entry,
                                   parameter, num_words_available, -1);
        }

        qemu_mutex_unlock(&d->pgraph.lock);
        qemu_mutex_lock(&d->pfifo.lock);

    } else if (method >= 0x100) {
        // method passed to engine

        /* methods that take objects.
         * TODO: Check this range is correct for the nv2a */
        if (method >= 0x180 && method < 0x200) {
            //bql_lock();
            RAMHTEntry entry = ramht_lookup(d, parameter);
            assert(entry.valid);
            // assert(entry.channel_id == state->channel_id);
            parameter = entry.instance;
            //bql_unlock();
        }

        enum FIFOEngine engine = GET_MASK(*engine_reg, 3 << (4*subchannel));
        assert(engine == ENGINE_GRAPHICS);
        SET_MASK(*pull1, NV_PFIFO_CACHE1_PULL1_ENGINE, engine);
        pfifo_boot_trace_state(d, "puller-method", method_entry, parameter,
                               num_words_available, -1);

        // TODO: this is fucked
        pfifo_boot_trace_activity_state(d, "puller-method-before-pgraph-call",
                                        method_entry, parameter,
                                        num_words_available, -1, true, false,
                                        0, false, 0, 0, false, false);
        qemu_mutex_unlock(&d->pfifo.lock);
        qemu_mutex_lock(&d->pgraph.lock);

        if (can_fifo_access(d)) {
            pfifo_boot_trace_activity_state(d, "puller-method-pgraph-call",
                                            method_entry, parameter,
                                            num_words_available, -1, true,
                                            false, 0, false, 0, 0, true,
                                            true);
            num_proc =
                pgraph_method(d, subchannel, method, parameter, parameters,
                              num_words_available, max_lookahead_words, inc);
            pfifo_boot_trace_activity_state(d, "puller-method-pgraph-return",
                                            method_entry, parameter,
                                            num_words_available, num_proc,
                                            true, false, 0, false, 0, 0,
                                            true, true);
            pfifo_boot_trace_state(d, "puller-method-done", method_entry,
                                   parameter, num_words_available, num_proc);
        } else {
            pfifo_boot_trace_state(d, "puller-no-access", method_entry,
                                   parameter, num_words_available, -1);
        }

        qemu_mutex_unlock(&d->pgraph.lock);
        qemu_mutex_lock(&d->pfifo.lock);
    } else {
        assert(!"Unrecognized pfifo puller method");
    }

    if (num_proc > 0) {
        *status |= NV_PFIFO_CACHE1_STATUS_LOW_MARK;
    }

    return num_proc;
}

static bool pfifo_pusher_should_stall(NV2AState *d)
{
    return !can_fifo_access(d) ||
           qatomic_read(&d->pgraph.waiting_for_nop);
}

static void pfifo_run_pusher(NV2AState *d)
{
    uint32_t *push0 = &d->pfifo.regs[NV_PFIFO_CACHE1_PUSH0];
    uint32_t *push1 = &d->pfifo.regs[NV_PFIFO_CACHE1_PUSH1];
    uint32_t *dma_subroutine = &d->pfifo.regs[NV_PFIFO_CACHE1_DMA_SUBROUTINE];
    uint32_t *dma_state = &d->pfifo.regs[NV_PFIFO_CACHE1_DMA_STATE];
    uint32_t *dma_push = &d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUSH];
    uint32_t *dma_get = &d->pfifo.regs[NV_PFIFO_CACHE1_DMA_GET];
    uint32_t *dma_put = &d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUT];
    uint32_t *dma_dcount = &d->pfifo.regs[NV_PFIFO_CACHE1_DMA_DCOUNT];
    uint32_t *status = &d->pfifo.regs[NV_PFIFO_CACHE1_STATUS];

    if (!GET_MASK(*push0, NV_PFIFO_CACHE1_PUSH0_ACCESS) ||
        !GET_MASK(*dma_push, NV_PFIFO_CACHE1_DMA_PUSH_ACCESS) ||
        GET_MASK(*dma_push, NV_PFIFO_CACHE1_DMA_PUSH_STATUS)) {
        pfifo_boot_trace_state(d, "pusher-skip", 0, 0, 0, -1);
        return;
    }

    // TODO: should we become busy here??
    // NV_PFIFO_CACHE1_DMA_PUSH_STATE _BUSY

    unsigned int channel_id = GET_MASK(*push1,
                                       NV_PFIFO_CACHE1_PUSH1_CHID);


    /* Channel running DMA mode */
    uint32_t channel_modes = d->pfifo.regs[NV_PFIFO_MODE];
    assert(channel_modes & (1 << channel_id));

    assert(GET_MASK(*push1, NV_PFIFO_CACHE1_PUSH1_MODE)
            == NV_PFIFO_CACHE1_PUSH1_MODE_DMA);

    /* We're running so there should be no pending errors... */
    assert(GET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_ERROR)
            == NV_PFIFO_CACHE1_DMA_STATE_ERROR_NONE);

    hwaddr dma_instance =
        GET_MASK(d->pfifo.regs[NV_PFIFO_CACHE1_DMA_INSTANCE],
                 NV_PFIFO_CACHE1_DMA_INSTANCE_ADDRESS) << 4;

    hwaddr dma_len;
    uint8_t *dma = nv_dma_map(d, dma_instance, &dma_len);
    pfifo_boot_trace_state(d, "pusher-enter", 0, 0, 0, -1);

    while (true) {
        if (pfifo_pusher_should_stall(d)) {
            pfifo_boot_trace_state(d, "pusher-stall", 0, 0, 0, -1);
            break;
        }

        uint32_t dma_get_v = *dma_get;
        uint32_t dma_put_v = *dma_put;
        uint32_t dma_get_before = dma_get_v;
        if (dma_get_v == dma_put_v) {
            pfifo_boot_trace_activity_state(d, "pusher-empty", 0, 0, 0, -1,
                                            false, true, dma_get_v, false,
                                            0, 0, false, false);
            pfifo_boot_trace_state(d, "pusher-empty", 0, 0, 0, -1);
            break;
        }
        if (dma_get_v >= dma_len) {
            assert(!"Dma value is out of range in PFIFO pusher");
            SET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_ERROR,
                     NV_PFIFO_CACHE1_DMA_STATE_ERROR_PROTECTION);
            break;
        }

        size_t num_words_available = dma_put_v - dma_get_v;
        assert(num_words_available % 4 == 0);
        num_words_available /= 4;

        uint32_t *word_ptr = (uint32_t*)(dma + dma_get_v);
        uint32_t word = ldl_le_p(word_ptr);
        dma_get_v += 4;

        uint32_t method_type =
            GET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD_TYPE);
        uint32_t method_subchannel =
            GET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_SUBCHANNEL);
        uint32_t method =
            GET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD) << 2;
        uint32_t method_count =
            GET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD_COUNT);

        uint32_t subroutine_state =
            GET_MASK(*dma_subroutine, NV_PFIFO_CACHE1_DMA_SUBROUTINE_STATE);
        uint32_t trace_method_entry = word;
        uint32_t trace_parameter = 0;
        size_t trace_available = num_words_available;
        int64_t trace_processed = -1;

        if (method_count) {
            /* data word of methods command */
            d->pfifo.regs[NV_PFIFO_CACHE1_DMA_DATA_SHADOW] = word;

            assert((method & 3) == 0);
            uint32_t method_entry = 0;
            SET_MASK(method_entry, NV_PFIFO_CACHE1_METHOD_ADDRESS, method >> 2);
            SET_MASK(method_entry, NV_PFIFO_CACHE1_METHOD_TYPE, method_type);
            SET_MASK(method_entry, NV_PFIFO_CACHE1_METHOD_SUBCHANNEL,
                     method_subchannel);

            *status &= ~NV_PFIFO_CACHE1_STATUS_LOW_MARK;

            ssize_t num_words_processed =
                pfifo_run_puller(d, method_entry, word, word_ptr,
                                 MIN(method_count, num_words_available),
                                 num_words_available);
            if (num_words_processed < 0) {
                pfifo_boot_trace_state(d, "pusher-puller-stall",
                                       method_entry, word,
                                       num_words_available,
                                       num_words_processed);
                break;
            }
            pfifo_boot_trace_state(d, "pusher-puller-done", method_entry,
                                   word, num_words_available,
                                   num_words_processed);
            trace_method_entry = method_entry;
            trace_parameter = word;
            trace_processed = num_words_processed;

            dma_get_v += (num_words_processed-1)*4;

            if (method_type == NV_PFIFO_CACHE1_DMA_STATE_METHOD_TYPE_INC) {
                SET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD,
                         (method + 4*num_words_processed) >> 2);
            }
            SET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD_COUNT,
                     method_count - MIN(method_count, num_words_processed));

            (*dma_dcount) += num_words_processed;
        } else {
            /* no command active - this is the first word of a new one */
            d->pfifo.regs[NV_PFIFO_CACHE1_DMA_RSVD_SHADOW] = word;

            /* match all forms */
            if ((word & 0xe0000003) == 0x20000000) {
                /* old jump */
                d->pfifo.regs[NV_PFIFO_CACHE1_DMA_GET_JMP_SHADOW] =
                    dma_get_v;
                dma_get_v = word & 0x1fffffff;
                NV2A_DPRINTF("pb OLD_JMP 0x%x\n", dma_get_v);
            } else if ((word & 3) == 1) {
                /* jump */
                d->pfifo.regs[NV_PFIFO_CACHE1_DMA_GET_JMP_SHADOW] =
                    dma_get_v;
                dma_get_v = word & 0xfffffffc;
                NV2A_DPRINTF("pb JMP 0x%x\n", dma_get_v);
            } else if ((word & 3) == 2) {
                /* call */
                if (subroutine_state) {
                    SET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_ERROR,
                             NV_PFIFO_CACHE1_DMA_STATE_ERROR_CALL);
                    break;
                } else {
                    *dma_subroutine = dma_get_v;
                    SET_MASK(*dma_subroutine,
                             NV_PFIFO_CACHE1_DMA_SUBROUTINE_STATE, 1);
                    dma_get_v = word & 0xfffffffc;
                    NV2A_DPRINTF("pb CALL 0x%x\n", dma_get_v);
                }
            } else if (word == 0x00020000) {
                /* return */
                if (!subroutine_state) {
                    SET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_ERROR,
                             NV_PFIFO_CACHE1_DMA_STATE_ERROR_RETURN);
                    // break;
                } else {
                    dma_get_v = *dma_subroutine & 0xfffffffc;
                    SET_MASK(*dma_subroutine,
                             NV_PFIFO_CACHE1_DMA_SUBROUTINE_STATE, 0);
                    NV2A_DPRINTF("pb RET 0x%x\n", dma_get_v);
                }
            } else if ((word & 0xe0030003) == 0) {
                /* increasing methods */
                SET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD,
                         (word & 0x1fff) >> 2 );
                SET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_SUBCHANNEL,
                         (word >> 13) & 7);
                SET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD_COUNT,
                         (word >> 18) & 0x7ff);
                SET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD_TYPE,
                         NV_PFIFO_CACHE1_DMA_STATE_METHOD_TYPE_INC);
                *dma_dcount = 0;
                pfifo_boot_trace_state(d, "pusher-new-method-inc", word, 0,
                                       num_words_available, -1);
            } else if ((word & 0xe0030003) == 0x40000000) {
                /* non-increasing methods */
                SET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD,
                         (word & 0x1fff) >> 2 );
                SET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_SUBCHANNEL,
                         (word >> 13) & 7);
                SET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD_COUNT,
                         (word >> 18) & 0x7ff);
                SET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_METHOD_TYPE,
                         NV_PFIFO_CACHE1_DMA_STATE_METHOD_TYPE_NON_INC);
                *dma_dcount = 0;
                pfifo_boot_trace_state(d, "pusher-new-method-non-inc", word,
                                       0, num_words_available, -1);
            } else {
                NV2A_DPRINTF("pb reserved cmd 0x%x - 0x%x\n",
                             dma_get_v, word);
                SET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_ERROR,
                         NV_PFIFO_CACHE1_DMA_STATE_ERROR_RESERVED_CMD);
                // break;
                assert(!"Reserved pb command - invalid GPU command. Check logs for more info");
            }
        }

        pfifo_boot_trace_activity_state(d, "pusher-before-dma-get-commit",
                                        trace_method_entry, trace_parameter,
                                        trace_available, trace_processed,
                                        true, true, dma_get_v, true,
                                        dma_get_before, dma_get_v, false,
                                        false);
        pfifo_boot_trace_pre_commit_timer_pump(
            d, "pusher-before-dma-get-commit", trace_method_entry,
            trace_parameter, trace_available, trace_processed, dma_get_before,
            dma_get_v);
        *dma_get = dma_get_v;
        pfifo_boot_trace_activity_state(d, "pusher-after-dma-get-commit",
                                        trace_method_entry, trace_parameter,
                                        trace_available, trace_processed,
                                        true, true, dma_get_v, true,
                                        dma_get_before, dma_get_v, false,
                                        false);
        if (dma_get_before != dma_get_v && dma_get_v == *dma_put) {
            pfifo_boot_trace_stream_idle_transition(
                d, trace_method_entry, trace_parameter, trace_available,
                trace_processed, dma_get_before, dma_get_v);
            pfifo_boot_trace_ready_edge_timer_pump(d);
        }

        if (GET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_ERROR)) {
            break;
        }
    }

    // NV2A_DPRINTF("DMA pusher done: max 0x%" HWADDR_PRIx ", 0x%" HWADDR_PRIx " - 0x%" HWADDR_PRIx "\n",
    //      dma_len, control->dma_get, control->dma_put);

    uint32_t error = GET_MASK(*dma_state, NV_PFIFO_CACHE1_DMA_STATE_ERROR);
    if (error) {
        NV2A_DPRINTF("pb error: %d\n", error);
        assert(!"Error reported in PFIFO dma state - check logs for more info");

        SET_MASK(*dma_push, NV_PFIFO_CACHE1_DMA_PUSH_STATUS, 1); /* suspended */

        // d->pfifo.pending_interrupts |= NV_PFIFO_INTR_0_DMA_PUSHER;
        // nv2a_update_irq(d);
    }
}

void *pfifo_thread(void *arg)
{
    NV2AState *d = (NV2AState *)arg;

    pfifo_boot_trace_mark("b2 thread=nv2a-pfifo started");
    pgraph_init_thread(d);

    rcu_register_thread();

    qemu_mutex_lock(&d->pfifo.lock);
    while (true) {
        d->pfifo.fifo_kick = false;

        pgraph_process_pending(d);

        if (!d->pfifo.halt) {
            pfifo_run_pusher(d);
        }

        pgraph_process_pending_reports(d);

        if (!d->pfifo.fifo_kick) {
            qemu_cond_broadcast(&d->pfifo.fifo_idle_cond);

            // Both the pusher and puller are waiting for some action
            qemu_cond_wait(&d->pfifo.fifo_cond, &d->pfifo.lock);
        }

        if (d->exiting) {
            break;
        }
    }
    qemu_mutex_unlock(&d->pfifo.lock);

    rcu_unregister_thread();

    return NULL;
}

static uint32_t ramht_hash(NV2AState *d, uint32_t handle)
{
    unsigned int ramht_size =
        1 << (GET_MASK(d->pfifo.regs[NV_PFIFO_RAMHT], NV_PFIFO_RAMHT_SIZE)+12);

    /* XXX: Think this is different to what nouveau calculates... */
    unsigned int bits = ctz32(ramht_size)-1;

    uint32_t hash = 0;
    while (handle) {
        hash ^= (handle & ((1 << bits) - 1));
        handle >>= bits;
    }

    unsigned int channel_id = GET_MASK(d->pfifo.regs[NV_PFIFO_CACHE1_PUSH1],
                                       NV_PFIFO_CACHE1_PUSH1_CHID);
    hash ^= channel_id << (bits - 4);

    return hash;
}


static RAMHTEntry ramht_lookup(NV2AState *d, uint32_t handle)
{
    hwaddr ramht_size =
        1 << (GET_MASK(d->pfifo.regs[NV_PFIFO_RAMHT], NV_PFIFO_RAMHT_SIZE)+12);

    uint32_t hash = ramht_hash(d, handle);
    assert(hash * 8 < ramht_size);

    hwaddr ramht_address =
        GET_MASK(d->pfifo.regs[NV_PFIFO_RAMHT],
                 NV_PFIFO_RAMHT_BASE_ADDRESS) << 12;

    assert(ramht_address + hash * 8 < memory_region_size(&d->ramin));

    uint8_t *entry_ptr = d->ramin_ptr + ramht_address + hash * 8;

    uint32_t entry_handle = ldl_le_p((uint32_t*)entry_ptr);
    uint32_t entry_context = ldl_le_p((uint32_t*)(entry_ptr + 4));

    return (RAMHTEntry){
        .handle = entry_handle,
        .instance = (entry_context & NV_RAMHT_INSTANCE) << 4,
        .engine = (entry_context & NV_RAMHT_ENGINE) >> 16,
        .channel_id = (entry_context & NV_RAMHT_CHID) >> 24,
        .valid = entry_context & NV_RAMHT_STATUS,
    };
}
