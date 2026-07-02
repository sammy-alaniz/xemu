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

#define XEMU_NV2A_USER_DMA_PUT_TRACE_DEFAULT_LIMIT 0
#define XEMU_NV2A_USER_DMA_PUT_TRACE_CONTEXT_MAX 64

typedef struct UserDmaPutTraceSnapshot {
    bool emit;
    uint64_t seq;
    unsigned int channel_id;
    unsigned int cur_channel_id;
    hwaddr addr;
    uint64_t raw_value;
    unsigned int size;
    uint32_t dma_get;
    uint32_t old_dma_put;
    uint32_t new_dma_put;
    bool old_dma_to_put_known;
    bool new_dma_to_put_known;
    uint32_t old_dma_to_put;
    uint32_t new_dma_to_put;
} UserDmaPutTraceSnapshot;

static bool user_boot_trace_initialized;
static bool user_boot_trace_cached_enabled;
static int64_t user_boot_trace_dma_put_cached_limit =
    XEMU_NV2A_USER_DMA_PUT_TRACE_DEFAULT_LIMIT;
static uint64_t user_boot_trace_dma_put_count;
static char user_boot_trace_cached_context[
    XEMU_NV2A_USER_DMA_PUT_TRACE_CONTEXT_MAX];

static bool user_boot_trace_read_line(const char *path, char *buffer,
                                      size_t buffer_size)
{
    FILE *fp;

    if (!path || !buffer || buffer_size == 0) {
        return false;
    }

    fp = fopen(path, "r");
    if (!fp) {
        return false;
    }

    buffer[0] = 0;
    if (fgets(buffer, buffer_size, fp)) {
        buffer[strcspn(buffer, "\r\n")] = 0;
    }
    fclose(fp);

    return buffer[0] != 0;
}

static bool user_boot_trace_env_enabled(void)
{
#ifdef CONFIG_XEMU_BROWSER_BOOT
    return true;
#else
    const char *value = getenv("XEMU_BOOT_TRACE");

    return value && value[0] && strcmp(value, "0");
#endif
}

static const char *user_boot_trace_bool_str(bool value)
{
    return value ? "yes" : "no";
}

static void user_boot_trace_load_context(void)
{
    const char *env_context = getenv("XEMU_BOOT_TRACE_CONTEXT");
    const char *paths[] = {
        "/xemu-fixtures/boot_trace_context.txt",
        "/xemu-smoke/boot_trace_context.txt",
        "/xemu-smoke-out/boot_trace_context.txt",
        NULL,
    };

    if (env_context && env_context[0]) {
        g_strlcpy(user_boot_trace_cached_context, env_context,
                  sizeof(user_boot_trace_cached_context));
        return;
    }

    for (int i = 0; paths[i]; i++) {
        if (user_boot_trace_read_line(paths[i], user_boot_trace_cached_context,
                                      sizeof(user_boot_trace_cached_context))) {
            return;
        }
    }

#ifdef CONFIG_XEMU_BROWSER_BOOT
    g_strlcpy(user_boot_trace_cached_context, "browser-boot",
              sizeof(user_boot_trace_cached_context));
#else
    g_strlcpy(user_boot_trace_cached_context, "native-headless",
              sizeof(user_boot_trace_cached_context));
#endif
}

static int64_t user_boot_trace_parse_dma_put_limit(const char *value)
{
    char *end = NULL;
    int64_t limit;

    if (!value || !value[0]) {
        return XEMU_NV2A_USER_DMA_PUT_TRACE_DEFAULT_LIMIT;
    }

    limit = g_ascii_strtoll(value, &end, 10);
    if (end == value || limit < 0) {
        return XEMU_NV2A_USER_DMA_PUT_TRACE_DEFAULT_LIMIT;
    }

    return limit;
}

static int64_t user_boot_trace_load_dma_put_limit(void)
{
    const char *value = getenv("XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT");
    char fixture_value[64];
    const char *paths[] = {
        "/xemu-fixtures/nv2a_user_dma_put_limit.txt",
        "/xemu-smoke/nv2a_user_dma_put_limit.txt",
        "/xemu-smoke-out/nv2a_user_dma_put_limit.txt",
        NULL,
    };

    if (value && value[0]) {
        return user_boot_trace_parse_dma_put_limit(value);
    }

    for (int i = 0; paths[i]; i++) {
        if (user_boot_trace_read_line(paths[i], fixture_value,
                                      sizeof(fixture_value))) {
            return user_boot_trace_parse_dma_put_limit(fixture_value);
        }
    }

    return XEMU_NV2A_USER_DMA_PUT_TRACE_DEFAULT_LIMIT;
}

void user_boot_trace_init(void)
{
    if (user_boot_trace_initialized) {
        return;
    }

    user_boot_trace_initialized = true;
    user_boot_trace_cached_enabled = user_boot_trace_env_enabled();
    user_boot_trace_load_context();
    user_boot_trace_dma_put_cached_limit =
        user_boot_trace_load_dma_put_limit();
}

static void user_boot_trace_dma_put_snapshot(
    UserDmaPutTraceSnapshot *snapshot, NV2AState *d,
    unsigned int channel_id, unsigned int cur_channel_id, hwaddr addr,
    uint64_t raw_value, unsigned int size, uint32_t old_dma_put)
{
    int64_t limit;
    uint32_t dma_get;
    uint32_t new_dma_put;

    memset(snapshot, 0, sizeof(*snapshot));

    if (!user_boot_trace_initialized || !user_boot_trace_cached_enabled) {
        return;
    }

    limit = user_boot_trace_dma_put_cached_limit;
    if (limit == 0 || user_boot_trace_dma_put_count >= (uint64_t)limit) {
        return;
    }

    dma_get = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_GET];
    new_dma_put = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUT];

    snapshot->emit = true;
    snapshot->seq = ++user_boot_trace_dma_put_count;
    snapshot->channel_id = channel_id;
    snapshot->cur_channel_id = cur_channel_id;
    snapshot->addr = addr;
    snapshot->raw_value = raw_value;
    snapshot->size = size;
    snapshot->dma_get = dma_get;
    snapshot->old_dma_put = old_dma_put;
    snapshot->new_dma_put = new_dma_put;
    snapshot->old_dma_to_put_known = old_dma_put >= dma_get;
    snapshot->new_dma_to_put_known = new_dma_put >= dma_get;
    snapshot->old_dma_to_put = snapshot->old_dma_to_put_known ?
        old_dma_put - dma_get : 0;
    snapshot->new_dma_to_put = snapshot->new_dma_to_put_known ?
        new_dma_put - dma_get : 0;
}

static void user_boot_trace_dma_put_emit(
    const UserDmaPutTraceSnapshot *snapshot)
{
    if (!snapshot->emit) {
        return;
    }

    fprintf(stderr,
            "BOOT_MARK b6 nv2a=user-dma-put context=%s"
            " seq=%" PRIu64
            " source=nv-user-dma-put"
            " channel=%u"
            " cur_channel=%u"
            " addr=0x%08" PRIx64
            " offset=0x%04x"
            " size=%u"
            " raw_value=0x%08" PRIx64
            " dma_get=0x%08" PRIx32
            " old_dma_put=0x%08" PRIx32
            " new_dma_put=0x%08" PRIx32
            " old_dma_to_put_known=%s"
            " old_dma_to_put=%" PRIu32
            " new_dma_to_put_known=%s"
            " new_dma_to_put=%" PRIu32 "\n",
            user_boot_trace_cached_context, snapshot->seq,
            snapshot->channel_id, snapshot->cur_channel_id,
            (uint64_t)snapshot->addr,
            (unsigned)(snapshot->addr & 0xFFFF), snapshot->size,
            snapshot->raw_value, snapshot->dma_get, snapshot->old_dma_put,
            snapshot->new_dma_put,
            user_boot_trace_bool_str(snapshot->old_dma_to_put_known),
            snapshot->old_dma_to_put,
            user_boot_trace_bool_str(snapshot->new_dma_to_put_known),
            snapshot->new_dma_to_put);
}

/* USER - PFIFO MMIO and DMA submission area */
uint64_t user_read(void *opaque, hwaddr addr, unsigned int size)
{
    NV2AState *d = (NV2AState *)opaque;

    unsigned int channel_id = addr >> 16;
    assert(channel_id < NV2A_NUM_CHANNELS);

    qemu_mutex_lock(&d->pfifo.lock);

    uint32_t channel_modes = d->pfifo.regs[NV_PFIFO_MODE];

    uint64_t r = 0;
    if (channel_modes & (1 << channel_id)) {
        /* DMA Mode */

        unsigned int cur_channel_id =
            GET_MASK(d->pfifo.regs[NV_PFIFO_CACHE1_PUSH1],
                     NV_PFIFO_CACHE1_PUSH1_CHID);

        if (channel_id == cur_channel_id) {
            switch (addr & 0xFFFF) {
            case NV_USER_DMA_PUT:
                r = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUT];
                break;
            case NV_USER_DMA_GET:
                r = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_GET];
                break;
            case NV_USER_REF:
                r = d->pfifo.regs[NV_PFIFO_CACHE1_REF];
                break;
            default:
                break;
            }
        } else {
            /* ramfc */
            assert(!"Unsupported: channel_id != cur_channel_id");
        }
    } else {
        /* PIO Mode */
        assert(!"Failed to enter DMA mode - entered PIO mode");
    }

    qemu_mutex_unlock(&d->pfifo.lock);

    nv2a_reg_log_read(NV_USER, addr, size, r);
    return r;
}

void user_write(void *opaque, hwaddr addr, uint64_t val, unsigned int size)
{
    NV2AState *d = (NV2AState *)opaque;
    UserDmaPutTraceSnapshot dma_put_snapshot = { 0 };

    nv2a_reg_log_write(NV_USER, addr, size, val);

    unsigned int channel_id = addr >> 16;
    assert(channel_id < NV2A_NUM_CHANNELS);

    qemu_mutex_lock(&d->pfifo.lock);

    uint32_t channel_modes = d->pfifo.regs[NV_PFIFO_MODE];
    if (channel_modes & (1 << channel_id)) {
        /* DMA Mode */
        unsigned int cur_channel_id =
            GET_MASK(d->pfifo.regs[NV_PFIFO_CACHE1_PUSH1],
                     NV_PFIFO_CACHE1_PUSH1_CHID);

        if (channel_id == cur_channel_id) {
            const char *kick_source = "nv-user-write";
            uint32_t old_dma_put = d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUT];

            switch (addr & 0xFFFF) {
            case NV_USER_DMA_PUT:
                kick_source = "nv-user-dma-put";
                d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUT] = val;
                user_boot_trace_dma_put_snapshot(&dma_put_snapshot, d,
                                                 channel_id, cur_channel_id,
                                                 addr, val, size,
                                                 old_dma_put);
                break;
            case NV_USER_DMA_GET:
                kick_source = "nv-user-dma-get";
                d->pfifo.regs[NV_PFIFO_CACHE1_DMA_GET] = val;
                break;
            case NV_USER_REF:
                kick_source = "nv-user-ref";
                d->pfifo.regs[NV_PFIFO_CACHE1_REF] = val;
                break;
            default:
                NV2A_DPRINTF(true, "Unsupported NV_USER write: channel=%u offset=0x%04x\n", channel_id, (unsigned)(addr & 0xFFFF));
                assert(!"Unsupported NV_USER DMA register write offset");
                break;
            }

            pfifo_kick_with_source(d, kick_source);

        } else {
            /* ramfc */
            assert(!"Invalid channel id");
        }
    } else {
        /* PIO Mode */
        assert(!"Failed to enter DMA mode - entered PIO mode");
    }

    qemu_mutex_unlock(&d->pfifo.lock);

    user_boot_trace_dma_put_emit(&dma_put_snapshot);
}
