/*
 * xemu XBE accessing
 *
 * Helper functions to get details about the currently running executable.
 *
 * Copyright (C) 2020-2021 Matt Borgerson
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "xemu-xbe.h"
#include "qemu/osdep.h"
#include "qemu/thread.h"
#include "hw/hw.h"
#include "hw/i386/pc.h"
#include "hw/pci/pci.h"
#include "system/hw_accel.h"
#include "system/dma.h"
#include "system/address-spaces.h"
#include "system/memory.h"
#include "qemu/timer.h"
#include "cpu.h"
#include "exec/target_page.h"
#include "hw/xbox/nv2a/nv2a_regs.h"

#define XEMU_XBE_MAX_HEADERS (8 * TARGET_PAGE_SIZE)
#define XEMU_XBE_PHYS_SCAN_CHUNK_SIZE (64 * 1024)
#define XEMU_XBE_PHYS_SCAN_STRIDE 512
#define XEMU_XBE_PHYS_SCAN_DEFAULT_LIMIT (64 * 1024 * 1024)
#define XEMU_XBE_PHYS_SCAN_INTERVAL_US (1000 * 1000)
#define XEMU_XBE_VIRTUAL_PROBE_INTERVAL_US (1000 * 1000)
#define XEMU_XBE_VIRTUAL_PROBE_DEFAULT_LIMIT 16
#define XEMU_XBE_READ_PROGRESS_DEFAULT_LIMIT 32
#define XEMU_XBE_EXEC_PROBE_DEFAULT_LIMIT 32
#define XEMU_XBE_EXEC_PROBE_DEFAULT_STRIDE 100000
#define XEMU_XBE_EXEC_PROBE_INITIAL_SAMPLES 8
#define XEMU_XBE_PHYS_COMPARE_DEFAULT_LIMIT 32
#define XEMU_XBE_ENTRY_PROBE_DEFAULT_LIMIT 16
#define XEMU_XBE_ENTRY_TARGET_DEFAULT_LIMIT 16
#define XEMU_XBE_ENTRY_TARGET_DEFAULT_WINDOW 65536
#define XEMU_XBE_DISPATCH_PROBE_DEFAULT_LIMIT 16
#define XEMU_XBE_DISPATCH_STACK_WORDS 16
#define XEMU_XBE_DISPATCH_STACK_BYTES \
    (XEMU_XBE_DISPATCH_STACK_WORDS * sizeof(uint32_t))
#define XEMU_XBE_KERNEL_LOOP_DEFAULT_LIMIT 32
#define XEMU_XBE_KERNEL_LOOP_AFTER_IDLE_DEFAULT_LIMIT 16
#define XEMU_XBE_IDLE_BEFORE_PFIFO_TRANSITION_DEFAULT_LIMIT 16
#define XEMU_XBE_KERNEL_LOOP_DEFAULT_MIN_HITS 16
#define XEMU_XBE_ALIAS_COMPARE_DEFAULT_LIMIT 32
#define XEMU_XBE_PIC_IRQ_DEFAULT_LIMIT 512
#define XEMU_XBE_CPU_HARD_IRQ_DEFAULT_LIMIT 512
#define XEMU_XBE_IRET_DEFAULT_LIMIT 256
#define XEMU_XBE_PIT_IRQ_DEFAULT_LIMIT 128
#define XEMU_XBE_MAIN_LOOP_TIMER_DEFAULT_LIMIT 128
#define XEMU_XBE_TIMER_OPPORTUNITY_DEFAULT_LIMIT 128
#define XEMU_XBE_TCG_TIMER_PUMP_DEFAULT_LIMIT 64
#define XEMU_XBE_TCG_TIMER_PUMP_GATE_DEFAULT_LIMIT 64
#define XEMU_XBE_TCG_TIMER_PUMP_AFTER_IDLE_DEFAULT_LIMIT \
    XEMU_XBE_KERNEL_LOOP_AFTER_IDLE_DEFAULT_LIMIT
#define XEMU_XBE_TCG_TIMER_PUMP_DEFAULT_INTERVAL 0
#define XEMU_XBE_TCG_TIMER_PUMP_IDLE_LOOP_PC_1 UINT64_C(0x8001b02f)
#define XEMU_XBE_TCG_TIMER_PUMP_IDLE_LOOP_PC_2 UINT64_C(0x8001b030)
#define XEMU_XBE_FIRST_READ_PREDECESSOR_PC_BROWSER UINT64_C(0x80014f32)
#define XEMU_XBE_FIRST_READ_PREDECESSOR_PC_NATIVE UINT64_C(0x80014f5f)
#define XEMU_XBE_MEMORY_WATCH_DEFAULT_LIMIT 32
#define XEMU_XBE_MEMORY_WATCH_BYTES 4
#define XEMU_XBE_EXEC_CODE_PROBE_BYTES 16
#define XEMU_XBE_EXEC_EDGE_MAX 64
#define XEMU_XBE_EXEC_EDGE_DEFAULT_LIMIT 64
#define XEMU_XBE_TICK_BLOCK_PC UINT64_C(0x80030e84)
#define XEMU_XBE_TICK_BLOCK_NEXT_PC UINT64_C(0x80030f31)
#define XEMU_XBE_TICK_BLOCK_WATCH_PHYS UINT64_C(0x0003a890)
#define XEMU_XBE_TICK_BLOCK_TICK_UNIT UINT32_C(0x00002710)
#define XEMU_XBE_TICK_BLOCK_DEFAULT_LIMIT 256
#define XEMU_XBE_TICK_BLOCK_IRQ_DEFER_DEFAULT_LIMIT 8
#define XEMU_XBE_PRE_FIRST_READ_SCHEDULER_DEFAULT_TB_BUDGET 512
#define XEMU_XBE_EDGE_DECISION_PC XEMU_XBE_TICK_BLOCK_PC
#define XEMU_XBE_EDGE_DECISION_CMP_ADDR UINT64_C(0x80035c34)
#define XEMU_XBE_IDE_SECTOR_SIZE 512
#define XEMU_XBE_LOW_RAM_BYTES (64ULL * 1024 * 1024)
#define XEMU_XBE_IRQ_STACK_WORDS 8
#define XEMU_XBE_IRQ_STACK_BYTES \
    (XEMU_XBE_IRQ_STACK_WORDS * sizeof(uint32_t))
#define XEMU_XBE_SECTION_FLAG_WRITABLE 0x00000001U
#define XEMU_XBE_SECTION_FLAG_PRELOAD 0x00000002U
#define XEMU_XBE_SECTION_FLAG_EXECUTABLE 0x00000004U
#define XEMU_XBE_SECTION_MAP_DEFAULT_LIMIT 32

struct xemu_xbe_dma_header_observation {
    bool present;
    uint64_t sequence;
    uint64_t dma_addr;
    int64_t read_lba;
    int nsectors;
    uint32_t image_base;
    uint32_t image_size;
    uint32_t headers_size;
    uint32_t entry;
    uint64_t contiguous_bytes;
    bool read_complete_marked;
    bool preload_direct_exec_candidate_marked;
};

struct xemu_xbe_loaded_observation {
    bool loaded_marked;
    bool executed_marked;
    bool header_resident_marked;
    bool entry_marked;
    bool section_map_loaded_marked;
    bool section_map_entry_ready_marked;
    bool executed_detector_proof_marked;
    bool exec_section_miss_marked;
    uint64_t exec_probe_count;
    uint64_t exec_probe_observed_count;
    uint64_t exec_transition_probe_count;
    uint64_t exec_transition_probe_observed_count;
    uint64_t exec_edge_probe_count;
    uint64_t exec_entry_target_probe_count;
    uint64_t exec_dispatch_probe_count;
    uint64_t exec_kernel_loop_probe_count;
    uint64_t exec_kernel_loop_after_idle_probe_count;
    uint64_t exec_edge_decision_probe_count;
    uint64_t exec_edge_decision_skip_count;
    uint64_t exec_tick_block_probe_count;
    uint64_t exec_tick_block_pre_stream_count;
    uint64_t exec_tick_block_irq_defer_probe_count;
    uint64_t pre_first_read_scheduler_probe_count;
    uint64_t pre_first_read_scheduler_gate_probe_count;
    uint64_t exec_alias_compare_probe_count;
    uint64_t exec_phys_compare_probe_count;
    uint64_t entry_probe_count;
    uint32_t base;
    uint32_t size;
    uint32_t headers_size;
    uint32_t entry;
};

#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
typedef enum XemuXbeMemoryWatchAccessMode {
    XEMU_XBE_MEMORY_WATCH_ACCESS_OFF,
    XEMU_XBE_MEMORY_WATCH_ACCESS_ALL,
    XEMU_XBE_MEMORY_WATCH_ACCESS_READ,
    XEMU_XBE_MEMORY_WATCH_ACCESS_WRITE,
} XemuXbeMemoryWatchAccessMode;

static bool xemu_xbe_memory_watch_suppress;
static bool xemu_xbe_memory_watch_install_attempted;
static uint64_t xemu_xbe_memory_watch_emit_count;
static hwaddr xemu_xbe_memory_watch_phys_addr;
static hwaddr xemu_xbe_memory_watch_region_offset;
static MemAccessCallback *xemu_xbe_memory_watch_callback_ref;
#endif

struct xemu_xbe_exec_edge_observation {
    bool used;
    uint64_t start_pc;
    uint64_t next_pc;
    uint32_t tb_size;
    int tb_exit;
    uint64_t hits;
};

struct xemu_xbe_exec_transition_snapshot {
    bool valid;
    bool next_pc_known;
    uint64_t observed_count;
    uint64_t start_pc;
    uint64_t next_pc;
    uint32_t tb_size;
    int tb_exit;
};

static struct xemu_xbe_dma_header_observation xemu_xbe_dma_observation;
static struct xemu_xbe_loaded_observation xemu_xbe_loaded_observation;
static struct xemu_xbe_exec_edge_observation
    xemu_xbe_exec_edge_observations[XEMU_XBE_EXEC_EDGE_MAX];
static struct xemu_xbe_exec_transition_snapshot
    xemu_xbe_latest_exec_transition;

static bool xemu_call_chain_trace_enabled(void)
{
    const char *value = getenv("XEMU_BOOT_TRACE_CALL_CHAIN");

    if (value && value[0]) {
        return strcmp(value, "0");
    }

#ifdef CONFIG_XEMU_BROWSER_BOOT
    static bool initialized;
    static bool enabled;
    const char *paths[] = {
        "/xemu-fixtures/call_chain_trace.txt",
        "/xemu-smoke/call_chain_trace.txt",
        "/xemu-smoke-out/call_chain_trace.txt",
        NULL,
    };
    char buffer[32];

    if (initialized) {
        return enabled;
    }
    initialized = true;

    for (int i = 0; paths[i]; i++) {
        FILE *fp = fopen(paths[i], "r");

        if (!fp) {
            continue;
        }

        if (fgets(buffer, sizeof(buffer), fp)) {
            buffer[strcspn(buffer, "\r\n")] = 0;
        } else {
            buffer[0] = 0;
        }
        fclose(fp);

        if (!buffer[0]) {
            continue;
        }

        enabled = g_ascii_strcasecmp(buffer, "0") &&
                  g_ascii_strcasecmp(buffer, "false") &&
                  g_ascii_strcasecmp(buffer, "no") &&
                  g_ascii_strcasecmp(buffer, "off");
        return enabled;
    }
#endif

    return false;
}

static void xemu_call_chain_trace_once(bool *emitted, const char *event,
                                       const char *method)
{
    if (!*emitted && xemu_call_chain_trace_enabled()) {
        *emitted = true;
        fprintf(stderr, "CALL_CHAIN %s %s!\n", event, method);
    }
}

struct xemu_xbe_nv2a_wait_snapshot {
    bool present;
    uint64_t generation;
    char source[32];
    char op[32];
    XemuXbeBootTraceNv2aWaitState state;
};

struct xemu_xbe_pfifo_activity_snapshot {
    bool present;
    uint64_t generation;
    char source[32];
    char phase[48];
    XemuXbeBootTracePfifoActivityState state;
};

struct xemu_xbe_tcg_timer_pump_trace {
    bool active;
    uint64_t sequence;
    uint64_t observed_tbs;
    int64_t interval_tbs;
    int64_t virtual_now_before;
    int64_t virtual_deadline_before;
    bool virtual_has_timers_before;
    bool virtual_expired_before;
};

static QemuMutex xemu_xbe_nv2a_wait_snapshot_lock;
static struct xemu_xbe_nv2a_wait_snapshot
    xemu_xbe_nv2a_wait_snapshot;
static struct xemu_xbe_nv2a_wait_snapshot
    xemu_xbe_last_pfifo_stream_idle_snapshot;
static struct xemu_xbe_pfifo_activity_snapshot
    xemu_xbe_pfifo_activity_snapshot;
static struct xemu_xbe_tcg_timer_pump_trace xemu_xbe_tcg_timer_pump_trace;
static bool xemu_xbe_pfifo_stream_idle_transition_seen;

static void xemu_xbe_boot_trace_virtual_probe(void);
static const char *xemu_xbe_boot_trace_context(void);
static int64_t xemu_xbe_exec_probe_limit(void);
static uint64_t xemu_xbe_exec_probe_stride(void);
static int64_t xemu_xbe_phys_compare_probe_limit(void);
static int64_t xemu_xbe_exec_edge_limit(void);
static int64_t xemu_xbe_entry_target_limit(void);
static uint64_t xemu_xbe_entry_target_window(void);
static int64_t xemu_xbe_dispatch_probe_limit(void);
static int64_t xemu_xbe_kernel_loop_probe_limit(void);
static int64_t xemu_xbe_kernel_loop_after_idle_probe_limit(void);
static int64_t xemu_xbe_idle_before_pfifo_transition_probe_limit(void);
static uint64_t xemu_xbe_kernel_loop_probe_min_hits(void);
static int64_t xemu_xbe_alias_compare_probe_limit(void);
static int64_t xemu_xbe_pic_irq_probe_limit(void);
static int64_t xemu_xbe_cpu_hard_irq_probe_limit(void);
static int64_t xemu_xbe_iret_probe_limit(void);
static int64_t xemu_xbe_pit_irq_probe_limit(void);
static int64_t xemu_xbe_main_loop_timer_probe_limit(void);
static int64_t xemu_xbe_timer_opportunity_probe_limit(void);
static int64_t xemu_xbe_tcg_timer_pump_probe_limit(void);
static int64_t xemu_xbe_tcg_timer_pump_gate_probe_limit(void);
static int64_t xemu_xbe_tcg_timer_pump_after_idle_probe_limit(void);
static int64_t xemu_xbe_tick_block_probe_limit(void);
static int64_t xemu_xbe_tick_block_irq_defer_probe_limit(void);
static bool xemu_xbe_tick_block_irq_defer_enabled(void);
static int64_t xemu_xbe_pre_first_read_scheduler_tb_budget(void);
#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
static int64_t xemu_xbe_memory_watch_limit(void);
static uint64_t xemu_xbe_memory_watch_phys(void);
#endif
#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
static XemuXbeMemoryWatchAccessMode xemu_xbe_memory_watch_access_mode(void);
static bool xemu_xbe_memory_watch_access_enabled(void);
static bool xemu_xbe_memory_watch_access_matches(bool write);
static const char *xemu_xbe_memory_watch_access_mode_name(void);
#endif
static bool xemu_xbe_irq_after_pfifo_empty_only(void);
static bool xemu_xbe_irq_watch_matches(int guest_irq);
static const char *xemu_xbe_browser_headless_timer_pump_mode(void);
static const char *xemu_xbe_main_loop_timer_pump_block_reason(
    const struct xemu_xbe_nv2a_wait_snapshot *wait_state);
static bool xemu_xbe_timer_pump_idle_loop_before_pfifo_transition_ready(
    const struct xemu_xbe_nv2a_wait_snapshot *wait_state,
    bool activity_gate,
    const char *marker_kind,
    const char *mode);
static bool xemu_xbe_nv2a_wait_is_stream_idle(
    const struct xemu_xbe_nv2a_wait_snapshot *snapshot);
static void xemu_xbe_boot_trace_record_pfifo_stream_idle_state(
    const XemuXbeBootTraceNv2aWaitState *state);
static void xemu_xbe_boot_trace_latest_pfifo_stream_idle_state(
    struct xemu_xbe_nv2a_wait_snapshot *snapshot);
static bool xemu_xbe_pfifo_stream_idle_transition_observed(void);
static bool xemu_xbe_boot_trace_read_fixture_setting(const char *file_name,
                                                     char *buffer,
                                                     size_t buffer_size);
static int64_t xemu_xbe_boot_trace_limit_setting(const char *env_name,
                                                 const char *file_name,
                                                 int64_t default_limit);
#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
static uint64_t xemu_xbe_boot_trace_u64_setting(const char *env_name,
                                                const char *file_name,
                                                uint64_t default_value);
#endif
static int64_t xemu_xbe_edge_decision_limit(void);
static void xemu_xbe_boot_trace_memory_watch_install(void);
static bool xemu_xbe_boot_trace_memory_watch_sample(uint64_t *phys_out,
                                                    uint32_t *value_out);
static bool xemu_xbe_read_phys_u32(hwaddr phys_addr, uint32_t *value);
static void xemu_xbe_pre_first_read_scheduler_note_timer_pump(bool progress);
static void xemu_xbe_pre_first_read_scheduler_note_first_read(
    uint64_t guest_pc,
    uint32_t tb_size,
    const char *source);
static void xemu_xbe_pre_first_read_scheduler_note_tick_block(
    uint64_t guest_pc,
    uint32_t tb_size,
    int tb_exit,
    const char *source);

static void xemu_xbe_nv2a_wait_snapshot_lock_guard(void)
{
    static gsize initialized;

    if (g_once_init_enter(&initialized)) {
        qemu_mutex_init(&xemu_xbe_nv2a_wait_snapshot_lock);
        g_once_init_leave(&initialized, 1);
    }

    qemu_mutex_lock(&xemu_xbe_nv2a_wait_snapshot_lock);
}

struct xemu_xbe_page_probe {
    bool cpu_known;
    uint64_t cr0;
    uint64_t cr3;
    uint64_t cr4;
    uint64_t efer;
    hwaddr pdpe_addr;
    uint64_t pdpe;
    hwaddr pde_addr;
    uint64_t pde;
    hwaddr pte_addr;
    uint64_t pte;
    const char *status;
};

struct xemu_xbe_pc_mapping {
    uint64_t pc;
    hwaddr phys_addr;
    bool mapped;
};

struct xemu_xbe_exec_context {
    bool cpu_known;
    const char *mode;
    uint32_t cpl;
    uint64_t eip;
    uint64_t eax;
    uint64_t ebx;
    uint64_t ecx;
    uint64_t edx;
    uint64_t esp;
    uint64_t ebp;
    uint64_t esi;
    uint64_t edi;
    uint64_t eflags;
    uint64_t computed_eflags;
    uint64_t hflags;
    uint64_t cr0;
    uint64_t cr3;
    uint64_t cr4;
    uint64_t efer;
    uint32_t cs_selector;
    uint64_t cs_base;
    uint32_t ss_selector;
    uint64_t ss_base;
    uint32_t cpu_interrupt_request;
    bool cpu_halted;
    bool cpu_exit_request;
    int32_t cpu_exception_index;
};

static const char *xemu_xbe_tcg_timer_pump_before_pfifo_gate_reason(
    struct xemu_xbe_exec_context *exec_ctx,
    struct xemu_xbe_pfifo_activity_snapshot *activity,
    uint32_t *activity_dma_to_put,
    bool activity_gate);

struct xemu_xbe_stack_probe {
    bool read_ok;
    uint64_t hash;
    uint32_t words[XEMU_XBE_IRQ_STACK_WORDS];
};

struct xemu_xbe_branch_probe {
    const char *kind;
    bool target_known;
    uint64_t target;
    bool operand_addr_known;
    uint64_t operand_addr;
};

struct xemu_xbe_code_probe {
    bool read_ok;
    uint8_t bytes[XEMU_XBE_EXEC_CODE_PROBE_BYTES];
    size_t len;
    uint64_t hash;
    uint8_t opcode;
    uint8_t opcode2;
    uint8_t modrm;
    bool opcode2_known;
    bool modrm_known;
    struct xemu_xbe_branch_probe branch;
    const char *mem_kind;
    uint32_t mem_width;
    bool mem_addr_known;
    uint64_t mem_addr;
    const char *mem_region;
    struct xemu_xbe_pc_mapping mem_mapping;
    bool mem_value_read;
    uint32_t mem_value;
};

struct xemu_xbe_edge_decision_snapshot {
    bool valid;
    uint64_t seq;
    uint64_t start_pc;
    uint32_t tb_size;
    const char *source;
    struct xemu_xbe_exec_context pre_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    struct xemu_xbe_code_probe start_code_probe;
    bool watch_value_read;
    uint32_t watch_value;
    bool cmp_mapping_known;
    uint64_t cmp_phys;
    bool cmp_value_read;
    uint32_t cmp_value;
};

static struct xemu_xbe_edge_decision_snapshot
    xemu_xbe_edge_decision_pending;

struct xemu_xbe_tick_block_snapshot {
    bool valid;
    uint64_t start_pc;
    uint32_t tb_size;
    const char *source;
    struct xemu_xbe_exec_context pre_ctx;
    struct xemu_xbe_nv2a_wait_snapshot pre_wait_state;
    bool pre_watch_value_read;
    uint32_t pre_watch_value;
};

static struct xemu_xbe_tick_block_snapshot xemu_xbe_tick_block_pending;

struct xemu_xbe_pre_first_read_scheduler_state {
    bool active;
    bool done;
    bool first_read_seen;
    bool first_read_before_tick_block;
    uint64_t seq;
    uint64_t tb_count;
    uint64_t timer_pump_count;
    uint64_t timer_delivery_count;
    uint64_t start_tick_block_count;
    uint64_t start_edge_decision_count;
    uint64_t start_skip_count;
};

static struct xemu_xbe_pre_first_read_scheduler_state
    xemu_xbe_pre_first_read_scheduler;

struct xemu_xbe_target_classification {
    const char *relation;
    const char *entry_relation;
    const char *address_mode;
    const char *phys_match;
    uint64_t distance;
    uint64_t entry_distance;
    uint64_t image_pc;
    struct xemu_xbe_pc_mapping mapping;
    struct xemu_xbe_pc_mapping image_mapping;
};

struct xemu_xbe_dispatch_candidate {
    bool present;
    const char *label;
    int index;
    uint64_t value;
    struct xemu_xbe_target_classification classification;
};

static const char *xemu_xbe_entry_target_status(
    const struct xemu_xbe_target_classification *classification);
static void xemu_xbe_boot_trace_dispatch_probe(
    uint64_t observed_count,
    uint64_t pc,
    const struct xemu_xbe_exec_context *exec_ctx,
    const char *source);
static void xemu_xbe_capture_exec_context(struct xemu_xbe_exec_context *ctx);
static bool xemu_xbe_boot_trace_kernel_loop_probe(
    uint64_t observed_count,
    const char *probe,
    const struct xemu_xbe_exec_edge_observation *edge,
    const struct xemu_xbe_exec_context *exec_ctx,
    const struct xemu_xbe_code_probe *start_code_probe,
    const struct xemu_xbe_code_probe *next_code_probe,
    bool require_min_hits,
    bool require_stream_idle,
    const char *source);

static const char *xemu_xbe_bool_str(bool value)
{
    return value ? "yes" : "no";
}

static const char *xemu_xbe_tcg_timer_pump_trace_fields(char *buffer,
                                                        size_t buffer_size)
{
    const struct xemu_xbe_tcg_timer_pump_trace *trace =
        &xemu_xbe_tcg_timer_pump_trace;

    snprintf(buffer, buffer_size,
             " timer_pump_active=%s"
             " timer_pump_seq=%" PRIu64
             " timer_pump_observed_tbs=%" PRIu64
             " timer_pump_interval_tbs=%" PRId64
             " timer_pump_now_before=%" PRId64
             " timer_pump_deadline_before=%" PRId64
             " timer_pump_has_timers_before=%s"
             " timer_pump_expired_before=%s",
             xemu_xbe_bool_str(trace->active), trace->sequence,
             trace->observed_tbs, trace->interval_tbs,
             trace->virtual_now_before, trace->virtual_deadline_before,
             xemu_xbe_bool_str(trace->virtual_has_timers_before),
             xemu_xbe_bool_str(trace->virtual_expired_before));

    return buffer;
}

static bool xemu_xbe_boot_trace_enabled(void)
{
#ifdef CONFIG_XEMU_BROWSER_BOOT
    return true;
#else
    const char *value = getenv("XEMU_BOOT_TRACE");

    return value && value[0] && strcmp(value, "0");
#endif
}

void xemu_xbe_boot_trace_enter_tcg_timer_pump(uint64_t observed_tbs,
                                              int64_t interval_tbs,
                                              int64_t virtual_now_before,
                                              int64_t virtual_deadline_before,
                                              bool virtual_has_timers_before,
                                              bool virtual_expired_before)
{
    xemu_xbe_tcg_timer_pump_trace.active = true;
    xemu_xbe_tcg_timer_pump_trace.sequence++;
    xemu_xbe_tcg_timer_pump_trace.observed_tbs = observed_tbs;
    xemu_xbe_tcg_timer_pump_trace.interval_tbs = interval_tbs;
    xemu_xbe_tcg_timer_pump_trace.virtual_now_before = virtual_now_before;
    xemu_xbe_tcg_timer_pump_trace.virtual_deadline_before =
        virtual_deadline_before;
    xemu_xbe_tcg_timer_pump_trace.virtual_has_timers_before =
        virtual_has_timers_before;
    xemu_xbe_tcg_timer_pump_trace.virtual_expired_before =
        virtual_expired_before;
}

void xemu_xbe_boot_trace_leave_tcg_timer_pump(void)
{
    xemu_xbe_tcg_timer_pump_trace.active = false;
}

void xemu_xbe_boot_trace_observe_nv2a_wait_state(
    const XemuXbeBootTraceNv2aWaitState *state)
{
    if (!state || !xemu_xbe_boot_trace_enabled()) {
        return;
    }

    xemu_xbe_nv2a_wait_snapshot_lock_guard();
    xemu_xbe_nv2a_wait_snapshot.present = true;
    xemu_xbe_nv2a_wait_snapshot.generation++;
    xemu_xbe_nv2a_wait_snapshot.state = *state;
    g_strlcpy(xemu_xbe_nv2a_wait_snapshot.source,
              state->source ? state->source : "unknown",
              sizeof(xemu_xbe_nv2a_wait_snapshot.source));
    g_strlcpy(xemu_xbe_nv2a_wait_snapshot.op,
              state->op ? state->op : "unknown",
              sizeof(xemu_xbe_nv2a_wait_snapshot.op));
    xemu_xbe_nv2a_wait_snapshot.state.source =
        xemu_xbe_nv2a_wait_snapshot.source;
    xemu_xbe_nv2a_wait_snapshot.state.op = xemu_xbe_nv2a_wait_snapshot.op;
    qemu_mutex_unlock(&xemu_xbe_nv2a_wait_snapshot_lock);
}

static void xemu_xbe_boot_trace_record_pfifo_stream_idle_state(
    const XemuXbeBootTraceNv2aWaitState *state)
{
    if (!state) {
        return;
    }

    xemu_xbe_nv2a_wait_snapshot_lock_guard();
    xemu_xbe_last_pfifo_stream_idle_snapshot.present = true;
    xemu_xbe_last_pfifo_stream_idle_snapshot.generation++;
    xemu_xbe_last_pfifo_stream_idle_snapshot.state = *state;
    g_strlcpy(xemu_xbe_last_pfifo_stream_idle_snapshot.source,
              state->source ? state->source : "unknown",
              sizeof(xemu_xbe_last_pfifo_stream_idle_snapshot.source));
    g_strlcpy(xemu_xbe_last_pfifo_stream_idle_snapshot.op,
              state->op ? state->op : "unknown",
              sizeof(xemu_xbe_last_pfifo_stream_idle_snapshot.op));
    xemu_xbe_last_pfifo_stream_idle_snapshot.state.source =
        xemu_xbe_last_pfifo_stream_idle_snapshot.source;
    xemu_xbe_last_pfifo_stream_idle_snapshot.state.op =
        xemu_xbe_last_pfifo_stream_idle_snapshot.op;
    qemu_mutex_unlock(&xemu_xbe_nv2a_wait_snapshot_lock);
}

void xemu_xbe_boot_trace_observe_pfifo_activity(
    const XemuXbeBootTracePfifoActivityState *state)
{
    if (!state || !xemu_xbe_boot_trace_enabled()) {
        return;
    }

    xemu_xbe_nv2a_wait_snapshot_lock_guard();
    xemu_xbe_pfifo_activity_snapshot.present = true;
    xemu_xbe_pfifo_activity_snapshot.generation++;
    xemu_xbe_pfifo_activity_snapshot.state = *state;
    g_strlcpy(xemu_xbe_pfifo_activity_snapshot.source,
              state->source ? state->source : "unknown",
              sizeof(xemu_xbe_pfifo_activity_snapshot.source));
    g_strlcpy(xemu_xbe_pfifo_activity_snapshot.phase,
              state->phase ? state->phase : "unknown",
              sizeof(xemu_xbe_pfifo_activity_snapshot.phase));
    xemu_xbe_pfifo_activity_snapshot.state.source =
        xemu_xbe_pfifo_activity_snapshot.source;
    xemu_xbe_pfifo_activity_snapshot.state.phase =
        xemu_xbe_pfifo_activity_snapshot.phase;
    qemu_mutex_unlock(&xemu_xbe_nv2a_wait_snapshot_lock);
}

void xemu_xbe_boot_trace_observe_pfifo_stream_idle_boundary(
    const XemuXbeBootTraceNv2aWaitState *state)
{
    static uint64_t seq;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_exec_transition_snapshot transition =
        xemu_xbe_latest_exec_transition;

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_loaded() ||
        !xemu_xbe_boot_trace_entry_ready() ||
        !state ||
        !state->source ||
        !state->op ||
        strcmp(state->source, "pfifo-window") ||
        strcmp(state->op, "pusher-empty") ||
        !state->pfifo_known ||
        state->dma_get != state->dma_put) {
        return;
    }

    seq++;
    qatomic_set(&xemu_xbe_pfifo_stream_idle_transition_seen, true);
    xemu_xbe_boot_trace_record_pfifo_stream_idle_state(state);
    xemu_xbe_capture_exec_context(&exec_ctx);
    fprintf(stderr,
            "BOOT_MARK b6 pfifo=stream-idle-boundary context=%s"
            " seq=%" PRIu64
            " wait_seq=%" PRIu64
            " wait_source=%s"
            " wait_op=%s"
            " dma_get=0x%08" PRIx32
            " dma_put=0x%08" PRIx32
            " dma_state_method=0x%04" PRIx32
            " dma_state_count=%" PRIu32
            " pmc_pending=0x%08" PRIx32
            " pmc_enabled=0x%08" PRIx32
            " pfifo_pending=0x%08" PRIx32
            " pfifo_enabled=0x%08" PRIx32
            " pgraph_pending=0x%08" PRIx32
            " pgraph_enabled=0x%08" PRIx32
            " fifo_access=%s"
            " halt=%s"
            " fifo_kick=%s"
            " waiting_flip=%s"
            " waiting_nop=%s"
            " waiting_context=%s"
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " last_transition_valid=%s"
            " last_transition_observed_tbs=%" PRIu64
            " last_transition_start_pc=0x%08" PRIx64
            " last_transition_next_pc_known=%s"
            " last_transition_next_pc=0x%08" PRIx64
            " last_transition_tb_size=%" PRIu32
            " last_transition_tb_exit=%d\n",
            xemu_xbe_boot_trace_context(), seq, state->seq, state->source,
            state->op, state->dma_get, state->dma_put,
            state->dma_state_method, state->dma_state_count,
            state->pmc_pending, state->pmc_enabled,
            state->pfifo_pending, state->pfifo_enabled,
            state->pgraph_pending, state->pgraph_enabled,
            xemu_xbe_bool_str(state->fifo_access),
            xemu_xbe_bool_str(state->pfifo_halt),
            xemu_xbe_bool_str(state->pfifo_kick),
            xemu_xbe_bool_str(state->pgraph_waiting_flip),
            xemu_xbe_bool_str(state->pgraph_waiting_nop),
            xemu_xbe_bool_str(state->pgraph_waiting_context),
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(transition.valid),
            transition.valid ? transition.observed_count : 0,
            transition.valid ? transition.start_pc : 0,
            xemu_xbe_bool_str(transition.valid && transition.next_pc_known),
            transition.valid && transition.next_pc_known ? transition.next_pc : 0,
            transition.valid ? transition.tb_size : 0,
            transition.valid ? transition.tb_exit : 0);
}

void xemu_xbe_boot_trace_observe_pfifo_stream_idle_transition(
    const XemuXbeBootTraceNv2aWaitState *state,
    uint32_t dma_get_before,
    uint32_t dma_get_after,
    uint32_t dma_put,
    uint64_t available,
    int64_t processed)
{
    static uint64_t seq;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_exec_transition_snapshot transition =
        xemu_xbe_latest_exec_transition;

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_loaded() ||
        !xemu_xbe_boot_trace_entry_ready() ||
        !state ||
        !state->source ||
        !state->op ||
        strcmp(state->source, "pfifo-transition") ||
        strcmp(state->op, "pusher-empty-transition") ||
        !state->pfifo_known ||
        dma_get_before == dma_get_after ||
        dma_get_after != dma_put) {
        return;
    }

    seq++;
    qatomic_set(&xemu_xbe_pfifo_stream_idle_transition_seen, true);
    xemu_xbe_capture_exec_context(&exec_ctx);
    fprintf(stderr,
            "BOOT_MARK b6 pfifo=stream-idle-transition context=%s"
            " seq=%" PRIu64
            " wait_seq=%" PRIu64
            " wait_source=%s"
            " wait_op=%s"
            " dma_get_before=0x%08" PRIx32
            " dma_get_after=0x%08" PRIx32
            " dma_put=0x%08" PRIx32
            " available=%" PRIu64
            " processed=%" PRId64
            " method=0x%04" PRIx32
            " parameter=0x%08" PRIx32
            " dma_state_method=0x%04" PRIx32
            " dma_state_count=%" PRIu32
            " pmc_pending=0x%08" PRIx32
            " pmc_enabled=0x%08" PRIx32
            " pfifo_pending=0x%08" PRIx32
            " pfifo_enabled=0x%08" PRIx32
            " pgraph_pending=0x%08" PRIx32
            " pgraph_enabled=0x%08" PRIx32
            " fifo_access=%s"
            " halt=%s"
            " fifo_kick=%s"
            " waiting_flip=%s"
            " waiting_nop=%s"
            " waiting_context=%s"
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " last_transition_valid=%s"
            " last_transition_observed_tbs=%" PRIu64
            " last_transition_start_pc=0x%08" PRIx64
            " last_transition_next_pc_known=%s"
            " last_transition_next_pc=0x%08" PRIx64
            " last_transition_tb_size=%" PRIu32
            " last_transition_tb_exit=%d\n",
            xemu_xbe_boot_trace_context(), seq, state->seq, state->source,
            state->op, dma_get_before, dma_get_after, dma_put, available,
            processed, state->method, state->parameter,
            state->dma_state_method, state->dma_state_count,
            state->pmc_pending, state->pmc_enabled,
            state->pfifo_pending, state->pfifo_enabled,
            state->pgraph_pending, state->pgraph_enabled,
            xemu_xbe_bool_str(state->fifo_access),
            xemu_xbe_bool_str(state->pfifo_halt),
            xemu_xbe_bool_str(state->pfifo_kick),
            xemu_xbe_bool_str(state->pgraph_waiting_flip),
            xemu_xbe_bool_str(state->pgraph_waiting_nop),
            xemu_xbe_bool_str(state->pgraph_waiting_context),
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(transition.valid),
            transition.valid ? transition.observed_count : 0,
            transition.valid ? transition.start_pc : 0,
            xemu_xbe_bool_str(transition.valid && transition.next_pc_known),
            transition.valid && transition.next_pc_known ? transition.next_pc : 0,
            transition.valid ? transition.tb_size : 0,
            transition.valid ? transition.tb_exit : 0);
}

static void xemu_xbe_boot_trace_latest_nv2a_wait_state(
    struct xemu_xbe_nv2a_wait_snapshot *snapshot)
{
    xemu_xbe_nv2a_wait_snapshot_lock_guard();
    *snapshot = xemu_xbe_nv2a_wait_snapshot;
    qemu_mutex_unlock(&xemu_xbe_nv2a_wait_snapshot_lock);

    snapshot->state.source = snapshot->source;
    snapshot->state.op = snapshot->op;
}

static void xemu_xbe_boot_trace_latest_pfifo_stream_idle_state(
    struct xemu_xbe_nv2a_wait_snapshot *snapshot)
{
    xemu_xbe_nv2a_wait_snapshot_lock_guard();
    *snapshot = xemu_xbe_last_pfifo_stream_idle_snapshot;
    qemu_mutex_unlock(&xemu_xbe_nv2a_wait_snapshot_lock);

    snapshot->state.source = snapshot->source;
    snapshot->state.op = snapshot->op;
}

static void xemu_xbe_boot_trace_latest_pfifo_activity(
    struct xemu_xbe_pfifo_activity_snapshot *snapshot)
{
    xemu_xbe_nv2a_wait_snapshot_lock_guard();
    *snapshot = xemu_xbe_pfifo_activity_snapshot;
    qemu_mutex_unlock(&xemu_xbe_nv2a_wait_snapshot_lock);

    snapshot->state.source = snapshot->source;
    snapshot->state.phase = snapshot->phase;
}

static bool xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(
    const struct xemu_xbe_nv2a_wait_snapshot *snapshot)
{
    return snapshot && snapshot->present &&
           !strcmp(snapshot->state.source, "pfifo-window") &&
           !strcmp(snapshot->state.op, "pusher-empty");
}

static const char *xemu_xbe_nv2a_wait_pfifo_empty_blocker(
    const struct xemu_xbe_nv2a_wait_snapshot *snapshot)
{
    if (!snapshot || !snapshot->present) {
        return "wait-missing";
    }
    if (strcmp(snapshot->state.source, "pfifo-window")) {
        return "wait-source-not-pfifo-window";
    }
    if (strcmp(snapshot->state.op, "pusher-empty")) {
        return "wait-op-not-pusher-empty";
    }

    return "none";
}

static bool xemu_xbe_nv2a_wait_snapshot_is_pcrtc_wait(
    const struct xemu_xbe_nv2a_wait_snapshot *snapshot)
{
    return snapshot && snapshot->present &&
           !strcmp(snapshot->state.source, "pcrtc") &&
           (!strcmp(snapshot->state.op, "intr-clear") ||
            !strcmp(snapshot->state.op, "intr-enable") ||
            !strcmp(snapshot->state.op, "vblank-suppress") ||
            !strcmp(snapshot->state.op, "vblank-raise"));
}

static bool xemu_xbe_nv2a_wait_snapshot_is_pcrtc_intr_clear(
    const struct xemu_xbe_nv2a_wait_snapshot *snapshot)
{
    return snapshot && snapshot->present &&
           !strcmp(snapshot->state.source, "pcrtc") &&
           !strcmp(snapshot->state.op, "intr-clear") &&
           (snapshot->state.pcrtc_enabled & NV_PCRTC_INTR_0_VBLANK) &&
           !(snapshot->state.pcrtc_pending & NV_PCRTC_INTR_0_VBLANK) &&
           !(snapshot->state.pmc_pending & NV_PMC_INTR_0_PCRTC);
}

static bool xemu_xbe_irq_trace_gate_allows(
    int guest_irq,
    const struct xemu_xbe_nv2a_wait_snapshot *wait_state)
{
    if (!xemu_xbe_irq_after_pfifo_empty_only()) {
        return true;
    }

    return xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(wait_state) ||
           xemu_xbe_irq_watch_matches(guest_irq);
}

bool xemu_xbe_boot_trace_loaded(void)
{
    return xemu_xbe_loaded_observation.loaded_marked &&
           !xemu_xbe_loaded_observation.executed_marked;
}

bool xemu_xbe_boot_trace_entry_ready(void)
{
    return xemu_xbe_loaded_observation.entry_marked;
}

static bool xemu_xbe_browser_headless_timer_pump_mode_is_pretransition(
    const char *mode)
{
    return mode &&
           (!g_ascii_strcasecmp(mode, "pfifo-before-transition-activity") ||
            !g_ascii_strcasecmp(
                mode,
                "pfifo-before-transition-activity-then-after-pfifo-empty") ||
            !g_ascii_strcasecmp(
                mode,
                "pcrtc-before-stream-idle-then-after-pfifo-empty") ||
            !g_ascii_strcasecmp(
                mode,
                "pcrtc-intr-clear-before-stream-idle-then-after-pfifo-empty") ||
            !g_ascii_strcasecmp(
                mode,
                "deterministic-pcrtc-prestream-tick-window"));
}

static bool xemu_xbe_browser_headless_timer_pump_mode_is_ready_edge(
    const char *mode)
{
    return mode &&
           (!g_ascii_strcasecmp(mode, "pfifo-ready-edge-qemu-pump") ||
            !g_ascii_strcasecmp(mode, "pfifo-ready-edge-qemu-pump-all") ||
            !g_ascii_strcasecmp(mode, "pfifo-stream-idle-ready-edge") ||
            !g_ascii_strcasecmp(mode, "ready-edge"));
}

static bool xemu_xbe_browser_headless_timer_pump_mode_is_ready_edge_all_timers(
    const char *mode)
{
    return mode &&
           !g_ascii_strcasecmp(mode, "pfifo-ready-edge-qemu-pump-all");
}

static bool xemu_xbe_browser_headless_timer_pump_mode_is_pcrtc_prestream(
    const char *mode)
{
    return mode &&
           (!g_ascii_strcasecmp(
                mode,
                "pcrtc-intr-clear-before-stream-idle-then-after-pfifo-empty") ||
            !g_ascii_strcasecmp(
                mode,
                "deterministic-pcrtc-prestream-tick-window"));
}

static bool xemu_xbe_main_loop_timer_source_is_browser_diagnostic(
    const char *source)
{
    return source &&
           (!strcmp(source, "browser-headless-host-pump-bounded") ||
            !strcmp(source, "browser-deterministic-pump") ||
            !strcmp(source, "browser-deterministic-pcrtc-prestream") ||
            !strcmp(source, "browser-ready-edge-qemu-pump") ||
            !strcmp(source, "browser-ready-edge-qemu-pump-all"));
}

bool xemu_xbe_boot_trace_main_loop_timer_pump_pcrtc_prestream_ready(void)
{
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    const char *mode;

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready() ||
        xemu_xbe_main_loop_timer_probe_limit() <= 0) {
        return false;
    }

    mode = xemu_xbe_browser_headless_timer_pump_mode();
    if (!xemu_xbe_browser_headless_timer_pump_mode_is_pcrtc_prestream(mode) ||
        xemu_xbe_pfifo_stream_idle_transition_observed()) {
        return false;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    return xemu_xbe_nv2a_wait_snapshot_is_pcrtc_intr_clear(&wait_state);
}

bool xemu_xbe_boot_trace_main_loop_timer_pump_ready(void)
{
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    const char *mode;

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready() ||
        xemu_xbe_main_loop_timer_probe_limit() <= 0) {
        return false;
    }

    mode = xemu_xbe_browser_headless_timer_pump_mode();
    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (xemu_xbe_browser_headless_timer_pump_mode_is_pcrtc_prestream(mode)) {
        if (xemu_xbe_pfifo_stream_idle_transition_observed()) {
            return xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(&wait_state);
        }

        if (xemu_xbe_nv2a_wait_snapshot_is_pcrtc_intr_clear(&wait_state)) {
            return true;
        }

        return xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(&wait_state);
    }
    if (!g_ascii_strcasecmp(mode, "entry-ready")) {
        return true;
    }
    if (!g_ascii_strcasecmp(mode, "after-pfifo-empty")) {
        return xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(&wait_state);
    }
    if (!g_ascii_strcasecmp(mode, "pfifo-before-transition-activity")) {
        return xemu_xbe_timer_pump_idle_loop_before_pfifo_transition_ready(
            &wait_state, true, "headless", mode);
    }
    if (!g_ascii_strcasecmp(
            mode,
            "pfifo-before-transition-activity-then-after-pfifo-empty")) {
        if (xemu_xbe_pfifo_stream_idle_transition_observed()) {
            return xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(&wait_state);
        }

        return xemu_xbe_timer_pump_idle_loop_before_pfifo_transition_ready(
            &wait_state, true, "headless", mode);
    }
    if (!g_ascii_strcasecmp(
            mode,
            "pcrtc-before-stream-idle-then-after-pfifo-empty")) {
        if (xemu_xbe_pfifo_stream_idle_transition_observed()) {
            return xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(&wait_state);
        }

        return xemu_xbe_nv2a_wait_snapshot_is_pcrtc_wait(&wait_state);
    }
    if (xemu_xbe_browser_headless_timer_pump_mode_is_ready_edge(mode)) {
        return xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(&wait_state);
    }

    if (xemu_xbe_irq_after_pfifo_empty_only() &&
        !xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(&wait_state)) {
        return false;
    }

    return true;
}

static const char *xemu_xbe_main_loop_timer_pump_block_reason(
    const struct xemu_xbe_nv2a_wait_snapshot *wait_state)
{
    const char *mode;

    if (!xemu_xbe_boot_trace_enabled()) {
        return "trace-disabled";
    }
    if (!xemu_xbe_boot_trace_entry_ready()) {
        return "entry-not-ready";
    }
    if (xemu_xbe_main_loop_timer_probe_limit() <= 0) {
        return "main-loop-timer-limit";
    }

    mode = xemu_xbe_browser_headless_timer_pump_mode();
    if (xemu_xbe_browser_headless_timer_pump_mode_is_pcrtc_prestream(mode)) {
        if (xemu_xbe_pfifo_stream_idle_transition_observed()) {
            return xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(wait_state) ?
                NULL : "wait-not-pfifo-empty";
        }

        if (xemu_xbe_nv2a_wait_snapshot_is_pcrtc_intr_clear(wait_state) ||
            xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(wait_state)) {
            return NULL;
        }

        return "wait-not-pcrtc-intr-clear-or-pfifo-empty";
    }
    if (!g_ascii_strcasecmp(mode, "entry-ready")) {
        return NULL;
    }
    if (!g_ascii_strcasecmp(mode, "after-pfifo-empty")) {
        return xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(wait_state) ?
            NULL : "wait-not-pfifo-empty";
    }
    if (!g_ascii_strcasecmp(mode, "pfifo-before-transition-activity")) {
        struct xemu_xbe_exec_context exec_ctx;
        struct xemu_xbe_pfifo_activity_snapshot activity;
        uint32_t activity_dma_to_put = 0;

        return xemu_xbe_tcg_timer_pump_before_pfifo_gate_reason(
            &exec_ctx, &activity, &activity_dma_to_put, true);
    }
    if (!g_ascii_strcasecmp(
            mode,
            "pfifo-before-transition-activity-then-after-pfifo-empty")) {
        if (xemu_xbe_pfifo_stream_idle_transition_observed()) {
            return xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(wait_state) ?
                NULL : "wait-not-pfifo-empty";
        }

        {
            struct xemu_xbe_exec_context exec_ctx;
            struct xemu_xbe_pfifo_activity_snapshot activity;
            uint32_t activity_dma_to_put = 0;

            return xemu_xbe_tcg_timer_pump_before_pfifo_gate_reason(
                &exec_ctx, &activity, &activity_dma_to_put, true);
        }
    }
    if (!g_ascii_strcasecmp(
            mode,
            "pcrtc-before-stream-idle-then-after-pfifo-empty")) {
        if (xemu_xbe_pfifo_stream_idle_transition_observed()) {
            return xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(wait_state) ?
                NULL : "wait-not-pfifo-empty";
        }

        return xemu_xbe_nv2a_wait_snapshot_is_pcrtc_wait(wait_state) ?
            NULL : "wait-not-pcrtc";
    }
    if (xemu_xbe_browser_headless_timer_pump_mode_is_ready_edge(mode)) {
        return xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(wait_state) ?
            NULL : "wait-not-pfifo-empty";
    }

    if (xemu_xbe_irq_after_pfifo_empty_only() &&
        !xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(wait_state)) {
        return "irq-after-pfifo-empty";
    }

    return NULL;
}

bool xemu_xbe_boot_trace_main_loop_timer_pump_ready_edge_enabled(void)
{
    const char *mode = xemu_xbe_browser_headless_timer_pump_mode();

    return xemu_xbe_boot_trace_enabled() &&
           xemu_xbe_boot_trace_entry_ready() &&
           xemu_xbe_main_loop_timer_probe_limit() > 0 &&
           xemu_xbe_browser_headless_timer_pump_mode_is_ready_edge(mode);
}

bool xemu_xbe_boot_trace_main_loop_timer_pump_ready_edge_all_timers(void)
{
    const char *mode = xemu_xbe_browser_headless_timer_pump_mode();

    return xemu_xbe_boot_trace_main_loop_timer_pump_ready_edge_enabled() &&
           xemu_xbe_browser_headless_timer_pump_mode_is_ready_edge_all_timers(
               mode);
}

bool xemu_xbe_boot_trace_main_loop_timer_pump_presleep_enabled(void)
{
    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready() ||
        xemu_xbe_main_loop_timer_probe_limit() <= 0) {
        return false;
    }

    return xemu_xbe_browser_headless_timer_pump_mode_is_pretransition(
        xemu_xbe_browser_headless_timer_pump_mode());
}

bool xemu_xbe_boot_trace_executed(void)
{
    return xemu_xbe_loaded_observation.executed_marked;
}

bool xemu_xbe_boot_trace_dashboard_observed(void)
{
    return (xemu_xbe_dma_observation.present ||
            xemu_xbe_loaded_observation.loaded_marked) &&
           !xemu_xbe_loaded_observation.executed_marked;
}

static const char *xemu_xbe_browser_headless_timer_pump_mode(void)
{
    static bool initialized;
    static char mode[64] = "default";
    char file_value[64];
    const char *value = getenv("XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE");

    if (initialized) {
        return mode;
    }

    initialized = true;
    if (!value || !value[0]) {
        if (!xemu_xbe_boot_trace_read_fixture_setting(
                "browser_headless_timer_pump_mode.txt", file_value,
                sizeof(file_value))) {
            return mode;
        }
        value = file_value;
    }

    if (!value[0] ||
        !g_ascii_strcasecmp(value, "default") ||
        !g_ascii_strcasecmp(value, "current") ||
        !g_ascii_strcasecmp(value, "auto")) {
        g_strlcpy(mode, "default", sizeof(mode));
    } else if (!g_ascii_strcasecmp(value, "entry-ready") ||
               !g_ascii_strcasecmp(value, "entry") ||
               !g_ascii_strcasecmp(value, "any") ||
               !g_ascii_strcasecmp(value, "all")) {
        g_strlcpy(mode, "entry-ready", sizeof(mode));
    } else if (!g_ascii_strcasecmp(value, "after-pfifo-empty") ||
               !g_ascii_strcasecmp(value, "pfifo-empty") ||
               !g_ascii_strcasecmp(value, "after-stream-idle") ||
               !g_ascii_strcasecmp(value, "stream-idle")) {
        g_strlcpy(mode, "after-pfifo-empty", sizeof(mode));
    } else if (!g_ascii_strcasecmp(value, "pfifo-before-transition-activity") ||
               !g_ascii_strcasecmp(value, "pfifo-pre-transition-activity") ||
               !g_ascii_strcasecmp(value, "before-pfifo-transition-activity") ||
               !g_ascii_strcasecmp(value, "pre-pfifo-transition-activity")) {
        g_strlcpy(mode, "pfifo-before-transition-activity", sizeof(mode));
    } else if (!g_ascii_strcasecmp(
                   value,
                   "pfifo-before-transition-activity-then-after-pfifo-empty") ||
               !g_ascii_strcasecmp(
                   value,
                   "pfifo-pre-transition-activity-then-after-pfifo-empty") ||
               !g_ascii_strcasecmp(
                   value,
                   "pre-transition-activity-then-after-pfifo-empty") ||
               !g_ascii_strcasecmp(value,
                                   "pretransition-then-after-pfifo-empty")) {
        g_strlcpy(mode,
                  "pfifo-before-transition-activity-then-after-pfifo-empty",
                  sizeof(mode));
    } else if (!g_ascii_strcasecmp(
                   value,
                   "pcrtc-before-stream-idle-then-after-pfifo-empty") ||
               !g_ascii_strcasecmp(
                   value,
                   "pcrtc-before-pfifo-empty-then-after-pfifo-empty") ||
               !g_ascii_strcasecmp(value,
                                   "pcrtc-prestream-then-pfifo-empty") ||
               !g_ascii_strcasecmp(value,
                                   "pcrtc-prestream-then-after-pfifo-empty")) {
        g_strlcpy(mode, "pcrtc-before-stream-idle-then-after-pfifo-empty",
                  sizeof(mode));
    } else if (!g_ascii_strcasecmp(value, "pfifo-ready-edge-qemu-pump") ||
               !g_ascii_strcasecmp(value, "pfifo-ready-edge") ||
               !g_ascii_strcasecmp(value, "stream-idle-ready-edge") ||
               !g_ascii_strcasecmp(value, "pfifo-stream-idle-ready-edge") ||
               !g_ascii_strcasecmp(value, "ready-edge")) {
        g_strlcpy(mode, "pfifo-ready-edge-qemu-pump", sizeof(mode));
    } else if (!g_ascii_strcasecmp(
                   value,
                   "pcrtc-intr-clear-before-stream-idle-then-after-pfifo-empty") ||
               !g_ascii_strcasecmp(
                   value,
                   "deterministic-pcrtc-prestream-tick-window") ||
               !g_ascii_strcasecmp(value,
                                   "pcrtc-intr-clear-prestream") ||
               !g_ascii_strcasecmp(value,
                                   "pcrtc-intr-clear-prestream-then-pfifo-empty")) {
        g_strlcpy(
            mode,
            "pcrtc-intr-clear-before-stream-idle-then-after-pfifo-empty",
            sizeof(mode));
    } else if (!g_ascii_strcasecmp(value, "pfifo-ready-edge-qemu-pump-all") ||
               !g_ascii_strcasecmp(value, "pfifo-ready-edge-all") ||
               !g_ascii_strcasecmp(value, "ready-edge-all") ||
               !g_ascii_strcasecmp(value, "ready-edge-all-timers")) {
        g_strlcpy(mode, "pfifo-ready-edge-qemu-pump-all", sizeof(mode));
    } else {
        fprintf(stderr,
                "Invalid XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE='%s'; "
                "using default\n",
                value);
        g_strlcpy(mode, "default", sizeof(mode));
    }

    return mode;
}

static const char *xemu_xbe_tcg_timer_pump_mode(void)
{
    static bool initialized;
    static char mode[64] = "all";
    char file_value[64];
    const char *value = getenv("XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE");

    if (initialized) {
        return mode;
    }

    initialized = true;
    if (!value || !value[0]) {
        if (!xemu_xbe_boot_trace_read_fixture_setting(
                "xbe_tcg_timer_pump_mode.txt", file_value,
                sizeof(file_value))) {
            return mode;
        }
        value = file_value;
    }

    if (!value[0] ||
        !g_ascii_strcasecmp(value, "all") ||
        !g_ascii_strcasecmp(value, "any")) {
        g_strlcpy(mode, "all", sizeof(mode));
    } else if (!g_ascii_strcasecmp(value, "idle") ||
               !g_ascii_strcasecmp(value, "idle-loop")) {
        g_strlcpy(mode, "idle-loop", sizeof(mode));
    } else if (!g_ascii_strcasecmp(value, "idle-loop-serviceable") ||
               !g_ascii_strcasecmp(value, "idle-serviceable") ||
               !g_ascii_strcasecmp(value, "serviceable")) {
        g_strlcpy(mode, "idle-loop-serviceable", sizeof(mode));
    } else if (!g_ascii_strcasecmp(value, "idle-loop-serviceable-pit-only") ||
               !g_ascii_strcasecmp(value, "idle-serviceable-pit-only") ||
               !g_ascii_strcasecmp(value, "serviceable-pit-only") ||
               !g_ascii_strcasecmp(value, "pit-only")) {
        g_strlcpy(mode, "idle-loop-serviceable-pit-only", sizeof(mode));
    } else if (!g_ascii_strcasecmp(value,
                                  "idle-loop-serviceable-pit-after-idle") ||
               !g_ascii_strcasecmp(value,
                                   "idle-serviceable-pit-after-idle") ||
               !g_ascii_strcasecmp(value, "serviceable-pit-after-idle") ||
               !g_ascii_strcasecmp(value, "pit-after-idle")) {
        g_strlcpy(mode, "idle-loop-serviceable-pit-after-idle",
                  sizeof(mode));
    } else if (!g_ascii_strcasecmp(value,
                                  "idle-loop-serviceable-pit-after-idle-full") ||
               !g_ascii_strcasecmp(value,
                                   "idle-serviceable-pit-after-idle-full") ||
               !g_ascii_strcasecmp(value, "serviceable-pit-after-idle-full") ||
               !g_ascii_strcasecmp(value, "pit-after-idle-full")) {
        g_strlcpy(mode, "idle-loop-serviceable-pit-after-idle-full",
                  sizeof(mode));
    } else if (!g_ascii_strcasecmp(value,
                                  "idle-loop-serviceable-pit-after-pfifo-transition") ||
               !g_ascii_strcasecmp(value,
                                   "serviceable-pit-after-pfifo-transition") ||
               !g_ascii_strcasecmp(value, "pit-after-pfifo-transition") ||
               !g_ascii_strcasecmp(value, "pfifo-transition") ||
               !g_ascii_strcasecmp(value, "pfifo-transition-pit-only")) {
        g_strlcpy(mode, "pit-after-pfifo-transition", sizeof(mode));
    } else if (!g_ascii_strcasecmp(value, "pit-post-pfifo-pre-first-read") ||
               !g_ascii_strcasecmp(value, "pit-after-pfifo-pre-first-read") ||
               !g_ascii_strcasecmp(value, "post-pfifo-pre-first-read") ||
               !g_ascii_strcasecmp(value, "pre-first-read")) {
        g_strlcpy(mode, "pit-post-pfifo-pre-first-read", sizeof(mode));
    } else if (!g_ascii_strcasecmp(value,
                                  "pit-pre-first-read-micro-scheduler") ||
               !g_ascii_strcasecmp(value,
                                  "pre-first-read-micro-scheduler") ||
               !g_ascii_strcasecmp(value, "micro-pre-first-read") ||
               !g_ascii_strcasecmp(value, "pre-first-read-owner")) {
        g_strlcpy(mode, "pit-pre-first-read-micro-scheduler", sizeof(mode));
    } else if (!g_ascii_strcasecmp(value,
                                  "idle-loop-inhibited-pit-before-pfifo-transition") ||
               !g_ascii_strcasecmp(value,
                                   "serviceable-pit-before-pfifo-transition") ||
               !g_ascii_strcasecmp(value, "pit-before-pfifo-transition") ||
               !g_ascii_strcasecmp(value, "before-pfifo-transition") ||
               !g_ascii_strcasecmp(value, "pfifo-before-transition") ||
               !g_ascii_strcasecmp(value, "pre-pfifo-transition")) {
        g_strlcpy(mode, "pit-before-pfifo-transition", sizeof(mode));
    } else if (!g_ascii_strcasecmp(value,
                                  "pit-before-pfifo-transition-activity") ||
               !g_ascii_strcasecmp(value,
                                   "pfifo-activity-before-transition") ||
               !g_ascii_strcasecmp(value,
                                   "before-pfifo-transition-activity") ||
               !g_ascii_strcasecmp(value,
                                   "pre-pfifo-transition-activity")) {
        g_strlcpy(mode, "pit-before-pfifo-transition-activity", sizeof(mode));
    } else if (!g_ascii_strcasecmp(value,
                                  "pit-before-pfifo-transition-activity-defer") ||
               !g_ascii_strcasecmp(value,
                                   "pfifo-activity-before-transition-defer") ||
               !g_ascii_strcasecmp(value,
                                   "before-pfifo-transition-activity-defer") ||
               !g_ascii_strcasecmp(value,
                                   "pre-pfifo-transition-activity-defer")) {
        g_strlcpy(mode, "pit-before-pfifo-transition-activity-defer",
                  sizeof(mode));
    } else if (!g_ascii_strcasecmp(
                   value,
                   "pit-before-pfifo-transition-activity-pre-tb-defer") ||
               !g_ascii_strcasecmp(
                   value,
                   "pfifo-activity-before-transition-pre-tb-defer") ||
               !g_ascii_strcasecmp(
                   value,
                   "before-pfifo-transition-activity-pre-tb-defer") ||
               !g_ascii_strcasecmp(
                   value,
                   "pre-pfifo-transition-activity-pre-tb-defer")) {
        g_strlcpy(mode, "pit-before-pfifo-transition-activity-pre-tb-defer",
                  sizeof(mode));
    } else if (!g_ascii_strcasecmp(
                   value,
                   "pit-before-pfifo-transition-activity-defer-to-idle") ||
               !g_ascii_strcasecmp(
                   value,
                   "pfifo-activity-before-transition-defer-to-idle") ||
               !g_ascii_strcasecmp(
                   value,
                   "before-pfifo-transition-activity-defer-to-idle") ||
               !g_ascii_strcasecmp(
                   value,
                   "pre-pfifo-transition-activity-defer-to-idle")) {
        g_strlcpy(mode, "pit-before-pfifo-transition-activity-defer-to-idle",
                  sizeof(mode));
    } else if (!g_ascii_strcasecmp(
                   value,
                   "pit-at-pfifo-transition-pre-commit-defer-to-idle") ||
               !g_ascii_strcasecmp(
                   value,
                   "pfifo-transition-pre-commit-pit-defer-to-idle") ||
               !g_ascii_strcasecmp(
                   value,
                   "pfifo-pre-commit-pit-defer-to-idle") ||
               !g_ascii_strcasecmp(
                   value,
                   "pre-commit-pfifo-transition-pit-defer-to-idle")) {
        g_strlcpy(mode, "pit-at-pfifo-transition-pre-commit-defer-to-idle",
                  sizeof(mode));
    } else {
        fprintf(stderr,
                "Invalid XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE='%s'; "
                "using all\n",
                value);
        g_strlcpy(mode, "all", sizeof(mode));
    }

    return mode;
}

static bool xemu_xbe_tcg_timer_pump_mode_is_pfifo_pre_commit(
    const char *mode)
{
    return !g_ascii_strcasecmp(
        mode, "pit-at-pfifo-transition-pre-commit-defer-to-idle");
}

static bool xemu_xbe_tcg_timer_pump_mode_is_pre_first_read_scheduler(
    const char *mode)
{
    return !g_ascii_strcasecmp(mode,
                               "pit-pre-first-read-micro-scheduler");
}

static bool xemu_xbe_pfifo_stream_idle_transition_observed(void)
{
    return qatomic_read(&xemu_xbe_pfifo_stream_idle_transition_seen);
}

bool xemu_xbe_boot_trace_pfifo_stream_idle_transition_observed(void)
{
    return xemu_xbe_pfifo_stream_idle_transition_observed();
}

static bool xemu_xbe_tcg_timer_pump_idle_loop_ready(void)
{
    struct xemu_xbe_exec_context exec_ctx;
    uint64_t pc;

    xemu_xbe_capture_exec_context(&exec_ctx);
    if (!exec_ctx.cpu_known ||
        strcmp(exec_ctx.mode, "protected32") ||
        exec_ctx.cpl != 0 ||
        !(exec_ctx.computed_eflags & IF_MASK)) {
        return false;
    }

    pc = exec_ctx.eip & UINT64_C(0xffffffff);

    /*
     * Browser-only diagnostic mode for the current dashboard B6 trace. These
     * PCs are the native kernel idle-loop locations where timer IRQ delivery
     * was observed, avoiding timer injection inside the IRQ handler path.
     */
    return pc == XEMU_XBE_TCG_TIMER_PUMP_IDLE_LOOP_PC_1 ||
           pc == XEMU_XBE_TCG_TIMER_PUMP_IDLE_LOOP_PC_2;
}

static bool xemu_xbe_exec_context_is_idle_loop_serviceable(
    const struct xemu_xbe_exec_context *exec_ctx,
    bool require_no_pending_interrupt)
{
    uint64_t pc;

    if (!exec_ctx ||
        !exec_ctx->cpu_known ||
        strcmp(exec_ctx->mode, "protected32") ||
        exec_ctx->cpl != 0 ||
        !(exec_ctx->computed_eflags & IF_MASK) ||
        (exec_ctx->hflags & HF_INHIBIT_IRQ_MASK) ||
        (require_no_pending_interrupt &&
         exec_ctx->cpu_interrupt_request != 0)) {
        return false;
    }

    pc = exec_ctx->eip & UINT64_C(0xffffffff);

    /*
     * Stricter browser-only diagnostic for the post-idle B6 boundary: pump
     * timers only when the native idle loop is at an IRQ-serviceable PC.
     */
    return pc == XEMU_XBE_TCG_TIMER_PUMP_IDLE_LOOP_PC_2;
}

static bool xemu_xbe_tcg_timer_pump_idle_loop_serviceable_ready(void)
{
    struct xemu_xbe_exec_context exec_ctx;

    xemu_xbe_capture_exec_context(&exec_ctx);
    return xemu_xbe_exec_context_is_idle_loop_serviceable(&exec_ctx, true);
}

static bool xemu_xbe_exec_context_is_post_pfifo_pre_first_read_serviceable(
    const struct xemu_xbe_exec_context *exec_ctx)
{
    uint64_t pc;

    if (!exec_ctx ||
        !exec_ctx->cpu_known ||
        strcmp(exec_ctx->mode, "protected32") ||
        exec_ctx->cpl != 0 ||
        !(exec_ctx->computed_eflags & IF_MASK) ||
        (exec_ctx->hflags & HF_INHIBIT_IRQ_MASK) ||
        exec_ctx->cpu_interrupt_request != 0) {
        return false;
    }

    pc = exec_ctx->eip & UINT64_C(0xffffffff);

    return pc == XEMU_XBE_TCG_TIMER_PUMP_IDLE_LOOP_PC_2 ||
           pc == XEMU_XBE_TICK_BLOCK_PC;
}

static bool xemu_xbe_pre_first_read_scheduler_pc_is_candidate(uint64_t pc)
{
    return pc == XEMU_XBE_TCG_TIMER_PUMP_IDLE_LOOP_PC_2 ||
           pc == XEMU_XBE_FIRST_READ_PREDECESSOR_PC_BROWSER ||
           pc == XEMU_XBE_FIRST_READ_PREDECESSOR_PC_NATIVE;
}

static bool xemu_xbe_exec_context_is_pre_first_read_scheduler_serviceable(
    const struct xemu_xbe_exec_context *exec_ctx)
{
    uint64_t pc;

    if (!exec_ctx ||
        !exec_ctx->cpu_known ||
        strcmp(exec_ctx->mode, "protected32") ||
        exec_ctx->cpl != 0 ||
        !(exec_ctx->computed_eflags & IF_MASK) ||
        exec_ctx->cpu_interrupt_request != 0) {
        return false;
    }

    pc = exec_ctx->eip & UINT64_C(0xffffffff);

    /*
     * This opt-in owner runs before cpu_handle_interrupt() so the observed
     * first-read predecessor can still be interrupted before it reaches
     * 0x80030e84 and consumes the shared word at zero ticks.
     *
     * The browser predecessor is the instruction immediately after STI. x86
     * rules inhibit delivery for that one instruction, but pumping here can
     * make the IRQ pending for delivery after the RET and before the watched
     * read at 0x80030e84.
     */
    if (pc == XEMU_XBE_FIRST_READ_PREDECESSOR_PC_BROWSER &&
        (exec_ctx->hflags & HF_INHIBIT_IRQ_MASK)) {
        return true;
    }
    if (exec_ctx->hflags & HF_INHIBIT_IRQ_MASK) {
        return false;
    }

    return xemu_xbe_pre_first_read_scheduler_pc_is_candidate(pc);
}

static const char *xemu_xbe_pre_first_read_scheduler_edge_state(void)
{
    const struct xemu_xbe_exec_transition_snapshot *transition =
        &xemu_xbe_latest_exec_transition;

    if (!transition->valid) {
        return "none";
    }
    if (!transition->next_pc_known) {
        return "next-unknown";
    }
    if (transition->start_pc == XEMU_XBE_TICK_BLOCK_PC &&
        transition->next_pc == XEMU_XBE_TICK_BLOCK_NEXT_PC) {
        return "tick-block-useful-edge";
    }
    if (transition->start_pc == XEMU_XBE_TICK_BLOCK_PC) {
        return "tick-block-edge-regressed";
    }

    return "other-edge";
}

static bool xemu_xbe_pre_first_read_scheduler_edge_regressed(void)
{
    const struct xemu_xbe_exec_transition_snapshot *transition =
        &xemu_xbe_latest_exec_transition;

    return transition->valid &&
           transition->next_pc_known &&
           transition->start_pc == XEMU_XBE_TICK_BLOCK_PC &&
           transition->next_pc != XEMU_XBE_TICK_BLOCK_NEXT_PC;
}

static void xemu_xbe_pre_first_read_scheduler_emit(const char *phase,
                                                   const char *owner,
                                                   const char *stop_reason,
                                                   uint64_t guest_pc,
                                                   uint32_t tb_size,
                                                   int tb_exit)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    struct xemu_xbe_pre_first_read_scheduler_state *state =
        &xemu_xbe_pre_first_read_scheduler;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    const struct xemu_xbe_exec_transition_snapshot *transition =
        &xemu_xbe_latest_exec_transition;
    int64_t limit = xemu_xbe_tcg_timer_pump_probe_limit();
    int64_t tb_budget = xemu_xbe_pre_first_read_scheduler_tb_budget();
    uint32_t watch_value = 0;
    uint64_t watch_ticks = 0;
    bool watch_value_read;
    uint64_t seq;

    if (!xemu_xbe_boot_trace_enabled() ||
        limit == 0 ||
        obs->pre_first_read_scheduler_probe_count >= (uint64_t)limit) {
        return;
    }

    xemu_xbe_capture_exec_context(&exec_ctx);
    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    wait_state.state.source = wait_state.source;
    wait_state.state.op = wait_state.op;

#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
    xemu_xbe_memory_watch_suppress = true;
    watch_value_read =
        xemu_xbe_read_phys_u32(XEMU_XBE_TICK_BLOCK_WATCH_PHYS, &watch_value);
    xemu_xbe_memory_watch_suppress = false;
#endif
    if (watch_value_read) {
        watch_ticks = watch_value / XEMU_XBE_TICK_BLOCK_TICK_UNIT;
    }

    seq = ++obs->pre_first_read_scheduler_probe_count;
    state->seq = seq;
    fprintf(stderr,
            "BOOT_MARK b6 scheduler=pre-first-read context=%s"
            " seq=%" PRIu64
            " phase=%s"
            " owner=%s"
            " mode=%s"
            " stop_reason=%s"
            " active=%s"
            " done=%s"
            " tb_count=%" PRIu64
            " tb_budget=%" PRId64
            " timer_pumps=%" PRIu64
            " timer_deliveries=%" PRIu64
            " tick_block_completions=%" PRIu64
            " start_tick_block_completions=%" PRIu64
            " tick_block_delta=%" PRIu64
            " first_read_seen=%s"
            " first_read_before_tick_block=%s"
            " edge_decision_count=%" PRIu64
            " start_edge_decision_count=%" PRIu64
            " edge_decision_delta=%" PRIu64
            " edge_state=%s"
            " watch_phys=0x%08" PRIx64
            " watch_tick_unit=0x%08" PRIx32
            " watch_value_read=%s"
            " watch_value=0x%08" PRIx32
            " watch_ticks=%" PRIu64
            " guest_pc=0x%08" PRIx64
            " tb_size=%" PRIu32
            " tb_exit=%d"
            " latest_transition_valid=%s"
            " latest_start_pc=0x%08" PRIx64
            " latest_next_pc_known=%s"
            " latest_next_pc=0x%08" PRIx64
            " latest_tb_exit=%d"
            " cpu_known=%s"
            " cpu_mode=%s"
            " cpl=%" PRIu32
            " eip=0x%08" PRIx64
            " eflags=0x%08" PRIx64
            " interrupts_enabled=%s"
            " irq_inhibited=%s"
            " cpu_interrupt_request=0x%08" PRIx32
            " pending_interrupt=%s"
            " cpu_exit_request=%s"
            " wait_present=%s"
            " stream_idle=%s"
            " wait_generation=%" PRIu64
            " wait_source=%s"
            " wait_op=%s"
            " wait_seq=%" PRIu64 "\n",
            xemu_xbe_boot_trace_context(), seq,
            phase ? phase : "checkpoint",
            owner ? owner : "unknown",
            xemu_xbe_tcg_timer_pump_mode(),
            stop_reason ? stop_reason : "none",
            xemu_xbe_bool_str(state->active),
            xemu_xbe_bool_str(state->done),
            state->tb_count, tb_budget,
            state->timer_pump_count,
            state->timer_delivery_count,
            obs->exec_tick_block_probe_count,
            state->start_tick_block_count,
            obs->exec_tick_block_probe_count -
                state->start_tick_block_count,
            xemu_xbe_bool_str(state->first_read_seen),
            xemu_xbe_bool_str(state->first_read_before_tick_block),
            obs->exec_edge_decision_probe_count,
            state->start_edge_decision_count,
            obs->exec_edge_decision_probe_count -
                state->start_edge_decision_count,
            xemu_xbe_pre_first_read_scheduler_edge_state(),
            XEMU_XBE_TICK_BLOCK_WATCH_PHYS,
            XEMU_XBE_TICK_BLOCK_TICK_UNIT,
            xemu_xbe_bool_str(watch_value_read),
            watch_value, watch_ticks,
            guest_pc, tb_size, tb_exit,
            xemu_xbe_bool_str(transition->valid),
            transition->valid ? transition->start_pc : 0,
            xemu_xbe_bool_str(transition->valid &&
                              transition->next_pc_known),
            transition->valid && transition->next_pc_known ?
                transition->next_pc : 0,
            transition->valid ? transition->tb_exit : 0,
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(wait_state.present),
            xemu_xbe_bool_str(xemu_xbe_nv2a_wait_is_stream_idle(&wait_state)),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0);
}

static void xemu_xbe_pre_first_read_scheduler_finish(const char *phase,
                                                     const char *owner,
                                                     const char *stop_reason,
                                                     uint64_t guest_pc,
                                                     uint32_t tb_size,
                                                     int tb_exit)
{
    struct xemu_xbe_pre_first_read_scheduler_state *state =
        &xemu_xbe_pre_first_read_scheduler;

    if (!state->active || state->done) {
        return;
    }

    state->done = true;
    xemu_xbe_pre_first_read_scheduler_emit(phase, owner, stop_reason, guest_pc,
                                           tb_size, tb_exit);
    state->active = false;
}

static const char *xemu_xbe_pre_first_read_scheduler_stop_reason(void)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    struct xemu_xbe_pre_first_read_scheduler_state *state =
        &xemu_xbe_pre_first_read_scheduler;
    int64_t tb_budget = xemu_xbe_pre_first_read_scheduler_tb_budget();

    if (!state->active || state->done) {
        return NULL;
    }
    if (obs->executed_marked) {
        return "dashboard-executed";
    }
    if (state->first_read_before_tick_block) {
        return "first-read-before-tick-block";
    }
    if (obs->exec_tick_block_probe_count > state->start_tick_block_count &&
        !state->first_read_seen) {
        return "tick-block-before-first-read";
    }
    if (obs->exec_edge_decision_probe_count >
            state->start_edge_decision_count &&
        obs->exec_tick_block_probe_count <= state->start_tick_block_count) {
        return "first-read-before-tick-block";
    }
    if (xemu_xbe_pre_first_read_scheduler_edge_regressed()) {
        return "edge-regressed";
    }
    if (tb_budget >= 0 && state->tb_count >= (uint64_t)tb_budget) {
        return "tb-budget";
    }

    return NULL;
}

static void xemu_xbe_pre_first_read_scheduler_maybe_stop(
    const char *phase,
    const char *owner,
    uint64_t guest_pc,
    uint32_t tb_size,
    int tb_exit)
{
    const char *reason = xemu_xbe_pre_first_read_scheduler_stop_reason();

    if (reason) {
        xemu_xbe_pre_first_read_scheduler_finish(
            phase, owner, reason, guest_pc, tb_size, tb_exit);
    }
}

static bool xemu_xbe_pre_first_read_scheduler_gate_should_emit(
    bool mode_match,
    bool trace_enabled,
    bool entry_ready,
    bool loaded,
    const struct xemu_xbe_exec_context *exec_ctx)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    int64_t limit = xemu_xbe_tcg_timer_pump_gate_probe_limit();
    uint64_t pc = exec_ctx && exec_ctx->cpu_known ?
        (exec_ctx->eip & UINT64_C(0xffffffff)) : 0;

    if (!mode_match || !trace_enabled || limit == 0) {
        return false;
    }
    if (obs->pre_first_read_scheduler_gate_probe_count >= (uint64_t)limit) {
        return false;
    }
    (void)loaded;

    /*
     * Avoid spending the bounded gate budget during early boot. The current
     * question starts only after the dashboard entry code is known readable.
     */
    if (!entry_ready) {
        return false;
    }

    return xemu_xbe_pfifo_stream_idle_transition_observed() ||
           xemu_xbe_pre_first_read_scheduler_pc_is_candidate(pc);
}

static void xemu_xbe_pre_first_read_scheduler_gate_emit(
    const char *reason,
    bool ready,
    bool mode_match,
    bool trace_enabled,
    bool entry_ready,
    bool loaded,
    int64_t interval,
    int64_t tb_budget,
    int64_t pump_limit,
    bool pump_limit_exhausted,
    bool virtual_has_timers,
    bool virtual_expired,
    int64_t virtual_now,
    int64_t virtual_deadline,
    bool serviceable,
    const struct xemu_xbe_exec_context *exec_ctx)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    struct xemu_xbe_pre_first_read_scheduler_state *state =
        &xemu_xbe_pre_first_read_scheduler;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    uint64_t pc = exec_ctx && exec_ctx->cpu_known ?
        (exec_ctx->eip & UINT64_C(0xffffffff)) : 0;
    uint32_t watch_value = 0;
    uint64_t watch_ticks = 0;
    bool watch_value_read = false;
    uint64_t seq;

    if (!xemu_xbe_pre_first_read_scheduler_gate_should_emit(
            mode_match, trace_enabled, entry_ready, loaded, exec_ctx)) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    wait_state.state.source = wait_state.source;
    wait_state.state.op = wait_state.op;

#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
    xemu_xbe_memory_watch_suppress = true;
    watch_value_read =
        xemu_xbe_read_phys_u32(XEMU_XBE_TICK_BLOCK_WATCH_PHYS, &watch_value);
    xemu_xbe_memory_watch_suppress = false;
#endif
    if (watch_value_read) {
        watch_ticks = watch_value / XEMU_XBE_TICK_BLOCK_TICK_UNIT;
    }

    seq = ++obs->pre_first_read_scheduler_gate_probe_count;
    fprintf(stderr,
            "BOOT_MARK b6 scheduler=pre-first-read-gate context=%s"
            " seq=%" PRIu64
            " reason=%s"
            " ready=%s"
            " mode_match=%s"
            " trace_enabled=%s"
            " entry_ready=%s"
            " loaded=%s"
            " interval_tbs=%" PRId64
            " tb_budget=%" PRId64
            " pump_limit=%" PRId64
            " pump_limit_exhausted=%s"
            " scheduler_active=%s"
            " scheduler_done=%s"
            " scheduler_timer_pumps=%" PRIu64
            " edge_decision_count=%" PRIu64
            " edge_decision_seen=%s"
            " tick_block_count=%" PRIu64
            " virtual_now=%" PRId64
            " virtual_deadline=%" PRId64
            " virtual_has_timers=%s"
            " virtual_expired=%s"
            " serviceable=%s"
            " cpu_known=%s"
            " cpu_mode=%s"
            " cpl=%" PRIu32
            " eip=0x%08" PRIx64
            " pc_candidate=%s"
            " pc_idle=%s"
            " pc_browser_first_read_predecessor=%s"
            " pc_native_first_read_predecessor=%s"
            " eflags=0x%08" PRIx64
            " interrupts_enabled=%s"
            " irq_inhibited=%s"
            " cpu_interrupt_request=0x%08" PRIx32
            " pending_interrupt=%s"
            " cpu_exit_request=%s"
            " watch_phys=0x%08" PRIx64
            " watch_tick_unit=0x%08" PRIx32
            " watch_value_read=%s"
            " watch_value=0x%08" PRIx32
            " watch_ticks=%" PRIu64
            " wait_present=%s"
            " stream_idle_transition_seen=%s"
            " stream_idle=%s"
            " wait_generation=%" PRIu64
            " wait_source=%s"
            " wait_op=%s"
            " wait_seq=%" PRIu64 "\n",
            xemu_xbe_boot_trace_context(), seq,
            reason ? reason : "unknown",
            xemu_xbe_bool_str(ready),
            xemu_xbe_bool_str(mode_match),
            xemu_xbe_bool_str(trace_enabled),
            xemu_xbe_bool_str(entry_ready),
            xemu_xbe_bool_str(loaded),
            interval, tb_budget, pump_limit,
            xemu_xbe_bool_str(pump_limit_exhausted),
            xemu_xbe_bool_str(state->active),
            xemu_xbe_bool_str(state->done),
            state->timer_pump_count,
            obs->exec_edge_decision_probe_count,
            xemu_xbe_bool_str(obs->exec_edge_decision_probe_count > 0),
            obs->exec_tick_block_probe_count,
            virtual_now, virtual_deadline,
            xemu_xbe_bool_str(virtual_has_timers),
            xemu_xbe_bool_str(virtual_expired),
            xemu_xbe_bool_str(serviceable),
            xemu_xbe_bool_str(exec_ctx && exec_ctx->cpu_known),
            exec_ctx ? exec_ctx->mode : "unknown",
            exec_ctx ? exec_ctx->cpl : 0,
            exec_ctx && exec_ctx->cpu_known ? exec_ctx->eip : 0,
            xemu_xbe_bool_str(
                xemu_xbe_pre_first_read_scheduler_pc_is_candidate(pc)),
            xemu_xbe_bool_str(pc == XEMU_XBE_TCG_TIMER_PUMP_IDLE_LOOP_PC_2),
            xemu_xbe_bool_str(pc ==
                              XEMU_XBE_FIRST_READ_PREDECESSOR_PC_BROWSER),
            xemu_xbe_bool_str(pc ==
                              XEMU_XBE_FIRST_READ_PREDECESSOR_PC_NATIVE),
            exec_ctx ? exec_ctx->computed_eflags : 0,
            xemu_xbe_bool_str(exec_ctx &&
                              (exec_ctx->computed_eflags & IF_MASK)),
            xemu_xbe_bool_str(exec_ctx &&
                              (exec_ctx->hflags & HF_INHIBIT_IRQ_MASK)),
            exec_ctx ? exec_ctx->cpu_interrupt_request : 0,
            xemu_xbe_bool_str(exec_ctx &&
                              exec_ctx->cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx && exec_ctx->cpu_exit_request),
            XEMU_XBE_TICK_BLOCK_WATCH_PHYS,
            XEMU_XBE_TICK_BLOCK_TICK_UNIT,
            xemu_xbe_bool_str(watch_value_read),
            watch_value, watch_ticks,
            xemu_xbe_bool_str(wait_state.present),
            xemu_xbe_bool_str(xemu_xbe_pfifo_stream_idle_transition_observed()),
            xemu_xbe_bool_str(xemu_xbe_nv2a_wait_is_stream_idle(&wait_state)),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0);
}

static bool xemu_xbe_tcg_timer_pump_pre_first_read_scheduler_site_ready(
    bool emit_gate)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    struct xemu_xbe_pre_first_read_scheduler_state *state =
        &xemu_xbe_pre_first_read_scheduler;
    struct xemu_xbe_exec_context exec_ctx;
    int64_t interval = xemu_xbe_boot_trace_tcg_timer_pump_interval();
    bool mode_match = xemu_xbe_tcg_timer_pump_mode_is_pre_first_read_scheduler(
        xemu_xbe_tcg_timer_pump_mode());
    bool trace_enabled = xemu_xbe_boot_trace_enabled();
    bool entry_ready = xemu_xbe_boot_trace_entry_ready();
    bool loaded = xemu_xbe_boot_trace_loaded();
    int64_t tb_budget;
    int64_t pump_limit;
    int64_t virtual_now;
    int64_t virtual_deadline;
    bool pump_limit_exhausted;
    bool virtual_has_timers;
    bool virtual_expired;
    bool serviceable;
    const char *reason = "ready";
    bool ready = false;

    if (!mode_match || !trace_enabled || !entry_ready || interval <= 0) {
        return false;
    }

    tb_budget = xemu_xbe_pre_first_read_scheduler_tb_budget();
    pump_limit = xemu_xbe_tcg_timer_pump_after_idle_probe_limit();
    virtual_now = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL);
    virtual_deadline =
        qemu_clock_deadline_ns_all(QEMU_CLOCK_VIRTUAL, QEMU_TIMER_ATTR_ALL);
    pump_limit_exhausted =
        pump_limit > 0 && state->timer_pump_count >= (uint64_t)pump_limit;
    virtual_has_timers = qemu_clock_has_timers(QEMU_CLOCK_VIRTUAL);
    virtual_expired = qemu_clock_expired(QEMU_CLOCK_VIRTUAL);

    xemu_xbe_capture_exec_context(&exec_ctx);
    serviceable = xemu_xbe_exec_context_is_pre_first_read_scheduler_serviceable(
        &exec_ctx);

    if (tb_budget == 0) {
        reason = "tb-budget-zero";
    } else if (pump_limit <= 0) {
        reason = "pump-limit-disabled";
    } else if (pump_limit_exhausted) {
        reason = "pump-limit-exhausted";
    } else if (!loaded) {
        reason = "not-loaded";
    } else if (state->done) {
        reason = "scheduler-done";
    } else if (obs->exec_edge_decision_probe_count > 0) {
        reason = "edge-decision-already-seen";
    } else if (!virtual_has_timers) {
        reason = "no-virtual-timers";
    } else if (!virtual_expired) {
        reason = "no-expired-virtual-timer";
    } else if (!serviceable) {
        reason = "cpu-not-serviceable";
    } else {
        ready = true;
    }

    if (emit_gate) {
        xemu_xbe_pre_first_read_scheduler_gate_emit(
            reason, ready, mode_match, trace_enabled, entry_ready, loaded,
            interval, tb_budget, pump_limit, pump_limit_exhausted,
            virtual_has_timers, virtual_expired, virtual_now,
            virtual_deadline, serviceable, &exec_ctx);
    }

    return ready;
}

static bool xemu_xbe_tcg_timer_pump_pre_first_read_scheduler_ready(void)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    struct xemu_xbe_pre_first_read_scheduler_state *state =
        &xemu_xbe_pre_first_read_scheduler;
    struct xemu_xbe_exec_context exec_ctx;

    if (!xemu_xbe_tcg_timer_pump_pre_first_read_scheduler_site_ready(false)) {
        return false;
    }

    xemu_xbe_capture_exec_context(&exec_ctx);
    if (!state->active) {
        memset(state, 0, sizeof(*state));
        state->active = true;
        state->start_tick_block_count = obs->exec_tick_block_probe_count;
        state->start_edge_decision_count =
            obs->exec_edge_decision_probe_count;
        state->start_skip_count = obs->exec_edge_decision_skip_count;
        xemu_xbe_pre_first_read_scheduler_emit(
            "start", "tcg-pre-interrupt", NULL, exec_ctx.eip, 0, 0);
    }

    return true;
}

static void xemu_xbe_pre_first_read_scheduler_note_timer_pump(bool progress)
{
    struct xemu_xbe_pre_first_read_scheduler_state *state =
        &xemu_xbe_pre_first_read_scheduler;

    if (!state->active || state->done) {
        return;
    }

    state->timer_pump_count++;
    if (progress) {
        state->timer_delivery_count++;
    }
    xemu_xbe_pre_first_read_scheduler_emit(
        "timer-pump", "tcg-pre-interrupt", NULL, 0, 0, 0);
    xemu_xbe_pre_first_read_scheduler_maybe_stop(
        "timer-pump-stop", "tcg-pre-interrupt", 0, 0, 0);
}

static void xemu_xbe_pre_first_read_scheduler_note_first_read(
    uint64_t guest_pc,
    uint32_t tb_size,
    const char *source)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    struct xemu_xbe_pre_first_read_scheduler_state *state =
        &xemu_xbe_pre_first_read_scheduler;

    if (!state->active || state->done) {
        return;
    }

    state->first_read_seen = true;
    if (obs->exec_tick_block_probe_count <= state->start_tick_block_count) {
        state->first_read_before_tick_block = true;
    }
    xemu_xbe_pre_first_read_scheduler_finish(
        "first-read", source ? source : "edge-decision-pre",
        state->first_read_before_tick_block ?
            "first-read-before-tick-block" : "first-read-after-tick-block",
        guest_pc, tb_size, 0);
}

static void xemu_xbe_pre_first_read_scheduler_note_tick_block(
    uint64_t guest_pc,
    uint32_t tb_size,
    int tb_exit,
    const char *source)
{
    struct xemu_xbe_pre_first_read_scheduler_state *state =
        &xemu_xbe_pre_first_read_scheduler;

    if (!state->active || state->done) {
        return;
    }

    xemu_xbe_pre_first_read_scheduler_maybe_stop(
        "tick-block", source ? source : "tick-block-post", guest_pc,
        tb_size, tb_exit);
}

void xemu_xbe_boot_trace_pre_first_read_scheduler_after_tb(uint64_t guest_pc,
                                                           uint32_t tb_size,
                                                           int tb_exit,
                                                           const char *source)
{
    struct xemu_xbe_pre_first_read_scheduler_state *state =
        &xemu_xbe_pre_first_read_scheduler;

    if (!state->active || state->done) {
        return;
    }

    state->tb_count++;
    xemu_xbe_pre_first_read_scheduler_maybe_stop(
        "after-tb", source ? source : "tcg-after-tb", guest_pc, tb_size,
        tb_exit);
}

static bool xemu_xbe_tcg_timer_pump_idle_loop_serviceable_after_idle_ready(void)
{
    /*
     * Browser-only B6 diagnostic: native observes the stream-idle kernel loop
     * edge pair before the first PIT service. Require one full post-idle
     * 0x8001b030 <-> 0x8001b02f cycle before allowing the synthetic PIT pump.
     */
    if (xemu_xbe_loaded_observation.exec_kernel_loop_after_idle_probe_count < 2) {
        return false;
    }

    return xemu_xbe_tcg_timer_pump_idle_loop_serviceable_ready();
}

static bool xemu_xbe_tcg_timer_pump_idle_loop_serviceable_after_idle_full_ready(void)
{
    int64_t limit = xemu_xbe_tcg_timer_pump_after_idle_probe_limit();

    if (limit <= 0 ||
        xemu_xbe_loaded_observation.exec_kernel_loop_after_idle_probe_count <
            (uint64_t)limit) {
        return false;
    }

    return xemu_xbe_tcg_timer_pump_idle_loop_serviceable_ready();
}

static bool xemu_xbe_tcg_timer_pump_idle_loop_serviceable_after_pfifo_transition_ready(void)
{
    if (!xemu_xbe_pfifo_stream_idle_transition_observed()) {
        return false;
    }

    return xemu_xbe_tcg_timer_pump_idle_loop_serviceable_ready();
}

static bool xemu_xbe_tcg_timer_pump_post_pfifo_pre_first_read_ready(void)
{
    static uint64_t delivery_attempts;
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    int64_t limit = xemu_xbe_tcg_timer_pump_after_idle_probe_limit();

    if (limit <= 0 || delivery_attempts >= (uint64_t)limit ||
        !xemu_xbe_pfifo_stream_idle_transition_observed() ||
        obs->exec_tick_block_probe_count > 0 ||
        obs->exec_edge_decision_probe_count > 0) {
        return false;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (!xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(&wait_state)) {
        return false;
    }

    xemu_xbe_capture_exec_context(&exec_ctx);
    if (!xemu_xbe_exec_context_is_post_pfifo_pre_first_read_serviceable(
            &exec_ctx)) {
        return false;
    }

    if (!qemu_clock_has_timers(QEMU_CLOCK_VIRTUAL) ||
        !qemu_clock_expired(QEMU_CLOCK_VIRTUAL)) {
        return false;
    }

    delivery_attempts++;
    return true;
}

static bool xemu_xbe_pc_is_tcg_timer_pump_before_pfifo_candidate(uint64_t pc)
{
    pc &= UINT64_C(0xffffffff);

    return pc == XEMU_XBE_TCG_TIMER_PUMP_IDLE_LOOP_PC_1 ||
           pc == XEMU_XBE_TCG_TIMER_PUMP_IDLE_LOOP_PC_2 ||
           pc == UINT64_C(0x8001b043);
}

static bool xemu_xbe_pfifo_activity_dma_to_put(
    const struct xemu_xbe_pfifo_activity_snapshot *activity,
    uint32_t *dma_to_put)
{
    if (!activity ||
        !activity->present ||
        activity->state.dma_get_reg > activity->state.dma_put) {
        return false;
    }

    *dma_to_put = activity->state.dma_put - activity->state.dma_get_reg;
    return true;
}

static bool xemu_xbe_wait_state_dma_to_put(
    const struct xemu_xbe_nv2a_wait_snapshot *wait_state,
    uint32_t *dma_to_put)
{
    if (!wait_state ||
        !wait_state->present ||
        !wait_state->state.pfifo_known ||
        wait_state->state.dma_get > wait_state->state.dma_put) {
        return false;
    }

    *dma_to_put = wait_state->state.dma_put - wait_state->state.dma_get;
    return true;
}

static const char *xemu_xbe_tcg_timer_pump_before_pfifo_gate_reason(
    struct xemu_xbe_exec_context *exec_ctx,
    struct xemu_xbe_pfifo_activity_snapshot *activity,
    uint32_t *activity_dma_to_put,
    bool activity_gate)
{
    uint64_t pc;
    bool pc_candidate;

    *activity_dma_to_put = 0;
    xemu_xbe_capture_exec_context(exec_ctx);
    xemu_xbe_boot_trace_latest_pfifo_activity(activity);

    if (xemu_xbe_pfifo_stream_idle_transition_observed()) {
        return "transition-seen";
    }

    if (!exec_ctx->cpu_known) {
        return "cpu-unknown";
    }
    if (strcmp(exec_ctx->mode, "protected32")) {
        return "cpu-mode";
    }
    if (exec_ctx->cpl != 0) {
        return "cpu-cpl";
    }
    if (exec_ctx->cpu_interrupt_request != 0) {
        return "pending-interrupt";
    }

    pc = exec_ctx->eip & UINT64_C(0xffffffff);
    pc_candidate = xemu_xbe_pc_is_tcg_timer_pump_before_pfifo_candidate(pc);
    if (!pc_candidate && !activity_gate) {
        return "pc";
    }

    if (!activity->present) {
        return "activity-missing";
    }
    if (!activity->state.source ||
        strcmp(activity->state.source, "pfifo")) {
        return "activity-source";
    }
    if (!activity->state.phase ||
        (strcmp(activity->state.phase, "puller-method-pgraph-return") &&
         (!activity_gate ||
          strcmp(activity->state.phase, "puller-method-pgraph-call")))) {
        return "activity-phase";
    }
    if (!activity->state.active) {
        return "activity-inactive";
    }
    if (!activity->state.pfifo_lock_released) {
        return "pfifo-lock-held";
    }
    if (!activity->state.pgraph_locked) {
        return "pgraph-not-locked";
    }
    if (!xemu_xbe_pfifo_activity_dma_to_put(activity, activity_dma_to_put) ||
        *activity_dma_to_put == 0) {
        return "dma-get-at-put";
    }

    if (*activity_dma_to_put > (activity_gate ? 20 : 16)) {
        return "dma-to-put-large";
    }

    if (!pc_candidate && !activity_gate) {
        return "pc";
    }

    /*
     * Browser-only B6 diagnostic: native reaches the final PFIFO transition
     * with CPU_INTERRUPT_HARD already pending. Allow a PIT-only pump at the
     * narrow pre-commit PFIFO activity shape, before PFIFO records
     * stream-idle-transition, even if the browser CPU has already advanced
     * into the adjacent interrupt-disabled idle path.
     */
    return NULL;
}

static bool xemu_xbe_tcg_timer_pump_before_pfifo_gate_should_log(
    bool ready,
    const char *reason,
    const struct xemu_xbe_exec_context *exec_ctx,
    const struct xemu_xbe_pfifo_activity_snapshot *activity,
    uint32_t activity_dma_to_put,
    const struct xemu_xbe_nv2a_wait_snapshot *wait_state)
{
    uint32_t wait_dma_to_put;
    uint64_t pc;

    if (ready ||
        (reason && !strcmp(reason, "transition-seen"))) {
        return true;
    }
    if (xemu_xbe_pfifo_activity_dma_to_put(activity, &activity_dma_to_put) &&
        activity_dma_to_put <= 64) {
        return true;
    }
    if (xemu_xbe_wait_state_dma_to_put(wait_state, &wait_dma_to_put) &&
        wait_dma_to_put <= 64) {
        return true;
    }
    if (exec_ctx && exec_ctx->cpu_known) {
        pc = exec_ctx->eip & UINT64_C(0xffffffff);
        return xemu_xbe_pc_is_tcg_timer_pump_before_pfifo_candidate(pc) &&
               activity && activity->present;
    }

    return false;
}

static void xemu_xbe_tcg_timer_pump_before_pfifo_gate_trace(
    bool ready,
    const char *reason,
    const struct xemu_xbe_exec_context *exec_ctx,
    const struct xemu_xbe_pfifo_activity_snapshot *activity,
    uint32_t activity_dma_to_put,
    const struct xemu_xbe_nv2a_wait_snapshot *wait_state,
    const char *marker_kind,
    const char *mode)
{
    static uint64_t seq;
    int64_t limit = xemu_xbe_tcg_timer_pump_gate_probe_limit();
    uint32_t wait_dma_to_put = 0;
    bool activity_dma_to_put_known =
        xemu_xbe_pfifo_activity_dma_to_put(activity, &activity_dma_to_put);
    bool wait_dma_to_put_known =
        xemu_xbe_wait_state_dma_to_put(wait_state, &wait_dma_to_put);

    if (limit <= 0 ||
        seq >= (uint64_t)limit ||
        !xemu_xbe_tcg_timer_pump_before_pfifo_gate_should_log(
            ready, reason, exec_ctx, activity, activity_dma_to_put,
            wait_state)) {
        return;
    }

    seq++;
    fprintf(stderr,
            "BOOT_MARK b6 %s=timer-pump-gate context=%s"
            " seq=%" PRIu64
            " mode=%s"
            " ready=%s"
            " reason=%s"
            " transition_seen=%s"
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " wait_present=%s"
            " wait_generation=%" PRIu64
            " wait_source=%s"
            " wait_op=%s"
            " wait_seq=%" PRIu64
            " wait_dma_get=0x%08" PRIx32
            " wait_dma_put=0x%08" PRIx32
            " wait_dma_to_put_known=%s"
            " wait_dma_to_put=%" PRIu32
            " wait_pfifo_known=%s"
            " wait_fifo_access=%s"
            " wait_pfifo_pending=0x%08" PRIx32
            " wait_pfifo_enabled=0x%08" PRIx32
            " activity_present=%s"
            " activity_generation=%" PRIu64
            " activity_source=%s"
            " activity_phase=%s"
            " activity_seq=%" PRIu64
            " activity_method=0x%04" PRIx32
            " activity_parameter=0x%08" PRIx32
            " activity_dma_get_reg=0x%08" PRIx32
            " activity_dma_get_after=0x%08" PRIx32
            " activity_dma_put=0x%08" PRIx32
            " activity_dma_to_put_known=%s"
            " activity_dma_to_put=%" PRIu32
            " activity_active=%s"
            " activity_pfifo_lock_released=%s"
            " activity_pgraph_locked=%s"
            " activity_final_transition_candidate=%s\n",
            marker_kind && marker_kind[0] ? marker_kind : "tcg",
            xemu_xbe_boot_trace_context(), seq,
            mode && mode[0] ? mode : xemu_xbe_tcg_timer_pump_mode(),
            xemu_xbe_bool_str(ready), reason ? reason : "ready",
            xemu_xbe_bool_str(xemu_xbe_pfifo_stream_idle_transition_observed()),
            xemu_xbe_bool_str(exec_ctx && exec_ctx->cpu_known),
            exec_ctx ? exec_ctx->mode : "unknown",
            exec_ctx ? exec_ctx->cpl : 0,
            exec_ctx ? exec_ctx->eip : 0,
            exec_ctx ? exec_ctx->cs_selector : 0,
            exec_ctx ? exec_ctx->esp : 0,
            exec_ctx ? exec_ctx->computed_eflags : 0,
            xemu_xbe_bool_str(exec_ctx &&
                              (exec_ctx->computed_eflags & IF_MASK)),
            xemu_xbe_bool_str(exec_ctx &&
                              (exec_ctx->hflags & HF_INHIBIT_IRQ_MASK)),
            exec_ctx ? exec_ctx->cpu_interrupt_request : 0,
            xemu_xbe_bool_str(exec_ctx &&
                              exec_ctx->cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx && exec_ctx->cpu_exit_request),
            xemu_xbe_bool_str(wait_state && wait_state->present),
            wait_state ? wait_state->generation : 0,
            wait_state && wait_state->present ? wait_state->state.source : "none",
            wait_state && wait_state->present ? wait_state->state.op : "none",
            wait_state && wait_state->present ? wait_state->state.seq : 0,
            wait_state && wait_state->present ? wait_state->state.dma_get : 0,
            wait_state && wait_state->present ? wait_state->state.dma_put : 0,
            xemu_xbe_bool_str(wait_dma_to_put_known), wait_dma_to_put,
            xemu_xbe_bool_str(wait_state && wait_state->present &&
                              wait_state->state.pfifo_known),
            xemu_xbe_bool_str(wait_state && wait_state->present &&
                              wait_state->state.fifo_access),
            wait_state && wait_state->present ?
                wait_state->state.pfifo_pending : 0,
            wait_state && wait_state->present ?
                wait_state->state.pfifo_enabled : 0,
            xemu_xbe_bool_str(activity && activity->present),
            activity ? activity->generation : 0,
            activity && activity->present ? activity->state.source : "none",
            activity && activity->present ? activity->state.phase : "none",
            activity && activity->present ? activity->state.seq : 0,
            activity && activity->present ? activity->state.method : 0,
            activity && activity->present ? activity->state.parameter : 0,
            activity && activity->present ? activity->state.dma_get_reg : 0,
            activity && activity->present ? activity->state.dma_get_after : 0,
            activity && activity->present ? activity->state.dma_put : 0,
            xemu_xbe_bool_str(activity_dma_to_put_known),
            activity_dma_to_put,
            xemu_xbe_bool_str(activity && activity->present &&
                              activity->state.active),
            xemu_xbe_bool_str(activity && activity->present &&
                              activity->state.pfifo_lock_released),
            xemu_xbe_bool_str(activity && activity->present &&
                              activity->state.pgraph_locked),
            xemu_xbe_bool_str(activity && activity->present &&
                              activity->state.final_transition_candidate));
}

static bool xemu_xbe_timer_pump_idle_loop_before_pfifo_transition_ready(
    const struct xemu_xbe_nv2a_wait_snapshot *wait_state,
    bool activity_gate,
    const char *marker_kind,
    const char *mode)
{
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_pfifo_activity_snapshot activity;
    uint32_t activity_dma_to_put;
    const char *reason =
        xemu_xbe_tcg_timer_pump_before_pfifo_gate_reason(
            &exec_ctx, &activity, &activity_dma_to_put, activity_gate);
    bool ready = !reason;

    xemu_xbe_tcg_timer_pump_before_pfifo_gate_trace(
        ready, reason, &exec_ctx, &activity, activity_dma_to_put, wait_state,
        marker_kind, mode);

    return ready;
}

static bool xemu_xbe_tcg_timer_pump_idle_loop_before_pfifo_transition_ready(
    const struct xemu_xbe_nv2a_wait_snapshot *wait_state,
    bool activity_gate)
{
    return xemu_xbe_timer_pump_idle_loop_before_pfifo_transition_ready(
        wait_state, activity_gate, "tcg", xemu_xbe_tcg_timer_pump_mode());
}

bool xemu_xbe_boot_trace_tcg_timer_pump_ready(void)
{
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    const char *mode;

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready() ||
        xemu_xbe_boot_trace_tcg_timer_pump_interval() <= 0) {
        return false;
    }

    mode = xemu_xbe_tcg_timer_pump_mode();
    if (xemu_xbe_tcg_timer_pump_mode_is_pfifo_pre_commit(mode)) {
        return false;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (xemu_xbe_irq_after_pfifo_empty_only() &&
        !xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(&wait_state)) {
        if (!g_ascii_strcasecmp(mode, "pit-before-pfifo-transition")) {
            /* This mode has its own narrower pre-transition PFIFO gate. */
        } else if (!g_ascii_strcasecmp(
                       mode, "pit-before-pfifo-transition-activity")) {
            /* This mode has its own PFIFO-activity pre-transition gate. */
        } else if (!g_ascii_strcasecmp(
                       mode,
                       "pit-before-pfifo-transition-activity-defer")) {
            /* This mode also defers hard-IRQ service until the transition. */
        } else if (!g_ascii_strcasecmp(
                       mode,
                       "pit-before-pfifo-transition-activity-pre-tb-defer")) {
            /* This mode pumps before the next TB that should commit PFIFO. */
        } else if (!g_ascii_strcasecmp(
                       mode,
                       "pit-before-pfifo-transition-activity-defer-to-idle")) {
            /* This mode defers hard-IRQ service to the native idle PC. */
        } else if (xemu_xbe_tcg_timer_pump_mode_is_pre_first_read_scheduler(
                       mode)) {
            /* This mode has its own pre-first-read CPU/timer gate. */
        } else if (g_ascii_strcasecmp(mode, "pit-after-pfifo-transition") ||
                   !xemu_xbe_pfifo_stream_idle_transition_observed()) {
            return false;
        }
    }

    if (!g_ascii_strcasecmp(mode, "idle-loop")) {
        return xemu_xbe_tcg_timer_pump_idle_loop_ready();
    } else if (!g_ascii_strcasecmp(mode, "idle-loop-serviceable")) {
        return xemu_xbe_tcg_timer_pump_idle_loop_serviceable_ready();
    } else if (!g_ascii_strcasecmp(mode, "idle-loop-serviceable-pit-only")) {
        return xemu_xbe_tcg_timer_pump_idle_loop_serviceable_ready();
    } else if (!g_ascii_strcasecmp(mode,
                                  "idle-loop-serviceable-pit-after-idle")) {
        return xemu_xbe_tcg_timer_pump_idle_loop_serviceable_after_idle_ready();
    } else if (!g_ascii_strcasecmp(mode,
                                  "idle-loop-serviceable-pit-after-idle-full")) {
        return xemu_xbe_tcg_timer_pump_idle_loop_serviceable_after_idle_full_ready();
    } else if (!g_ascii_strcasecmp(mode, "pit-after-pfifo-transition")) {
        return xemu_xbe_tcg_timer_pump_idle_loop_serviceable_after_pfifo_transition_ready();
    } else if (!g_ascii_strcasecmp(mode, "pit-post-pfifo-pre-first-read")) {
        return xemu_xbe_tcg_timer_pump_post_pfifo_pre_first_read_ready();
    } else if (xemu_xbe_tcg_timer_pump_mode_is_pre_first_read_scheduler(
                   mode)) {
        return xemu_xbe_tcg_timer_pump_pre_first_read_scheduler_ready();
    } else if (!g_ascii_strcasecmp(mode, "pit-before-pfifo-transition")) {
        return xemu_xbe_tcg_timer_pump_idle_loop_before_pfifo_transition_ready(
            &wait_state, false);
    } else if (!g_ascii_strcasecmp(
                   mode, "pit-before-pfifo-transition-activity")) {
        return xemu_xbe_tcg_timer_pump_idle_loop_before_pfifo_transition_ready(
            &wait_state, true);
    } else if (!g_ascii_strcasecmp(
                   mode, "pit-before-pfifo-transition-activity-defer")) {
        return xemu_xbe_tcg_timer_pump_idle_loop_before_pfifo_transition_ready(
            &wait_state, true);
    } else if (!g_ascii_strcasecmp(
                   mode,
                   "pit-before-pfifo-transition-activity-pre-tb-defer")) {
        return xemu_xbe_tcg_timer_pump_idle_loop_before_pfifo_transition_ready(
            &wait_state, true);
    } else if (!g_ascii_strcasecmp(
                   mode,
                   "pit-before-pfifo-transition-activity-defer-to-idle")) {
        return xemu_xbe_tcg_timer_pump_idle_loop_before_pfifo_transition_ready(
            &wait_state, true);
    }

    return true;
}

bool xemu_xbe_boot_trace_tcg_timer_pump_before_tb(void)
{
    const char *mode = xemu_xbe_tcg_timer_pump_mode();

    return !g_ascii_strcasecmp(
        mode, "pit-before-pfifo-transition-activity-pre-tb-defer");
}

bool xemu_xbe_boot_trace_tcg_timer_pump_before_interrupt(void)
{
    /*
     * Keep the old broad before-interrupt path quarantined. The only allowed
     * owner here is the opt-in pre-first-read scheduler after its site-ready
     * guard has proved the dashboard image is loaded, the CPU is at a bounded
     * serviceable point, and an expired virtual timer is available.
     */
    return xemu_xbe_tcg_timer_pump_pre_first_read_scheduler_ready();
}

bool xemu_xbe_boot_trace_tcg_timer_pump_after_tb(void)
{
    return !xemu_xbe_boot_trace_tcg_timer_pump_before_tb() &&
           !xemu_xbe_tcg_timer_pump_pre_first_read_scheduler_site_ready(false);
}

bool xemu_xbe_boot_trace_tcg_timer_pump_pit_only(void)
{
    const char *mode = xemu_xbe_tcg_timer_pump_mode();

    return !g_ascii_strcasecmp(mode, "idle-loop-serviceable-pit-only") ||
           !g_ascii_strcasecmp(mode, "idle-loop-serviceable-pit-after-idle") ||
           !g_ascii_strcasecmp(mode,
                               "idle-loop-serviceable-pit-after-idle-full") ||
           !g_ascii_strcasecmp(mode, "pit-after-pfifo-transition") ||
           !g_ascii_strcasecmp(mode, "pit-post-pfifo-pre-first-read") ||
           !g_ascii_strcasecmp(mode, "pit-before-pfifo-transition") ||
           !g_ascii_strcasecmp(mode, "pit-before-pfifo-transition-activity") ||
           !g_ascii_strcasecmp(mode,
                               "pit-before-pfifo-transition-activity-defer") ||
           !g_ascii_strcasecmp(
               mode, "pit-before-pfifo-transition-activity-pre-tb-defer") ||
           !g_ascii_strcasecmp(
               mode, "pit-before-pfifo-transition-activity-defer-to-idle") ||
           xemu_xbe_tcg_timer_pump_mode_is_pre_first_read_scheduler(mode) ||
           xemu_xbe_tcg_timer_pump_mode_is_pfifo_pre_commit(mode);
}

bool xemu_xbe_boot_trace_pfifo_pre_commit_timer_pump_ready(
    const XemuXbeBootTracePfifoActivityState *state)
{
    const char *mode = xemu_xbe_tcg_timer_pump_mode();

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready() ||
        xemu_xbe_boot_trace_tcg_timer_pump_interval() <= 0 ||
        !xemu_xbe_tcg_timer_pump_mode_is_pfifo_pre_commit(mode) ||
        xemu_xbe_pfifo_stream_idle_transition_observed() ||
        !state ||
        !state->active ||
        !state->commit_range_known ||
        !state->final_transition_candidate ||
        state->dma_get_before == state->dma_get_after ||
        state->dma_get_after != state->dma_put) {
        return false;
    }

    return true;
}

static const char *xemu_xbe_boot_trace_context(void)
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

void xemu_xbe_boot_trace_observe_dma_header(uint64_t dma_addr,
                                            int64_t read_lba,
                                            int nsectors,
                                            uint32_t image_base,
                                            uint32_t image_size,
                                            uint32_t headers_size,
                                            uint32_t entry)
{
    if (!xemu_xbe_boot_trace_enabled() || !image_base || !image_size) {
        return;
    }

    xemu_xbe_dma_observation.present = true;
    xemu_xbe_dma_observation.sequence++;
    xemu_xbe_dma_observation.dma_addr = dma_addr;
    xemu_xbe_dma_observation.read_lba = read_lba;
    xemu_xbe_dma_observation.nsectors = nsectors;
    xemu_xbe_dma_observation.image_base = image_base;
    xemu_xbe_dma_observation.image_size = image_size;
    xemu_xbe_dma_observation.headers_size = headers_size;
    xemu_xbe_dma_observation.entry = entry;
    xemu_xbe_dma_observation.contiguous_bytes = 0;
    xemu_xbe_dma_observation.read_complete_marked = false;
    xemu_xbe_dma_observation.preload_direct_exec_candidate_marked = false;

    xemu_xbe_boot_trace_virtual_probe();
}

static int virt_to_phys(vaddr vaddr, hwaddr *phys_addr)
{
    MemTxAttrs attrs;
    CPUState *cs;
    hwaddr gpa;

    cs = qemu_get_cpu(0);
    if (!cs) {
        return 1; // No cpu
    }

    cpu_synchronize_state(cs);

    gpa = cpu_get_phys_page_attrs_debug(cs, vaddr & TARGET_PAGE_MASK, &attrs);
    if (gpa == -1) {
        return 1; // Unmapped
    } else {
        *phys_addr = gpa + (vaddr & ~TARGET_PAGE_MASK);
    }

    return 0;
}

static ssize_t virt_dma_memory_read(vaddr vaddr, void *buf, size_t len)
{
    size_t num_bytes_read = 0;

    while (num_bytes_read < len) {
        // Get physical page for this offset
        hwaddr phys_addr = 0;
        if (virt_to_phys(vaddr + num_bytes_read, &phys_addr) != 0) {
            return -1;
        }

        // Read contents from the page
        size_t bytes_remaining_in_page = TARGET_PAGE_SIZE - (phys_addr & ~TARGET_PAGE_MASK);
        size_t num_bytes_to_read = MIN(len - num_bytes_read, bytes_remaining_in_page);

        // FIXME: Check return value
        dma_memory_read(&address_space_memory,
                        phys_addr,
                        buf + num_bytes_read,
                        num_bytes_to_read,
                        MEMTXATTRS_UNSPECIFIED);

        num_bytes_read += num_bytes_to_read;
    }

    return num_bytes_read;
}

static void xemu_xbe_clear(struct xbe *xbe)
{
    if (xbe->headers) {
        free(xbe->headers);
    }
    memset(xbe, 0, sizeof(*xbe));
}

static bool xemu_xbe_assign_headers(struct xbe *xbe)
{
    uint32_t base;
    uint32_t cert_addr_virt;

    if (!xbe->headers || xbe->headers_len < sizeof(struct xbe_header) ||
        xbe->headers_len > XEMU_XBE_MAX_HEADERS) {
        return false;
    }

    xbe->header = (struct xbe_header *)xbe->headers;
    if (ldl_le_p(&xbe->header->m_magic) != 0x48454258) {
        return false;
    }

    base = ldl_le_p(&xbe->header->m_base);
    cert_addr_virt = ldl_le_p(&xbe->header->m_certificate_addr);
    if (base == 0 ||
        cert_addr_virt < base ||
        (uint64_t)cert_addr_virt + sizeof(struct xbe_certificate) >
            (uint64_t)base + xbe->headers_len) {
        return false;
    }

    xbe->cert = (struct xbe_certificate *)(xbe->headers + cert_addr_virt - base);
    return true;
}

struct xbe *xemu_get_xbe_info(void)
{
    vaddr hdr_addr_virt = 0x10000;

    static struct xbe xbe = {0};

    xemu_xbe_clear(&xbe);

    // Get physical page of headers
    hwaddr hdr_addr_phys = 0;
    if (virt_to_phys(hdr_addr_virt, &hdr_addr_phys) != 0) {
        return NULL;
    }

    // Check `XBEH` signature
    uint32_t sig = ldl_le_phys(&address_space_memory, hdr_addr_phys);
    if (sig != 0x48454258) {
        return NULL;
    }

    // Determine full length of headers
    xbe.headers_len = ldl_le_phys(&address_space_memory,
        hdr_addr_phys + offsetof(struct xbe_header, m_sizeof_headers));
    if (xbe.headers_len < sizeof(struct xbe_header) ||
        xbe.headers_len > XEMU_XBE_MAX_HEADERS) {
        // Headers are unusually large
        return NULL;
    }

    xbe.headers = malloc(xbe.headers_len);
    assert(xbe.headers != NULL);

    // Read all XBE headers
    ssize_t bytes_read = virt_dma_memory_read(hdr_addr_virt,
                                              xbe.headers,
                                              xbe.headers_len);
    if (bytes_read != xbe.headers_len) {
        // Failed to read headers
        return NULL;
    }

    if (!xemu_xbe_assign_headers(&xbe)) {
        xemu_xbe_clear(&xbe);
        return NULL;
    }

    return &xbe;
}

static bool xemu_xbe_phys_scan_enabled(void)
{
    const char *value = getenv("XEMU_BOOT_TRACE_XBE_PHYS_SCAN");

    return !value || !value[0] || strcmp(value, "0");
}

static uint64_t xemu_xbe_phys_scan_limit(void)
{
    static bool initialized;
    static uint64_t limit = XEMU_XBE_PHYS_SCAN_DEFAULT_LIMIT;
    const char *value;
    char *end = NULL;

    if (initialized) {
        return limit;
    }

    initialized = true;
    value = getenv("XEMU_BOOT_TRACE_XBE_PHYS_SCAN_BYTES");
    if (!value || !value[0]) {
        return limit;
    }

    limit = g_ascii_strtoull(value, &end, 10);
    if (end == value || limit == 0) {
        fprintf(stderr,
                "Invalid XEMU_BOOT_TRACE_XBE_PHYS_SCAN_BYTES='%s'; using %" PRIu64 "\n",
                value, (uint64_t)XEMU_XBE_PHYS_SCAN_DEFAULT_LIMIT);
        limit = XEMU_XBE_PHYS_SCAN_DEFAULT_LIMIT;
    }

    return limit;
}

static bool xemu_xbe_phys_read(hwaddr addr, void *buf, dma_addr_t len)
{
    return dma_memory_read(&address_space_memory, addr, buf, len,
                           MEMTXATTRS_UNSPECIFIED) == MEMTX_OK;
}

static struct xbe *xemu_get_xbe_info_from_phys_scan(hwaddr *phys_addr)
{
    static int64_t last_scan_us;
    static struct xbe xbe = {0};
    int64_t now_us;
    uint64_t limit;
    uint8_t *chunk;

    if (!xemu_xbe_phys_scan_enabled()) {
        return NULL;
    }

    now_us = g_get_monotonic_time();
    if (last_scan_us &&
        now_us - last_scan_us < XEMU_XBE_PHYS_SCAN_INTERVAL_US) {
        return NULL;
    }
    last_scan_us = now_us;

    limit = xemu_xbe_phys_scan_limit();
    chunk = g_malloc(XEMU_XBE_PHYS_SCAN_CHUNK_SIZE);
    for (hwaddr addr = 0; addr < limit; addr += XEMU_XBE_PHYS_SCAN_CHUNK_SIZE) {
        size_t chunk_len = MIN((uint64_t)XEMU_XBE_PHYS_SCAN_CHUNK_SIZE,
                               limit - addr);

        if (!xemu_xbe_phys_read(addr, chunk, chunk_len)) {
            continue;
        }

        for (size_t offset = 0;
             offset + sizeof(struct xbe_header) <= chunk_len;
             offset += XEMU_XBE_PHYS_SCAN_STRIDE) {
            uint32_t headers_len;

            if (ldl_le_p(chunk + offset) != 0x48454258) {
                continue;
            }

            headers_len = ldl_le_p(chunk + offset +
                                   offsetof(struct xbe_header,
                                            m_sizeof_headers));
            if (headers_len < sizeof(struct xbe_header) ||
                headers_len > XEMU_XBE_MAX_HEADERS) {
                continue;
            }

            xemu_xbe_clear(&xbe);
            xbe.headers_len = headers_len;
            xbe.headers = malloc(headers_len);
            assert(xbe.headers != NULL);

            if (!xemu_xbe_phys_read(addr + offset, xbe.headers, headers_len) ||
                !xemu_xbe_assign_headers(&xbe)) {
                xemu_xbe_clear(&xbe);
                continue;
            }

            *phys_addr = addr + offset;
            g_free(chunk);
            return &xbe;
        }
    }

    g_free(chunk);
    return NULL;
}

static bool xemu_xbe_current_pc(uint64_t *pc)
{
#if defined(TARGET_I386)
    CPUState *cs = qemu_get_cpu(0);
    X86CPU *cpu;
    CPUX86State *env;

    if (!cs) {
        return false;
    }

    cpu_synchronize_state(cs);
    cpu = X86_CPU(cs);
    env = &cpu->env;

    if (env->hflags & HF_CS64_MASK) {
        *pc = env->eip;
    } else {
        *pc = (uint32_t)(env->segs[R_CS].base + env->eip);
    }

    return true;
#else
    return false;
#endif
}

static bool xemu_xbe_pc_range_overlaps(uint64_t pc, uint32_t tb_size,
                                       uint64_t base, uint64_t size)
{
    uint64_t end = base + size;
    uint64_t pc_end;

    if (!size || end <= base) {
        return false;
    }

    pc_end = pc + MAX((uint32_t)1, tb_size);

    return pc < end && pc_end > base;
}

static void xemu_xbe_pc_relation_to_loaded_image(uint64_t pc, uint32_t size,
                                                 const char **relation,
                                                 uint64_t *distance)
{
    const struct xemu_xbe_loaded_observation *obs =
        &xemu_xbe_loaded_observation;
    uint64_t base = obs->base;
    uint64_t end = base + obs->size;
    uint64_t pc_end = pc + MAX((uint32_t)1, size);

    if (!obs->size || end <= base) {
        *relation = "unknown";
        *distance = 0;
    } else if (pc_end <= base) {
        *relation = "below";
        *distance = base - pc_end;
    } else if (pc >= end) {
        *relation = "above";
        *distance = pc - end;
    } else {
        *relation = "overlap";
        *distance = 0;
    }
}

static void xemu_xbe_pc_relation_to_loaded_entry(uint64_t pc, uint32_t size,
                                                 const char **relation,
                                                 uint64_t *distance)
{
    const struct xemu_xbe_loaded_observation *obs =
        &xemu_xbe_loaded_observation;
    uint64_t entry = obs->entry;
    uint64_t pc_end = pc + MAX((uint32_t)1, size);

    if (!obs->loaded_marked || !obs->entry) {
        *relation = "unknown";
        *distance = 0;
    } else if (pc_end <= entry) {
        *relation = "below";
        *distance = entry - pc_end;
    } else if (pc > entry) {
        *relation = "above";
        *distance = pc - entry;
    } else {
        *relation = "overlap";
        *distance = 0;
    }
}

static uint64_t xemu_xbe_image_offset(uint64_t image_pc)
{
    const struct xemu_xbe_loaded_observation *obs =
        &xemu_xbe_loaded_observation;

    if (image_pc < obs->base) {
        return 0;
    }

    return image_pc - obs->base;
}

static bool xemu_xbe_image_pc_in_headers(uint64_t image_pc)
{
    const struct xemu_xbe_loaded_observation *obs =
        &xemu_xbe_loaded_observation;
    uint64_t headers_end = (uint64_t)obs->base + obs->headers_size;

    return obs->headers_size && image_pc >= obs->base &&
           image_pc < headers_end;
}

static struct xemu_xbe_pc_mapping xemu_xbe_translate_pc(uint64_t pc)
{
    struct xemu_xbe_pc_mapping mapping = {
        .pc = pc,
        .phys_addr = 0,
        .mapped = false,
    };

    if (pc <= UINT32_MAX &&
        virt_to_phys((vaddr)(uint32_t)pc, &mapping.phys_addr) == 0) {
        mapping.mapped = true;
    }

    return mapping;
}

static const char *xemu_xbe_classify_memory_addr(
    uint64_t addr,
    const struct xemu_xbe_pc_mapping *mapping)
{
    uint32_t addr32;

    if (addr > UINT32_MAX) {
        return "out-of-range";
    }

    addr32 = (uint32_t)addr;
    if (addr32 < XEMU_XBE_LOW_RAM_BYTES) {
        return "direct-low-ram";
    }
    if (addr32 >= 0x80000000U &&
        addr32 < 0x80000000U + XEMU_XBE_LOW_RAM_BYTES) {
        if (mapping->mapped && mapping->phys_addr < XEMU_XBE_LOW_RAM_BYTES) {
            return "kernel-ram-alias";
        }
        return mapping->mapped ? "kernel-ram-alias-mapped" :
                                 "kernel-ram-alias-unmapped";
    }
    if (addr32 >= 0xd0000000U && addr32 < 0xe0000000U) {
        if (!mapping->mapped) {
            return "kernel-virtual-unmapped";
        }
        if (mapping->phys_addr < XEMU_XBE_LOW_RAM_BYTES) {
            return "kernel-virtual-ram";
        }
        if (mapping->phys_addr >= 0xfd000000U) {
            return "kernel-virtual-mmio-high";
        }
        return "kernel-virtual-mapped";
    }
    if (addr32 >= 0xfd000000U) {
        return "mmio-high";
    }
    if (!mapping->mapped) {
        return "unmapped";
    }
    if (mapping->phys_addr < XEMU_XBE_LOW_RAM_BYTES) {
        return "mapped-ram";
    }
    if (mapping->phys_addr >= 0xfd000000U) {
        return "mapped-mmio-high";
    }
    return "mapped-other";
}

static bool xemu_xbe_pc_overlaps_loaded_image(uint64_t pc, uint32_t tb_size,
                                              const char **address_mode,
                                              uint64_t *image_pc,
                                              struct xemu_xbe_pc_mapping *pc_mapping,
                                              struct xemu_xbe_pc_mapping *image_mapping)
{
    const struct xemu_xbe_loaded_observation *obs =
        &xemu_xbe_loaded_observation;
    uint64_t base = obs->base;
    uint64_t size = obs->size;
    uint64_t alias_pc;

    *address_mode = "none";
    *image_pc = pc;
    *pc_mapping = xemu_xbe_translate_pc(pc);
    *image_mapping = *pc_mapping;

    if (!obs->loaded_marked || obs->executed_marked || !size) {
        return false;
    }

    if (xemu_xbe_pc_range_overlaps(pc, tb_size, base, size)) {
        *address_mode = "direct";
        return true;
    }

    if (pc > UINT32_MAX || !(pc & 0x80000000ULL)) {
        return false;
    }

    alias_pc = (uint32_t)pc & 0x7fffffffU;
    if (!xemu_xbe_pc_range_overlaps(alias_pc, tb_size, base, size)) {
        return false;
    }

    *image_pc = alias_pc;
    *image_mapping = xemu_xbe_translate_pc(alias_pc);
    if (!pc_mapping->mapped || !image_mapping->mapped ||
        pc_mapping->phys_addr != image_mapping->phys_addr) {
        *address_mode = "high-alias-mismatch";
        return false;
    }

    *address_mode = "high-alias";
    return true;
}

static const char *xemu_xbe_phys_match_status(
    const char *address_mode,
    const struct xemu_xbe_pc_mapping *pc_mapping,
    const struct xemu_xbe_pc_mapping *image_mapping)
{
    if (strcmp(address_mode, "direct") == 0 ||
        strcmp(address_mode, "high-alias") == 0 ||
        strcmp(address_mode, "high-alias-mismatch") == 0) {
        if (!pc_mapping->mapped || !image_mapping->mapped) {
            return "unknown";
        }

        return pc_mapping->phys_addr == image_mapping->phys_addr ? "yes" : "no";
    }

    return "not-applicable";
}

static void xemu_xbe_classify_branch_target(
    const struct xemu_xbe_branch_probe *branch,
    struct xemu_xbe_target_classification *classification)
{
    if (!branch->target_known) {
        classification->relation = "unknown";
        classification->entry_relation = "unknown";
        classification->distance = 0;
        classification->entry_distance = 0;
        classification->address_mode = "unknown";
        classification->image_pc = 0;
        classification->mapping = (struct xemu_xbe_pc_mapping) { 0 };
        classification->image_mapping = (struct xemu_xbe_pc_mapping) { 0 };
        classification->phys_match = "unknown";
        return;
    }

    xemu_xbe_pc_relation_to_loaded_image(branch->target, 1,
                                         &classification->relation,
                                         &classification->distance);
    xemu_xbe_pc_overlaps_loaded_image(branch->target, 1,
                                      &classification->address_mode,
                                      &classification->image_pc,
                                      &classification->mapping,
                                      &classification->image_mapping);
    xemu_xbe_pc_relation_to_loaded_entry(classification->image_pc, 1,
                                         &classification->entry_relation,
                                         &classification->entry_distance);
    classification->phys_match =
        xemu_xbe_phys_match_status(classification->address_mode,
                                   &classification->mapping,
                                   &classification->image_mapping);
}

static void xemu_xbe_classify_value(
    uint64_t value,
    struct xemu_xbe_target_classification *classification)
{
    struct xemu_xbe_branch_probe probe = {
        .kind = "value",
        .target_known = true,
        .target = value,
    };

    xemu_xbe_classify_branch_target(&probe, classification);
}

static bool xemu_xbe_classification_entry_near(
    const struct xemu_xbe_target_classification *classification)
{
    uint64_t window = xemu_xbe_entry_target_window();

    return strcmp(classification->entry_relation, "unknown") != 0 &&
           strcmp(classification->address_mode, "unknown") != 0 &&
           strcmp(classification->address_mode, "none") != 0 &&
           classification->entry_distance <= window;
}

static bool xemu_xbe_classification_high_alias_mismatch(
    const struct xemu_xbe_target_classification *classification)
{
    return strcmp(classification->address_mode, "high-alias-mismatch") == 0;
}

static bool xemu_xbe_classification_candidate(
    const struct xemu_xbe_target_classification *classification)
{
    return strcmp(classification->phys_match, "yes") == 0 ||
           xemu_xbe_classification_entry_near(classification) ||
           xemu_xbe_classification_high_alias_mismatch(classification);
}

static int xemu_xbe_classification_priority(
    const struct xemu_xbe_target_classification *classification)
{
    if (strcmp(classification->phys_match, "yes") == 0) {
        return 3;
    }
    if (xemu_xbe_classification_entry_near(classification)) {
        return 2;
    }
    if (xemu_xbe_classification_high_alias_mismatch(classification)) {
        return 1;
    }
    return 0;
}

static void xemu_xbe_consider_dispatch_candidate(
    struct xemu_xbe_dispatch_candidate *candidate,
    const char *label,
    int index,
    uint64_t value,
    const struct xemu_xbe_target_classification *classification)
{
    if (!xemu_xbe_classification_candidate(classification)) {
        return;
    }

    if (!candidate->present ||
        xemu_xbe_classification_priority(classification) >
        xemu_xbe_classification_priority(&candidate->classification)) {
        candidate->present = true;
        candidate->label = label;
        candidate->index = index;
        candidate->value = value;
        candidate->classification = *classification;
    }
}

static bool xemu_xbe_read_code_probe_bytes(uint64_t pc, uint8_t *bytes,
                                           size_t len)
{
    if (pc > UINT32_MAX) {
        return false;
    }

    return virt_dma_memory_read((vaddr)(uint32_t)pc, bytes, len) ==
           (ssize_t)len;
}

static bool xemu_xbe_read_phys_probe_bytes(hwaddr phys_addr, uint8_t *bytes,
                                           size_t len)
{
    if (!len) {
        return true;
    }

    if (phys_addr > UINT64_MAX - len) {
        return false;
    }

    return dma_memory_read(&address_space_memory, phys_addr, bytes, len,
                           MEMTXATTRS_UNSPECIFIED) == MEMTX_OK;
}

static bool xemu_xbe_read_phys_u32(hwaddr phys_addr, uint32_t *value)
{
    uint32_t tmp;

    if (!xemu_xbe_read_phys_probe_bytes(phys_addr, (uint8_t *)&tmp,
                                        sizeof(tmp))) {
        return false;
    }

    *value = ldl_le_p(&tmp);
    return true;
}

static uint64_t xemu_xbe_fnv1a64(const uint8_t *data, size_t len)
{
    uint64_t hash = 1469598103934665603ULL;

    for (size_t i = 0; i < len; i++) {
        hash ^= data[i];
        hash *= 1099511628211ULL;
    }

    return hash;
}

static bool xemu_xbe_read_u32(vaddr addr, uint32_t *value)
{
    uint32_t tmp;

    if (virt_dma_memory_read(addr, &tmp, sizeof(tmp)) != sizeof(tmp)) {
        return false;
    }

    *value = ldl_le_p(&tmp);
    return true;
}

static bool xemu_xbe_read_u16(vaddr addr, uint16_t *value)
{
    uint16_t tmp;

    if (virt_dma_memory_read(addr, &tmp, sizeof(tmp)) != sizeof(tmp)) {
        return false;
    }

    *value = lduw_le_p(&tmp);
    return true;
}

static bool xemu_xbe_read_u8(vaddr addr, uint8_t *value)
{
    return virt_dma_memory_read(addr, value, sizeof(*value)) ==
           sizeof(*value);
}

static void xemu_xbe_capture_stack_probe(
    const struct xemu_xbe_exec_context *ctx,
    struct xemu_xbe_stack_probe *probe)
{
    uint8_t stack_bytes[XEMU_XBE_IRQ_STACK_BYTES];

    *probe = (struct xemu_xbe_stack_probe) { 0 };
    if (!ctx->cpu_known || ctx->esp > UINT32_MAX) {
        return;
    }

    if (virt_dma_memory_read((vaddr)(uint32_t)ctx->esp, stack_bytes,
                             sizeof(stack_bytes)) != sizeof(stack_bytes)) {
        return;
    }

    probe->read_ok = true;
    probe->hash = xemu_xbe_fnv1a64(stack_bytes, sizeof(stack_bytes));
    for (int i = 0; i < XEMU_XBE_IRQ_STACK_WORDS; i++) {
        probe->words[i] = ldl_le_p(stack_bytes + i * sizeof(uint32_t));
    }
}

static bool xemu_xbe_exec_context_reg_value(
    const struct xemu_xbe_exec_context *ctx,
    uint8_t reg,
    uint64_t *value)
{
    if (!ctx->cpu_known) {
        return false;
    }

    switch (reg & 7) {
    case 0:
        *value = ctx->eax;
        return true;
    case 1:
        *value = ctx->ecx;
        return true;
    case 2:
        *value = ctx->edx;
        return true;
    case 3:
        *value = ctx->ebx;
        return true;
    case 4:
        *value = ctx->esp;
        return true;
    case 5:
        *value = ctx->ebp;
        return true;
    case 6:
        *value = ctx->esi;
        return true;
    case 7:
        *value = ctx->edi;
        return true;
    default:
        return false;
    }
}

static bool xemu_xbe_decode_modrm_ea32(const uint8_t *bytes, size_t len,
                                       const struct xemu_xbe_exec_context *ctx,
                                       uint8_t mod, uint8_t rm,
                                       uint64_t *addr)
{
    size_t offset = 2;
    uint64_t base = 0;
    uint64_t index = 0;
    uint64_t result;
    int64_t disp = 0;
    bool has_base = true;
    bool has_disp32 = false;

    if (!ctx->cpu_known || mod == 3) {
        return false;
    }

    if (rm == 4) {
        uint8_t sib;
        uint8_t scale;
        uint8_t index_reg;
        uint8_t base_reg;

        if (len < offset + 1) {
            return false;
        }

        sib = bytes[offset++];
        scale = sib >> 6;
        index_reg = (sib >> 3) & 7;
        base_reg = sib & 7;

        if (index_reg != 4 &&
            !xemu_xbe_exec_context_reg_value(ctx, index_reg, &index)) {
            return false;
        }
        index <<= scale;

        if (mod == 0 && base_reg == 5) {
            has_base = false;
            has_disp32 = true;
        } else if (!xemu_xbe_exec_context_reg_value(ctx, base_reg, &base)) {
            return false;
        }
    } else if (mod == 0 && rm == 5) {
        has_base = false;
        has_disp32 = true;
    } else if (!xemu_xbe_exec_context_reg_value(ctx, rm, &base)) {
        return false;
    }

    if (mod == 1) {
        if (len < offset + 1) {
            return false;
        }
        disp = (int8_t)bytes[offset];
    } else if (mod == 2 || has_disp32) {
        if (len < offset + 4) {
            return false;
        }
        disp = (int32_t)ldl_le_p(bytes + offset);
    }

    result = (has_base ? base : 0) + index + disp;
    *addr = (uint32_t)result;
    return true;
}

static void xemu_xbe_decode_branch_probe(
    uint64_t pc,
    const struct xemu_xbe_exec_context *ctx,
    struct xemu_xbe_code_probe *code)
{
    const uint8_t *bytes = code->bytes;
    uint8_t opcode;

    code->branch.kind = "none";
    code->branch.target_known = false;
    code->branch.target = 0;

    if (!code->read_ok || code->len == 0) {
        code->branch.kind = "code-unreadable";
        return;
    }

    opcode = bytes[0];
    code->opcode = opcode;

    if (opcode == 0xe8 || opcode == 0xe9) {
        int32_t rel;

        if (code->len < 5) {
            code->branch.kind = opcode == 0xe8 ? "call-rel32-short-read" :
                                                 "jmp-rel32-short-read";
            return;
        }

        rel = (int32_t)ldl_le_p(bytes + 1);
        code->branch.kind = opcode == 0xe8 ? "call-rel32" : "jmp-rel32";
        code->branch.target_known = true;
        code->branch.target = (uint32_t)(pc + 5 + rel);
        return;
    }

    if (opcode == 0xeb || (opcode >= 0x70 && opcode <= 0x7f) ||
        (opcode >= 0xe0 && opcode <= 0xe3)) {
        int8_t rel;

        if (code->len < 2) {
            code->branch.kind = "rel8-short-read";
            return;
        }

        rel = (int8_t)bytes[1];
        if (opcode == 0xeb) {
            code->branch.kind = "jmp-rel8";
        } else if (opcode >= 0x70 && opcode <= 0x7f) {
            code->branch.kind = "jcc-rel8";
        } else {
            code->branch.kind = "loop-rel8";
        }
        code->branch.target_known = true;
        code->branch.target = (uint32_t)(pc + 2 + rel);
        return;
    }

    if (opcode == 0x0f) {
        if (code->len < 2) {
            code->branch.kind = "0f-short-read";
            return;
        }

        code->opcode2_known = true;
        code->opcode2 = bytes[1];
        if (bytes[1] >= 0x80 && bytes[1] <= 0x8f) {
            int32_t rel;

            if (code->len < 6) {
                code->branch.kind = "jcc-rel32-short-read";
                return;
            }

            rel = (int32_t)ldl_le_p(bytes + 2);
            code->branch.kind = "jcc-rel32";
            code->branch.target_known = true;
            code->branch.target = (uint32_t)(pc + 6 + rel);
        }
        return;
    }

    if (opcode == 0xff) {
        uint8_t modrm;
        uint8_t mod;
        uint8_t reg;
        uint8_t rm;

        if (code->len < 2) {
            code->branch.kind = "ff-short-read";
            return;
        }

        modrm = bytes[1];
        code->modrm_known = true;
        code->modrm = modrm;
        mod = modrm >> 6;
        reg = (modrm >> 3) & 7;
        rm = modrm & 7;

        if (reg == 2 || reg == 4) {
            code->branch.kind = reg == 2 ? "call-rm32" : "jmp-rm32";
            if (mod == 3 &&
                xemu_xbe_exec_context_reg_value(ctx, rm,
                                                &code->branch.target)) {
                code->branch.kind = reg == 2 ? "call-reg" : "jmp-reg";
                code->branch.target_known = true;
            } else if (mod != 3 &&
                       xemu_xbe_decode_modrm_ea32(bytes, code->len, ctx,
                                                  mod, rm,
                                                  &code->branch.operand_addr)) {
                uint32_t target;

                code->branch.operand_addr_known = true;
                if (xemu_xbe_read_u32((vaddr)(uint32_t)
                                      code->branch.operand_addr, &target)) {
                    code->branch.kind = reg == 2 ? "call-mem32" : "jmp-mem32";
                    code->branch.target_known = true;
                    code->branch.target = target;
                }
            }
        }
        return;
    }

    if (opcode == 0xc2 || opcode == 0xc3 || opcode == 0xca ||
        opcode == 0xcb) {
        uint32_t ret_target;

        code->branch.kind = "ret";
        if (ctx->cpu_known && ctx->esp <= UINT32_MAX &&
            xemu_xbe_read_u32((vaddr)(uint32_t)ctx->esp, &ret_target)) {
            code->branch.kind = "ret-stack";
            code->branch.target_known = true;
            code->branch.target = ret_target;
        }
        return;
    }

    if (opcode == 0xcc || opcode == 0xcd) {
        code->branch.kind = "int";
        return;
    }
}

static void xemu_xbe_decode_memory_probe(
    const struct xemu_xbe_exec_context *ctx,
    struct xemu_xbe_code_probe *code)
{
    const uint8_t *bytes = code->bytes;
    const uint8_t *ea_bytes = bytes;
    const char *kind = NULL;
    uint8_t opcode;
    uint8_t opcode2 = 0;
    uint8_t modrm;
    uint8_t mod;
    uint8_t reg;
    uint8_t rm;
    size_t ea_len;
    uint32_t width = 4;

    code->mem_kind = "none";
    code->mem_width = 0;
    code->mem_addr_known = false;
    code->mem_addr = 0;
    code->mem_region = "none";
    code->mem_mapping = (struct xemu_xbe_pc_mapping) { 0 };
    code->mem_value_read = false;
    code->mem_value = 0;

    if (!code->read_ok || code->len < 2) {
        return;
    }

    opcode = bytes[0];
    modrm = bytes[1];
    ea_len = code->len;
    mod = modrm >> 6;
    reg = (modrm >> 3) & 7;
    rm = modrm & 7;

    if (opcode == 0x0f) {
        if (code->len < 3) {
            return;
        }

        opcode2 = bytes[1];
        modrm = bytes[2];
        ea_bytes = bytes + 1;
        ea_len = code->len - 1;
        mod = modrm >> 6;
        reg = (modrm >> 3) & 7;
        rm = modrm & 7;

        switch (opcode2) {
        case 0xb6:
            kind = "movzx-r32-rm8";
            width = 1;
            break;
        case 0xb7:
            kind = "movzx-r32-rm16";
            width = 2;
            break;
        case 0xbe:
            kind = "movsx-r32-rm8";
            width = 1;
            break;
        case 0xbf:
            kind = "movsx-r32-rm16";
            width = 2;
            break;
        default:
            break;
        }
    } else {
        switch (opcode) {
        case 0x39:
            kind = "cmp-rm32-r32";
            break;
        case 0x3b:
            kind = "cmp-r32-rm32";
            break;
        case 0x85:
            kind = "test-rm32-r32";
            break;
        case 0x89:
            kind = "mov-rm32-r32";
            break;
        case 0x8b:
            kind = "mov-r32-rm32";
            break;
        case 0x81:
            if (reg == 7) {
                kind = "cmp-rm32-imm32";
            }
            break;
        case 0x83:
            if (reg == 7) {
                kind = "cmp-rm32-imm8";
            }
            break;
        case 0xf7:
            if (reg == 0) {
                kind = "test-rm32-imm32";
            }
            break;
        default:
            break;
        }
    }

    if (!kind) {
        return;
    }

    code->mem_kind = kind;
    code->mem_width = width;
    code->modrm_known = true;
    code->modrm = modrm;
    if (mod == 3) {
        return;
    }

    if (xemu_xbe_decode_modrm_ea32(ea_bytes, ea_len, ctx, mod, rm,
                                   &code->mem_addr)) {
        code->mem_addr_known = true;
        if (code->mem_addr <= UINT32_MAX) {
            vaddr addr = (vaddr)(uint32_t)code->mem_addr;

            code->mem_mapping = xemu_xbe_translate_pc(code->mem_addr);
            code->mem_region =
                xemu_xbe_classify_memory_addr(code->mem_addr,
                                              &code->mem_mapping);
            if (width == 1) {
                uint8_t value;

                if (xemu_xbe_read_u8(addr, &value)) {
                    code->mem_value = value;
                    code->mem_value_read = true;
                }
            } else if (width == 2) {
                uint16_t value;

                if (xemu_xbe_read_u16(addr, &value)) {
                    code->mem_value = value;
                    code->mem_value_read = true;
                }
            } else if (xemu_xbe_read_u32(addr, &code->mem_value)) {
                code->mem_value_read = true;
            }
        } else {
            code->mem_region =
                xemu_xbe_classify_memory_addr(code->mem_addr,
                                              &code->mem_mapping);
        }
    }
}

static void xemu_xbe_capture_code_probe(
    uint64_t pc,
    const struct xemu_xbe_exec_context *ctx,
    struct xemu_xbe_code_probe *code)
{
    memset(code, 0, sizeof(*code));
    code->len = sizeof(code->bytes);
    code->branch.kind = "none";
    code->read_ok = xemu_xbe_read_code_probe_bytes(pc, code->bytes,
                                                   code->len);
    if (!code->read_ok) {
        xemu_xbe_decode_branch_probe(pc, ctx, code);
        xemu_xbe_decode_memory_probe(ctx, code);
        return;
    }

    code->hash = xemu_xbe_fnv1a64(code->bytes, code->len);
    xemu_xbe_decode_branch_probe(pc, ctx, code);
    xemu_xbe_decode_memory_probe(ctx, code);
}

static void xemu_xbe_capture_exec_context(struct xemu_xbe_exec_context *ctx)
{
    memset(ctx, 0, sizeof(*ctx));
    ctx->mode = "unsupported";

#if defined(TARGET_I386)
    CPUState *cs = qemu_get_cpu(0);
    X86CPU *cpu;
    CPUX86State *env;

    if (!cs) {
        ctx->mode = "no-cpu";
        return;
    }

    cpu_synchronize_state(cs);
    cpu = X86_CPU(cs);
    env = &cpu->env;

    ctx->cpu_known = true;
    ctx->mode = (env->hflags & HF_CS64_MASK) ? "long" :
                (env->hflags & HF_CS32_MASK) ? "protected32" :
                (env->cr[0] & CR0_PE_MASK) ? "protected16" :
                "real";
    ctx->cpl = env->hflags & HF_CPL_MASK;
    ctx->eip = env->eip;
    ctx->eax = env->regs[R_EAX];
    ctx->ebx = env->regs[R_EBX];
    ctx->ecx = env->regs[R_ECX];
    ctx->edx = env->regs[R_EDX];
    ctx->esp = env->regs[R_ESP];
    ctx->ebp = env->regs[R_EBP];
    ctx->esi = env->regs[R_ESI];
    ctx->edi = env->regs[R_EDI];
    ctx->eflags = env->eflags;
    ctx->computed_eflags = cpu_compute_eflags(env);
    ctx->hflags = env->hflags;
    ctx->cr0 = env->cr[0];
    ctx->cr3 = env->cr[3];
    ctx->cr4 = env->cr[4];
    ctx->efer = env->efer;
    ctx->cs_selector = env->segs[R_CS].selector;
    ctx->cs_base = env->segs[R_CS].base;
    ctx->ss_selector = env->segs[R_SS].selector;
    ctx->ss_base = env->segs[R_SS].base;
    ctx->cpu_interrupt_request = cs->interrupt_request;
    ctx->cpu_halted = cs->halted != 0;
    ctx->cpu_exit_request = cs->exit_request;
    ctx->cpu_exception_index = cs->exception_index;
#endif
}

#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
static void xemu_xbe_boot_trace_memory_watch_callback(void *opaque,
                                                      MemoryRegion *mr,
                                                      hwaddr addr,
                                                      hwaddr len,
                                                      bool write)
{
    int64_t limit = xemu_xbe_memory_watch_limit();
    uint8_t bytes[XEMU_XBE_MEMORY_WATCH_BYTES];
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    uint32_t value = 0;
    bool value_read;

    (void)opaque;

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready() ||
        !xemu_xbe_memory_watch_access_matches(write) ||
        limit == 0 ||
        xemu_xbe_memory_watch_emit_count >= (uint64_t)limit ||
        xemu_xbe_memory_watch_suppress) {
        return;
    }

    xemu_xbe_memory_watch_suppress = true;
    value_read = xemu_xbe_read_phys_probe_bytes(
        xemu_xbe_memory_watch_phys_addr, bytes, sizeof(bytes));
    xemu_xbe_memory_watch_suppress = false;
    if (value_read) {
        value = ldl_le_p(bytes);
    }

    xemu_xbe_capture_exec_context(&exec_ctx);
    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    xemu_xbe_memory_watch_emit_count++;

    fprintf(stderr,
            "BOOT_MARK b6 memory-watch context=%s"
            " seq=%" PRIu64
            " access=%s"
            " access_filter=%s"
            " phys=0x%08" PRIx64
            " watch_phys=0x%08" PRIx64
            " watch_bytes=%u"
            " mr=%s"
            " mr_offset=0x%08" PRIx64
            " watch_mr_offset=0x%08" PRIx64
            " access_len=%" PRIu64
            " value_read=%s"
            " value_phase=pre-access"
            " value=0x%08" PRIx32
            " entry_ready=%s"
            " stream_idle=%s"
            " nv2a_wait_present=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_dma_get=0x%08x"
            " nv2a_dma_put=0x%08x"
            " cpu_known=%s"
            " cpu_mode=%s"
            " cpl=%" PRIu32
            " eip=0x%08" PRIx64
            " esp=0x%08" PRIx64
            " eflags=0x%08" PRIx64
            " interrupts_enabled=%s"
            " hflags=0x%08" PRIx64
            " irq_inhibited=%s"
            " cpu_interrupt_request=0x%08" PRIx32
            " pending_interrupt=%s"
            " source=mem-access-callback\n",
            xemu_xbe_boot_trace_context(),
            xemu_xbe_memory_watch_emit_count,
            write ? "write" : "read",
            xemu_xbe_memory_watch_access_mode_name(),
            (uint64_t)xemu_xbe_memory_watch_phys_addr,
            (uint64_t)xemu_xbe_memory_watch_phys_addr,
            XEMU_XBE_MEMORY_WATCH_BYTES,
            mr ? memory_region_name(mr) : "none",
            (uint64_t)addr,
            (uint64_t)xemu_xbe_memory_watch_region_offset,
            (uint64_t)len,
            xemu_xbe_bool_str(value_read), value,
            xemu_xbe_bool_str(xemu_xbe_loaded_observation.entry_marked),
            xemu_xbe_bool_str(xemu_xbe_nv2a_wait_is_stream_idle(&wait_state)),
            xemu_xbe_bool_str(wait_state.present),
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.dma_get : 0,
            wait_state.present ? wait_state.state.dma_put : 0,
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            exec_ctx.hflags,
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0));
}
#endif

static bool xemu_xbe_boot_trace_memory_watch_sample(uint64_t *phys_out,
                                                    uint32_t *value_out)
{
#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
    uint64_t phys = xemu_xbe_memory_watch_phys();
    int64_t limit = xemu_xbe_memory_watch_limit();
    uint8_t bytes[XEMU_XBE_MEMORY_WATCH_BYTES];
    bool value_read;

    *phys_out = phys;
    *value_out = 0;
    if (!xemu_xbe_boot_trace_enabled() || phys == 0 || limit == 0) {
        return false;
    }

#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
    xemu_xbe_memory_watch_suppress = true;
#endif
    value_read = xemu_xbe_read_phys_probe_bytes(phys, bytes, sizeof(bytes));
#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
    xemu_xbe_memory_watch_suppress = false;
#endif
    if (!value_read) {
        return false;
    }

    *value_out = ldl_le_p(bytes);
    return true;
#else
    *phys_out = 0;
    *value_out = 0;
    return false;
#endif
}

void xemu_xbe_boot_trace_tick_block_pre_tb(uint64_t guest_pc,
                                           uint32_t tb_size,
                                           const char *source)
{
#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    struct xemu_xbe_tick_block_snapshot *snapshot =
        &xemu_xbe_tick_block_pending;
    int64_t limit = xemu_xbe_tick_block_probe_limit();

    if (!xemu_xbe_boot_trace_enabled() || limit == 0 ||
        guest_pc != XEMU_XBE_TICK_BLOCK_PC ||
        !obs->loaded_marked || obs->executed_marked || !obs->entry_marked ||
        obs->exec_tick_block_probe_count >= (uint64_t)limit) {
        return;
    }

    memset(snapshot, 0, sizeof(*snapshot));
    snapshot->valid = true;
    snapshot->start_pc = guest_pc;
    snapshot->tb_size = tb_size;
    snapshot->source = source ? source : "tcg-tb-pre";
    xemu_xbe_capture_exec_context(&snapshot->pre_ctx);
    xemu_xbe_boot_trace_latest_nv2a_wait_state(&snapshot->pre_wait_state);
    snapshot->pre_wait_state.state.source = snapshot->pre_wait_state.source;
    snapshot->pre_wait_state.state.op = snapshot->pre_wait_state.op;

    xemu_xbe_memory_watch_suppress = true;
    snapshot->pre_watch_value_read =
        xemu_xbe_read_phys_u32(XEMU_XBE_TICK_BLOCK_WATCH_PHYS,
                               &snapshot->pre_watch_value);
    xemu_xbe_memory_watch_suppress = false;
#else
    (void)guest_pc;
    (void)tb_size;
    (void)source;
#endif
}

void xemu_xbe_boot_trace_tick_block_post_tb(uint64_t guest_pc,
                                            uint32_t tb_size,
                                            int tb_exit,
                                            const char *source)
{
#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    struct xemu_xbe_tick_block_snapshot *snapshot =
        &xemu_xbe_tick_block_pending;
    struct xemu_xbe_exec_context post_ctx;
    struct xemu_xbe_nv2a_wait_snapshot post_wait_state;
    uint64_t next_pc = 0;
    bool next_pc_known;
    bool expected_path;
    bool stream_idle_transition_seen;
    bool pre_stream_completion;
    bool post_watch_value_read;
    uint32_t post_watch_value = 0;
    int64_t watch_delta = 0;
    uint64_t pre_watch_ticks = 0;
    uint64_t post_watch_ticks = 0;
    int64_t watch_delta_ticks = 0;
    uint64_t emitted_seq;
    uint64_t pre_stream_seq;
    int64_t limit = xemu_xbe_tick_block_probe_limit();

    if (!snapshot->valid ||
        snapshot->start_pc != guest_pc ||
        snapshot->tb_size != tb_size) {
        return;
    }

    snapshot->valid = false;
    if (limit == 0 ||
        obs->exec_tick_block_probe_count >= (uint64_t)limit) {
        return;
    }

    next_pc_known = xemu_xbe_current_pc(&next_pc);
    expected_path = next_pc_known && next_pc == XEMU_XBE_TICK_BLOCK_NEXT_PC;
    if (!expected_path) {
        return;
    }

    xemu_xbe_capture_exec_context(&post_ctx);
    xemu_xbe_boot_trace_latest_nv2a_wait_state(&post_wait_state);
    post_wait_state.state.source = post_wait_state.source;
    post_wait_state.state.op = post_wait_state.op;

    xemu_xbe_memory_watch_suppress = true;
    post_watch_value_read =
        xemu_xbe_read_phys_u32(XEMU_XBE_TICK_BLOCK_WATCH_PHYS,
                               &post_watch_value);
    xemu_xbe_memory_watch_suppress = false;

    stream_idle_transition_seen = xemu_xbe_pfifo_stream_idle_transition_observed();
    pre_stream_completion = !stream_idle_transition_seen;
    emitted_seq = ++obs->exec_tick_block_probe_count;
    if (pre_stream_completion) {
        pre_stream_seq = ++obs->exec_tick_block_pre_stream_count;
    } else {
        pre_stream_seq = obs->exec_tick_block_pre_stream_count;
    }

    if (snapshot->pre_watch_value_read && post_watch_value_read) {
        watch_delta = (int64_t)post_watch_value -
                      (int64_t)snapshot->pre_watch_value;
        watch_delta_ticks =
            watch_delta / (int64_t)XEMU_XBE_TICK_BLOCK_TICK_UNIT;
    }
    if (snapshot->pre_watch_value_read) {
        pre_watch_ticks =
            snapshot->pre_watch_value / XEMU_XBE_TICK_BLOCK_TICK_UNIT;
    }
    if (post_watch_value_read) {
        post_watch_ticks =
            post_watch_value / XEMU_XBE_TICK_BLOCK_TICK_UNIT;
    }

    fprintf(stderr,
            "BOOT_MARK b6 tick-block=complete context=%s"
            " seq=%" PRIu64
            " source=%s"
            " pre_source=%s"
            " start_pc=0x%08" PRIx64
            " next_pc_known=%s"
            " next_pc=0x%08" PRIx64
            " expected_next=0x%08" PRIx64
            " tb_size=%" PRIu32
            " tb_exit=%d"
            " limit=%" PRId64
            " pre_stream_idle_completion=%s"
            " pre_stream_idle_completions=%" PRIu64
            " pre_stream_idle_seq=%" PRIu64
            " stream_idle_transition_seen=%s"
            " edge_decision_seen_before_completion=%s"
            " edge_decision_count_before_completion=%" PRIu64
            " watch_phys=0x%08" PRIx64
            " watch_tick_unit=0x%08" PRIx32
            " pre_watch_value_read=%s"
            " pre_watch_value=0x%08" PRIx32
            " pre_watch_ticks=%" PRIu64
            " post_watch_value_read=%s"
            " post_watch_value=0x%08" PRIx32
            " post_watch_ticks=%" PRIu64
            " watch_delta=%" PRId64
            " watch_delta_ticks=%" PRId64
            " pre_cpu_known=%s"
            " pre_eip=0x%08" PRIx64
            " pre_eflags=0x%08" PRIx64
            " pre_interrupts_enabled=%s"
            " pre_irq_inhibited=%s"
            " pre_cpu_interrupt_request=0x%08" PRIx32
            " pre_pending_interrupt=%s"
            " post_cpu_known=%s"
            " post_eip=0x%08" PRIx64
            " post_eflags=0x%08" PRIx64
            " post_interrupts_enabled=%s"
            " post_irq_inhibited=%s"
            " post_cpu_interrupt_request=0x%08" PRIx32
            " post_pending_interrupt=%s"
            " pre_wait_present=%s"
            " pre_stream_idle=%s"
            " pre_wait_generation=%" PRIu64
            " pre_wait_source=%s"
            " pre_wait_op=%s"
            " pre_wait_seq=%" PRIu64
            " pre_wait_dma_get=0x%08x"
            " pre_wait_dma_put=0x%08x"
            " pre_wait_pmc_pending=0x%08x"
            " pre_wait_pfifo_known=%s"
            " pre_wait_pfifo_pending=0x%08x"
            " pre_wait_pcrtc_pending=0x%08x"
            " pre_wait_pgraph_pending=0x%08x"
            " post_wait_present=%s"
            " post_stream_idle=%s"
            " post_wait_generation=%" PRIu64
            " post_wait_source=%s"
            " post_wait_op=%s"
            " post_wait_seq=%" PRIu64
            " post_wait_dma_get=0x%08x"
            " post_wait_dma_put=0x%08x"
            " post_wait_pmc_pending=0x%08x"
            " post_wait_pfifo_known=%s"
            " post_wait_pfifo_pending=0x%08x"
            " post_wait_pcrtc_pending=0x%08x"
            " post_wait_pgraph_pending=0x%08x\n",
            xemu_xbe_boot_trace_context(), emitted_seq,
            source ? source : "tcg-tb-post",
            snapshot->source ? snapshot->source : "tcg-tb-pre",
            snapshot->start_pc,
            xemu_xbe_bool_str(next_pc_known),
            next_pc_known ? next_pc : 0,
            XEMU_XBE_TICK_BLOCK_NEXT_PC,
            tb_size, tb_exit, limit,
            xemu_xbe_bool_str(pre_stream_completion),
            obs->exec_tick_block_pre_stream_count, pre_stream_seq,
            xemu_xbe_bool_str(stream_idle_transition_seen),
            xemu_xbe_bool_str(obs->exec_edge_decision_probe_count > 0),
            obs->exec_edge_decision_probe_count,
            XEMU_XBE_TICK_BLOCK_WATCH_PHYS,
            XEMU_XBE_TICK_BLOCK_TICK_UNIT,
            xemu_xbe_bool_str(snapshot->pre_watch_value_read),
            snapshot->pre_watch_value, pre_watch_ticks,
            xemu_xbe_bool_str(post_watch_value_read),
            post_watch_value, post_watch_ticks,
            watch_delta, watch_delta_ticks,
            xemu_xbe_bool_str(snapshot->pre_ctx.cpu_known),
            snapshot->pre_ctx.eip, snapshot->pre_ctx.computed_eflags,
            xemu_xbe_bool_str(snapshot->pre_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(snapshot->pre_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            snapshot->pre_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(snapshot->pre_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(post_ctx.cpu_known),
            post_ctx.eip, post_ctx.computed_eflags,
            xemu_xbe_bool_str(post_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(post_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            post_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(post_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(snapshot->pre_wait_state.present),
            xemu_xbe_bool_str(
                xemu_xbe_nv2a_wait_is_stream_idle(&snapshot->pre_wait_state)),
            snapshot->pre_wait_state.generation,
            snapshot->pre_wait_state.state.source ?
                snapshot->pre_wait_state.state.source : "none",
            snapshot->pre_wait_state.state.op ?
                snapshot->pre_wait_state.state.op : "none",
            snapshot->pre_wait_state.state.seq,
            snapshot->pre_wait_state.state.dma_get,
            snapshot->pre_wait_state.state.dma_put,
            snapshot->pre_wait_state.state.pmc_pending,
            xemu_xbe_bool_str(snapshot->pre_wait_state.state.pfifo_known),
            snapshot->pre_wait_state.state.pfifo_pending,
            snapshot->pre_wait_state.state.pcrtc_pending,
            snapshot->pre_wait_state.state.pgraph_pending,
            xemu_xbe_bool_str(post_wait_state.present),
            xemu_xbe_bool_str(
                xemu_xbe_nv2a_wait_is_stream_idle(&post_wait_state)),
            post_wait_state.generation,
            post_wait_state.state.source ?
                post_wait_state.state.source : "none",
            post_wait_state.state.op ?
                post_wait_state.state.op : "none",
            post_wait_state.state.seq,
            post_wait_state.state.dma_get,
            post_wait_state.state.dma_put,
            post_wait_state.state.pmc_pending,
            xemu_xbe_bool_str(post_wait_state.state.pfifo_known),
            post_wait_state.state.pfifo_pending,
            post_wait_state.state.pcrtc_pending,
            post_wait_state.state.pgraph_pending);
    xemu_xbe_pre_first_read_scheduler_note_tick_block(
        guest_pc, tb_size, tb_exit, source ? source : "tcg-tb-post");
#else
    (void)guest_pc;
    (void)tb_size;
    (void)tb_exit;
    (void)source;
#endif
}

bool xemu_xbe_boot_trace_tick_block_irq_defer_pre_tb(
    uint64_t guest_pc,
    uint32_t tb_size,
    uint32_t interrupt_request,
    bool cpu_exit_request,
    uint32_t hard_irq_mask,
    uint32_t defer_mask,
    const char *source)
{
#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    bool active = false;
    bool watch_value_read = false;
    bool sample_mismatch;
    uint32_t watch_value = 0;
    uint32_t effective_interrupt_request;
    bool effective_exit_request;
    uint64_t watch_ticks = 0;
    uint64_t seq;
    int64_t limit;
    const char *reason = "defer-one-tick-block";

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_tick_block_irq_defer_enabled() ||
        guest_pc != XEMU_XBE_TICK_BLOCK_PC) {
        return false;
    }

    limit = xemu_xbe_tick_block_irq_defer_probe_limit();
    if (limit == 0 ||
        obs->exec_tick_block_irq_defer_probe_count >= (uint64_t)limit) {
        return false;
    }

    xemu_xbe_capture_exec_context(&exec_ctx);
    effective_interrupt_request = interrupt_request;
    effective_exit_request = cpu_exit_request;
    if (exec_ctx.cpu_known) {
        effective_interrupt_request = exec_ctx.cpu_interrupt_request;
        effective_exit_request = exec_ctx.cpu_exit_request;
    }
    sample_mismatch = effective_interrupt_request != interrupt_request ||
                      effective_exit_request != cpu_exit_request;

    /*
     * This exact-PC IRQ defer was a diagnostic-only experiment. It proved too
     * sensitive to whether timer delivery lands at the return predecessor or
     * at the tick block itself, so keep the marker but disable the behavior.
     */
    reason = "quarantined";

    seq = ++obs->exec_tick_block_irq_defer_probe_count;
    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    wait_state.state.source = wait_state.source;
    wait_state.state.op = wait_state.op;

    xemu_xbe_memory_watch_suppress = true;
    watch_value_read =
        xemu_xbe_read_phys_u32(XEMU_XBE_TICK_BLOCK_WATCH_PHYS, &watch_value);
    xemu_xbe_memory_watch_suppress = false;
    if (watch_value_read) {
        watch_ticks = watch_value / XEMU_XBE_TICK_BLOCK_TICK_UNIT;
    }

    fprintf(stderr,
            "BOOT_MARK b6 tick-block-irq-defer context=%s"
            " phase=pre"
            " seq=%" PRIu64
            " source=%s"
            " action=%s"
            " reason=%s"
            " start_pc=0x%08" PRIx64
            " tb_size=%" PRIu32
            " hard_irq_mask=0x%08" PRIx32
            " defer_mask=0x%08" PRIx32
            " interrupt_request=0x%08" PRIx32
            " cpu_exit_request=%s"
            " effective_interrupt_request=0x%08" PRIx32
            " effective_exit_request=%s"
            " sample_mismatch=%s"
            " loaded=%s"
            " entry_ready=%s"
            " executed=%s"
            " tick_block_completions=%" PRIu64
            " tick_block_pre_stream_completions=%" PRIu64
            " edge_decision_count=%" PRIu64
            " edge_decision_skip_count=%" PRIu64
            " limit=%" PRId64
            " watch_phys=0x%08" PRIx64
            " watch_value_read=%s"
            " watch_value=0x%08" PRIx32
            " watch_ticks=%" PRIu64
            " cpu_known=%s"
            " eip=0x%08" PRIx64
            " eflags=0x%08" PRIx64
            " interrupts_enabled=%s"
            " irq_inhibited=%s"
            " ctx_interrupt_request=0x%08" PRIx32
            " ctx_exit_request=%s"
            " wait_present=%s"
            " stream_idle=%s"
            " wait_generation=%" PRIu64
            " wait_source=%s"
            " wait_op=%s"
            " wait_seq=%" PRIu64
            " wait_dma_get=0x%08x"
            " wait_dma_put=0x%08x"
            " wait_pmc_pending=0x%08x"
            " wait_pfifo_known=%s"
            " wait_pfifo_pending=0x%08x"
            " wait_pcrtc_pending=0x%08x"
            " wait_pgraph_pending=0x%08x\n",
            xemu_xbe_boot_trace_context(),
            seq,
            source ? source : "tcg-tb-pre",
            active ? "defer" : "skip",
            reason,
            guest_pc,
            tb_size,
            hard_irq_mask,
            defer_mask,
            interrupt_request,
            xemu_xbe_bool_str(cpu_exit_request),
            effective_interrupt_request,
            xemu_xbe_bool_str(effective_exit_request),
            xemu_xbe_bool_str(sample_mismatch),
            xemu_xbe_bool_str(obs->loaded_marked),
            xemu_xbe_bool_str(obs->entry_marked),
            xemu_xbe_bool_str(obs->executed_marked),
            obs->exec_tick_block_probe_count,
            obs->exec_tick_block_pre_stream_count,
            obs->exec_edge_decision_probe_count,
            obs->exec_edge_decision_skip_count,
            limit,
            XEMU_XBE_TICK_BLOCK_WATCH_PHYS,
            xemu_xbe_bool_str(watch_value_read),
            watch_value,
            watch_ticks,
            xemu_xbe_bool_str(exec_ctx.cpu_known),
            exec_ctx.eip,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(wait_state.present),
            xemu_xbe_bool_str(xemu_xbe_nv2a_wait_is_stream_idle(&wait_state)),
            wait_state.generation,
            wait_state.state.source ? wait_state.state.source : "none",
            wait_state.state.op ? wait_state.state.op : "none",
            wait_state.state.seq,
            wait_state.state.dma_get,
            wait_state.state.dma_put,
            wait_state.state.pmc_pending,
            xemu_xbe_bool_str(wait_state.state.pfifo_known),
            wait_state.state.pfifo_pending,
            wait_state.state.pcrtc_pending,
            wait_state.state.pgraph_pending);

    return active;
#else
    (void)guest_pc;
    (void)tb_size;
    (void)interrupt_request;
    (void)cpu_exit_request;
    (void)hard_irq_mask;
    (void)defer_mask;
    (void)source;
    return false;
#endif
}

void xemu_xbe_boot_trace_tick_block_irq_defer_post_tb(
    uint64_t guest_pc,
    uint32_t tb_size,
    int tb_exit,
    uint32_t saved_interrupt_request,
    bool saved_exit_request,
    uint16_t saved_icount_decr_high,
    uint32_t post_interrupt_request,
    bool post_exit_request,
    uint16_t post_icount_decr_high,
    uint32_t restored_interrupt_request,
    bool restored_exit_request,
    uint16_t restored_icount_decr_high,
    const char *source)
{
#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    struct xemu_xbe_exec_context exec_ctx;
    uint64_t next_pc = 0;
    bool next_pc_known;
    bool expected_path;

    xemu_xbe_capture_exec_context(&exec_ctx);
    next_pc_known = xemu_xbe_current_pc(&next_pc);
    expected_path = next_pc_known && next_pc == XEMU_XBE_TICK_BLOCK_NEXT_PC;

    fprintf(stderr,
            "BOOT_MARK b6 tick-block-irq-defer context=%s"
            " phase=post"
            " seq=%" PRIu64
            " source=%s"
            " start_pc=0x%08" PRIx64
            " next_pc_known=%s"
            " next_pc=0x%08" PRIx64
            " expected_next=0x%08" PRIx64
            " expected_path=%s"
            " tb_size=%" PRIu32
            " tb_exit=%d"
            " saved_interrupt_request=0x%08" PRIx32
            " saved_exit_request=%s"
            " saved_icount_decr_high=0x%04" PRIx16
            " post_interrupt_request=0x%08" PRIx32
            " post_exit_request=%s"
            " post_icount_decr_high=0x%04" PRIx16
            " restored_interrupt_request=0x%08" PRIx32
            " restored_exit_request=%s"
            " restored_icount_decr_high=0x%04" PRIx16
            " tick_block_completions=%" PRIu64
            " tick_block_pre_stream_completions=%" PRIu64
            " edge_decision_count=%" PRIu64
            " edge_decision_skip_count=%" PRIu64
            " cpu_known=%s"
            " eip=0x%08" PRIx64
            " eflags=0x%08" PRIx64
            " interrupts_enabled=%s"
            " irq_inhibited=%s"
            " ctx_interrupt_request=0x%08" PRIx32
            " ctx_exit_request=%s\n",
            xemu_xbe_boot_trace_context(),
            obs->exec_tick_block_irq_defer_probe_count,
            source ? source : "tcg-tb-post",
            guest_pc,
            xemu_xbe_bool_str(next_pc_known),
            next_pc_known ? next_pc : 0,
            XEMU_XBE_TICK_BLOCK_NEXT_PC,
            xemu_xbe_bool_str(expected_path),
            tb_size,
            tb_exit,
            saved_interrupt_request,
            xemu_xbe_bool_str(saved_exit_request),
            saved_icount_decr_high,
            post_interrupt_request,
            xemu_xbe_bool_str(post_exit_request),
            post_icount_decr_high,
            restored_interrupt_request,
            xemu_xbe_bool_str(restored_exit_request),
            restored_icount_decr_high,
            obs->exec_tick_block_probe_count,
            obs->exec_tick_block_pre_stream_count,
            obs->exec_edge_decision_probe_count,
            obs->exec_edge_decision_skip_count,
            xemu_xbe_bool_str(exec_ctx.cpu_known),
            exec_ctx.eip,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request));
#else
    (void)guest_pc;
    (void)tb_size;
    (void)tb_exit;
    (void)saved_interrupt_request;
    (void)saved_exit_request;
    (void)saved_icount_decr_high;
    (void)post_interrupt_request;
    (void)post_exit_request;
    (void)post_icount_decr_high;
    (void)restored_interrupt_request;
    (void)restored_exit_request;
    (void)restored_icount_decr_high;
    (void)source;
#endif
}

void xemu_xbe_boot_trace_edge_decision_pre_tb(uint64_t guest_pc,
                                              uint32_t tb_size,
                                              const char *source)
{
#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    struct xemu_xbe_edge_decision_snapshot *snapshot =
        &xemu_xbe_edge_decision_pending;
    struct xemu_xbe_nv2a_wait_snapshot last_pfifo_idle;
    int64_t limit = xemu_xbe_edge_decision_limit();
    hwaddr cmp_phys = 0;

    if (!xemu_xbe_boot_trace_enabled() || limit == 0 ||
        guest_pc != XEMU_XBE_EDGE_DECISION_PC) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&snapshot->wait_state);
    snapshot->wait_state.state.source = snapshot->wait_state.source;
    snapshot->wait_state.state.op = snapshot->wait_state.op;

    if (!obs->loaded_marked || obs->executed_marked || !obs->entry_marked ||
        obs->exec_edge_decision_probe_count >= (uint64_t)limit ||
        !xemu_xbe_nv2a_wait_is_stream_idle(&snapshot->wait_state)) {
        const char *reason;

        if (!obs->loaded_marked) {
            reason = "not-loaded";
        } else if (!obs->entry_marked) {
            reason = "entry-not-ready";
        } else if (obs->executed_marked) {
            reason = "already-executed";
        } else if (obs->exec_edge_decision_probe_count >= (uint64_t)limit) {
            reason = "probe-limit";
        } else {
            reason = "stream-idle-gate-false";
        }

        if (obs->exec_edge_decision_skip_count < (uint64_t)limit) {
            xemu_xbe_boot_trace_latest_pfifo_stream_idle_state(
                &last_pfifo_idle);
            obs->exec_edge_decision_skip_count++;
            fprintf(stderr,
                    "BOOT_MARK b6 edge-decision-skip context=%s"
                    " seq=%" PRIu64
                    " source=%s"
                    " reason=%s"
                    " guest_pc=0x%08" PRIx64
                    " target_pc=0x%08" PRIx64
                    " tb_size=%" PRIu32
                    " loaded=%s"
                    " entry_ready=%s"
                    " executed=%s"
                    " probe_count=%" PRIu64
                    " skip_count=%" PRIu64
                    " limit=%" PRId64
                    " wait_present=%s"
                    " stream_idle=%s"
                    " wait_generation=%" PRIu64
                    " wait_source=%s"
                    " wait_op=%s"
                    " wait_seq=%" PRIu64
                    " wait_dma_get=0x%08x"
                    " wait_dma_put=0x%08x"
                    " wait_pmc_pending=0x%08x"
                    " wait_pfifo_known=%s"
                    " wait_pfifo_pending=0x%08x"
                    " wait_pcrtc_pending=0x%08x"
                    " wait_pgraph_pending=0x%08x"
                    " last_pfifo_idle_present=%s"
                    " last_pfifo_idle_stream_idle=%s"
                    " last_pfifo_idle_generation=%" PRIu64
                    " last_pfifo_idle_source=%s"
                    " last_pfifo_idle_op=%s"
                    " last_pfifo_idle_seq=%" PRIu64
                    " last_pfifo_idle_dma_get=0x%08x"
                    " last_pfifo_idle_dma_put=0x%08x"
                    " last_pfifo_idle_pmc_pending=0x%08x"
                    " last_pfifo_idle_pfifo_known=%s"
                    " last_pfifo_idle_pfifo_pending=0x%08x"
                    " last_pfifo_idle_pcrtc_pending=0x%08x"
                    " last_pfifo_idle_pgraph_pending=0x%08x"
                    "\n",
                    xemu_xbe_boot_trace_context(),
                    obs->exec_edge_decision_skip_count,
                    source ? source : "tcg-tb-pre",
                    reason,
                    guest_pc,
                    XEMU_XBE_EDGE_DECISION_PC,
                    tb_size,
                    xemu_xbe_bool_str(obs->loaded_marked),
                    xemu_xbe_bool_str(obs->entry_marked),
                    xemu_xbe_bool_str(obs->executed_marked),
                    obs->exec_edge_decision_probe_count,
                    obs->exec_edge_decision_skip_count,
                    limit,
                    xemu_xbe_bool_str(snapshot->wait_state.present),
                    xemu_xbe_bool_str(
                        xemu_xbe_nv2a_wait_is_stream_idle(&snapshot->wait_state)),
                    snapshot->wait_state.generation,
                    snapshot->wait_state.state.source ?
                        snapshot->wait_state.state.source : "none",
                    snapshot->wait_state.state.op ?
                        snapshot->wait_state.state.op : "none",
                    snapshot->wait_state.state.seq,
                    snapshot->wait_state.state.dma_get,
                    snapshot->wait_state.state.dma_put,
                    snapshot->wait_state.state.pmc_pending,
                    xemu_xbe_bool_str(snapshot->wait_state.state.pfifo_known),
                    snapshot->wait_state.state.pfifo_pending,
                    snapshot->wait_state.state.pcrtc_pending,
                    snapshot->wait_state.state.pgraph_pending,
                    xemu_xbe_bool_str(last_pfifo_idle.present),
                    xemu_xbe_bool_str(
                        xemu_xbe_nv2a_wait_is_stream_idle(&last_pfifo_idle)),
                    last_pfifo_idle.generation,
                    last_pfifo_idle.state.source ?
                        last_pfifo_idle.state.source : "none",
                    last_pfifo_idle.state.op ?
                        last_pfifo_idle.state.op : "none",
                    last_pfifo_idle.state.seq,
                    last_pfifo_idle.state.dma_get,
                    last_pfifo_idle.state.dma_put,
                    last_pfifo_idle.state.pmc_pending,
                    xemu_xbe_bool_str(last_pfifo_idle.state.pfifo_known),
                    last_pfifo_idle.state.pfifo_pending,
                    last_pfifo_idle.state.pcrtc_pending,
                    last_pfifo_idle.state.pgraph_pending);
        }
        return;
    }

    memset(snapshot, 0, sizeof(*snapshot));
    xemu_xbe_boot_trace_latest_nv2a_wait_state(&snapshot->wait_state);
    snapshot->wait_state.state.source = snapshot->wait_state.source;
    snapshot->wait_state.state.op = snapshot->wait_state.op;
    xemu_xbe_capture_exec_context(&snapshot->pre_ctx);
    xemu_xbe_capture_code_probe(guest_pc, &snapshot->pre_ctx,
                                &snapshot->start_code_probe);

    xemu_xbe_memory_watch_suppress = true;
    snapshot->watch_value_read =
        xemu_xbe_read_phys_u32(0x0003a890, &snapshot->watch_value);
    snapshot->cmp_mapping_known =
        virt_to_phys((vaddr)(uint32_t)XEMU_XBE_EDGE_DECISION_CMP_ADDR,
                     &cmp_phys) == 0;
    snapshot->cmp_phys = snapshot->cmp_mapping_known ? cmp_phys : 0;
    snapshot->cmp_value_read =
        xemu_xbe_read_u32((vaddr)(uint32_t)XEMU_XBE_EDGE_DECISION_CMP_ADDR,
                          &snapshot->cmp_value);
    xemu_xbe_memory_watch_suppress = false;

    snapshot->valid = true;
    snapshot->seq = ++obs->exec_edge_decision_probe_count;
    snapshot->start_pc = guest_pc;
    snapshot->tb_size = tb_size;
    snapshot->source = source ? source : "tcg-tb-pre";
    xemu_xbe_pre_first_read_scheduler_note_first_read(
        guest_pc, tb_size, source ? source : "tcg-tb-pre");
#else
    (void)guest_pc;
    (void)tb_size;
    (void)source;
#endif
}

void xemu_xbe_boot_trace_edge_decision_post_tb(uint64_t guest_pc,
                                               uint32_t tb_size,
                                               int tb_exit,
                                               const char *source)
{
#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
    struct xemu_xbe_edge_decision_snapshot *snapshot =
        &xemu_xbe_edge_decision_pending;
    struct xemu_xbe_exec_context post_ctx;
    struct xemu_xbe_code_probe next_code_probe;
    uint64_t next_pc = 0;
    bool next_pc_known;

    if (!snapshot->valid ||
        snapshot->start_pc != guest_pc ||
        snapshot->tb_size != tb_size) {
        return;
    }

    snapshot->valid = false;
    next_pc_known = xemu_xbe_current_pc(&next_pc);
    xemu_xbe_capture_exec_context(&post_ctx);
    if (next_pc_known) {
        xemu_xbe_capture_code_probe(next_pc, &post_ctx, &next_code_probe);
    } else {
        memset(&next_code_probe, 0, sizeof(next_code_probe));
        next_code_probe.branch.kind = "none";
        next_code_probe.mem_kind = "none";
        next_code_probe.mem_region = "none";
    }

    fprintf(stderr,
            "BOOT_MARK b6 edge-decision context=%s"
            " seq=%" PRIu64
            " source=%s"
            " pre_source=%s"
            " start_pc=0x%08" PRIx64
            " next_pc_known=%s"
            " next_pc=0x%08" PRIx64
            " tb_size=%" PRIu32
            " tb_exit=%d"
            " expected_next=0x%08" PRIx64
            " fallthrough_match=%s"
            " pre_cpu_known=%s"
            " pre_cpu_mode=%s"
            " pre_cpl=%" PRIu32
            " pre_eip=0x%08" PRIx64
            " pre_eax=0x%08" PRIx64
            " pre_ebx=0x%08" PRIx64
            " pre_ecx=0x%08" PRIx64
            " pre_edx=0x%08" PRIx64
            " pre_esp=0x%08" PRIx64
            " pre_ebp=0x%08" PRIx64
            " pre_esi=0x%08" PRIx64
            " pre_edi=0x%08" PRIx64
            " pre_eflags_raw=0x%08" PRIx64
            " pre_eflags=0x%08" PRIx64
            " pre_interrupts_enabled=%s"
            " pre_flag_zf=%s"
            " pre_flag_cf=%s"
            " pre_flag_sf=%s"
            " pre_flag_of=%s"
            " pre_hflags=0x%08" PRIx64
            " pre_irq_inhibited=%s"
            " pre_cpu_interrupt_request=0x%08" PRIx32
            " pre_pending_interrupt=%s"
            " pre_cpu_halted=%s"
            " pre_cpu_exit_request=%s"
            " pre_watch_phys=0x0003a890"
            " pre_watch_value_read=%s"
            " pre_watch_value=0x%08" PRIx32
            " pre_cmp_addr=0x%08" PRIx64
            " pre_cmp_phys_mapped=%s"
            " pre_cmp_phys=0x%08" PRIx64
            " pre_cmp_value_read=%s"
            " pre_cmp_value=0x%08" PRIx32
            " pre_wait_present=%s"
            " pre_stream_idle=%s"
            " pre_wait_generation=%" PRIu64
            " pre_wait_source=%s"
            " pre_wait_op=%s"
            " pre_wait_seq=%" PRIu64
            " pre_wait_dma_get=0x%08x"
            " pre_wait_dma_put=0x%08x"
            " pre_wait_pmc_pending=0x%08x"
            " pre_wait_pmc_enabled=0x%08x"
            " pre_wait_pfifo_known=%s"
            " pre_wait_pfifo_pending=0x%08x"
            " pre_wait_pfifo_enabled=0x%08x"
            " pre_wait_pcrtc_pending=0x%08x"
            " pre_wait_pcrtc_enabled=0x%08x"
            " pre_wait_pgraph_pending=0x%08x"
            " pre_wait_pgraph_enabled=0x%08x"
            " start_code_read=%s"
            " start_code_hash=0x%016" PRIx64
            " start_opcode=0x%02" PRIx8
            " start_modrm_known=%s"
            " start_modrm=0x%02" PRIx8
            " start_mem_kind=%s"
            " start_mem_addr_known=%s"
            " start_mem_addr=0x%08" PRIx64
            " start_mem_phys_mapped=%s"
            " start_mem_phys=0x%08" PRIx64
            " start_mem_value_read=%s"
            " start_mem_value=0x%08" PRIx32
            " post_cpu_known=%s"
            " post_eip=0x%08" PRIx64
            " post_eflags=0x%08" PRIx64
            " post_interrupts_enabled=%s"
            " post_cpu_interrupt_request=0x%08" PRIx32
            " post_pending_interrupt=%s"
            " next_code_read=%s"
            " next_code_hash=0x%016" PRIx64
            " next_opcode=0x%02" PRIx8
            " next_modrm_known=%s"
            " next_modrm=0x%02" PRIx8
            " next_branch_kind=%s"
            " next_branch_target_known=%s"
            " next_branch_target=0x%08" PRIx64
            " next_mem_kind=%s"
            " next_mem_addr_known=%s"
            " next_mem_addr=0x%08" PRIx64
            " next_mem_phys_mapped=%s"
            " next_mem_phys=0x%08" PRIx64
            " next_mem_value_read=%s"
            " next_mem_value=0x%08" PRIx32
            "\n",
            xemu_xbe_boot_trace_context(),
            snapshot->seq,
            source ? source : "tcg-tb-post",
            snapshot->source ? snapshot->source : "tcg-tb-pre",
            snapshot->start_pc,
            xemu_xbe_bool_str(next_pc_known),
            next_pc_known ? next_pc : 0,
            snapshot->tb_size,
            tb_exit,
            snapshot->start_pc + snapshot->tb_size,
            xemu_xbe_bool_str(next_pc_known &&
                              next_pc == snapshot->start_pc +
                                         snapshot->tb_size),
            xemu_xbe_bool_str(snapshot->pre_ctx.cpu_known),
            snapshot->pre_ctx.mode,
            snapshot->pre_ctx.cpl,
            snapshot->pre_ctx.eip,
            snapshot->pre_ctx.eax,
            snapshot->pre_ctx.ebx,
            snapshot->pre_ctx.ecx,
            snapshot->pre_ctx.edx,
            snapshot->pre_ctx.esp,
            snapshot->pre_ctx.ebp,
            snapshot->pre_ctx.esi,
            snapshot->pre_ctx.edi,
            snapshot->pre_ctx.eflags,
            snapshot->pre_ctx.computed_eflags,
            xemu_xbe_bool_str(snapshot->pre_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(snapshot->pre_ctx.computed_eflags & CC_Z),
            xemu_xbe_bool_str(snapshot->pre_ctx.computed_eflags & CC_C),
            xemu_xbe_bool_str(snapshot->pre_ctx.computed_eflags & CC_S),
            xemu_xbe_bool_str(snapshot->pre_ctx.computed_eflags & CC_O),
            snapshot->pre_ctx.hflags,
            xemu_xbe_bool_str(snapshot->pre_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            snapshot->pre_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(snapshot->pre_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(snapshot->pre_ctx.cpu_halted),
            xemu_xbe_bool_str(snapshot->pre_ctx.cpu_exit_request),
            xemu_xbe_bool_str(snapshot->watch_value_read),
            snapshot->watch_value,
            XEMU_XBE_EDGE_DECISION_CMP_ADDR,
            xemu_xbe_bool_str(snapshot->cmp_mapping_known),
            snapshot->cmp_phys,
            xemu_xbe_bool_str(snapshot->cmp_value_read),
            snapshot->cmp_value,
            xemu_xbe_bool_str(snapshot->wait_state.present),
            xemu_xbe_bool_str(
                xemu_xbe_nv2a_wait_is_stream_idle(&snapshot->wait_state)),
            snapshot->wait_state.generation,
            snapshot->wait_state.state.source ?
                snapshot->wait_state.state.source : "none",
            snapshot->wait_state.state.op ?
                snapshot->wait_state.state.op : "none",
            snapshot->wait_state.state.seq,
            snapshot->wait_state.state.dma_get,
            snapshot->wait_state.state.dma_put,
            snapshot->wait_state.state.pmc_pending,
            snapshot->wait_state.state.pmc_enabled,
            xemu_xbe_bool_str(snapshot->wait_state.state.pfifo_known),
            snapshot->wait_state.state.pfifo_pending,
            snapshot->wait_state.state.pfifo_enabled,
            snapshot->wait_state.state.pcrtc_pending,
            snapshot->wait_state.state.pcrtc_enabled,
            snapshot->wait_state.state.pgraph_pending,
            snapshot->wait_state.state.pgraph_enabled,
            xemu_xbe_bool_str(snapshot->start_code_probe.read_ok),
            snapshot->start_code_probe.hash,
            snapshot->start_code_probe.opcode,
            xemu_xbe_bool_str(snapshot->start_code_probe.modrm_known),
            snapshot->start_code_probe.modrm,
            snapshot->start_code_probe.mem_kind,
            xemu_xbe_bool_str(snapshot->start_code_probe.mem_addr_known),
            snapshot->start_code_probe.mem_addr,
            xemu_xbe_bool_str(snapshot->start_code_probe.mem_mapping.mapped),
            snapshot->start_code_probe.mem_mapping.phys_addr,
            xemu_xbe_bool_str(snapshot->start_code_probe.mem_value_read),
            snapshot->start_code_probe.mem_value,
            xemu_xbe_bool_str(post_ctx.cpu_known),
            post_ctx.eip,
            post_ctx.computed_eflags,
            xemu_xbe_bool_str(post_ctx.computed_eflags & IF_MASK),
            post_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(post_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(next_code_probe.read_ok),
            next_code_probe.hash,
            next_code_probe.opcode,
            xemu_xbe_bool_str(next_code_probe.modrm_known),
            next_code_probe.modrm,
            next_code_probe.branch.kind ?
                next_code_probe.branch.kind : "none",
            xemu_xbe_bool_str(next_code_probe.branch.target_known),
            next_code_probe.branch.target,
            next_code_probe.mem_kind ? next_code_probe.mem_kind : "none",
            xemu_xbe_bool_str(next_code_probe.mem_addr_known),
            next_code_probe.mem_addr,
            xemu_xbe_bool_str(next_code_probe.mem_mapping.mapped),
            next_code_probe.mem_mapping.phys_addr,
            xemu_xbe_bool_str(next_code_probe.mem_value_read),
            next_code_probe.mem_value);
#else
    (void)guest_pc;
    (void)tb_size;
    (void)tb_exit;
    (void)source;
#endif
}

static void xemu_xbe_boot_trace_memory_watch_install(void)
{
#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
    CPUState *cpu;
    MemoryRegionSection section;
    uint64_t phys = xemu_xbe_memory_watch_phys();
    int64_t limit = xemu_xbe_memory_watch_limit();
    uint64_t section_size;

    if (xemu_xbe_memory_watch_callback_ref ||
        xemu_xbe_memory_watch_install_attempted ||
        !xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready() ||
        !xemu_xbe_memory_watch_access_enabled() ||
        phys == 0 ||
        limit == 0) {
        return;
    }

    xemu_xbe_memory_watch_install_attempted = true;
    xemu_xbe_memory_watch_phys_addr = (hwaddr)phys;
    cpu = qemu_get_cpu(0);
    if (!cpu) {
        fprintf(stderr,
                "BOOT_MARK b6 memory-watch-install context=%s"
                " result=fail reason=no-cpu"
                " phys=0x%08" PRIx64
                " watch_bytes=%u"
                " access_filter=%s"
                " limit=%" PRId64
                " source=entry-ready\n",
                xemu_xbe_boot_trace_context(), phys,
                XEMU_XBE_MEMORY_WATCH_BYTES,
                xemu_xbe_memory_watch_access_mode_name(), limit);
        return;
    }

    section = memory_region_find(get_system_memory(), phys,
                                 XEMU_XBE_MEMORY_WATCH_BYTES);
    if (!section.mr || !int128_nz(section.size)) {
        fprintf(stderr,
                "BOOT_MARK b6 memory-watch-install context=%s"
                " result=fail reason=no-memory-region"
                " phys=0x%08" PRIx64
                " watch_bytes=%u"
                " access_filter=%s"
                " limit=%" PRId64
                " source=entry-ready\n",
                xemu_xbe_boot_trace_context(), phys,
                XEMU_XBE_MEMORY_WATCH_BYTES,
                xemu_xbe_memory_watch_access_mode_name(), limit);
        if (section.mr) {
            memory_region_unref(section.mr);
        }
        return;
    }

    section_size = int128_get64(section.size);
    if (!memory_region_is_ram(section.mr) ||
        section_size < XEMU_XBE_MEMORY_WATCH_BYTES) {
        fprintf(stderr,
                "BOOT_MARK b6 memory-watch-install context=%s"
                " result=fail reason=%s"
                " phys=0x%08" PRIx64
                " watch_bytes=%u"
                " access_filter=%s"
                " limit=%" PRId64
                " mr=%s"
                " mr_offset=0x%08" PRIx64
                " section_bytes=%" PRIu64
                " source=entry-ready\n",
                xemu_xbe_boot_trace_context(),
                memory_region_is_ram(section.mr) ? "short-section" : "non-ram",
                phys, XEMU_XBE_MEMORY_WATCH_BYTES,
                xemu_xbe_memory_watch_access_mode_name(), limit,
                memory_region_name(section.mr),
                (uint64_t)section.offset_within_region, section_size);
        memory_region_unref(section.mr);
        return;
    }

    xemu_xbe_memory_watch_region_offset = section.offset_within_region;
    xemu_xbe_memory_watch_callback_ref = mem_access_callback_insert(
        cpu, section.mr, section.offset_within_region,
        XEMU_XBE_MEMORY_WATCH_BYTES,
        xemu_xbe_boot_trace_memory_watch_callback, NULL);

    fprintf(stderr,
            "BOOT_MARK b6 memory-watch-install context=%s"
            " result=pass"
            " phys=0x%08" PRIx64
            " watch_bytes=%u"
            " access_filter=%s"
            " limit=%" PRId64
            " mr=%s"
            " mr_offset=0x%08" PRIx64
            " section_bytes=%" PRIu64
            " source=entry-ready\n",
            xemu_xbe_boot_trace_context(), phys, XEMU_XBE_MEMORY_WATCH_BYTES,
            xemu_xbe_memory_watch_access_mode_name(), limit,
            memory_region_name(section.mr),
            (uint64_t)section.offset_within_region, section_size);
#endif
}

void xemu_xbe_boot_trace_observe_pic_irq_line(bool master,
                                              int irq,
                                              int level,
                                              uint32_t irr_before,
                                              uint32_t irr_after,
                                              uint32_t last_irr_before,
                                              uint32_t last_irr_after,
                                              uint32_t imr,
                                              uint32_t isr,
                                              uint32_t elcr,
                                              int output_irq)
{
    static uint64_t seq;
    static uint64_t watch_seq;
    int64_t limit;
    int guest_irq;
    bool watched;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready()) {
        return;
    }

    guest_irq = master ? irq : irq + 8;
    watched = xemu_xbe_irq_watch_matches(guest_irq);
    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (!xemu_xbe_irq_trace_gate_allows(guest_irq, &wait_state)) {
        return;
    }

    limit = xemu_xbe_pic_irq_probe_limit();
    if (watched) {
        if (watch_seq >= (uint64_t)limit) {
            return;
        }
        watch_seq++;
    } else if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);

    fprintf(stderr,
            "BOOT_MARK b6 pic=irq-line context=%s"
            " seq=%" PRIu64
            " chip=%s"
            " irq=%d"
            " guest_irq=%d"
            " level=%s"
            " output_irq=%d"
            " irr_before=0x%02" PRIx32
            " irr_after=0x%02" PRIx32
            " last_irr_before=0x%02" PRIx32
            " last_irr_after=0x%02" PRIx32
            " imr=0x%02" PRIx32
            " isr=0x%02" PRIx32
            " elcr=0x%02" PRIx32
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " watch=%s"
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x\n",
            xemu_xbe_boot_trace_context(), seq,
            master ? "master" : "slave", irq, guest_irq,
            level ? "assert" : "deassert", output_irq,
            irr_before, irr_after, last_irr_before, last_irr_after,
            imr, isr, elcr,
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(watched),
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);
}

void xemu_xbe_boot_trace_observe_lpc_irq_route(const char *source,
                                               const char *route_type,
                                               int input_irq,
                                               int pic_irq,
                                               int level,
                                               uint32_t acpi_route,
                                               uint32_t int_route,
                                               uint32_t pirq_route,
                                               bool delivered)
{
    static uint64_t seq;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready()) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (!xemu_xbe_irq_trace_gate_allows(pic_irq, &wait_state)) {
        return;
    }

    limit = xemu_xbe_pic_irq_probe_limit();
    if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);

    fprintf(stderr,
            "BOOT_MARK b6 lpc=irq-route context=%s"
            " seq=%" PRIu64
            " source=%s"
            " route_type=%s"
            " input_irq=%d"
            " pic_irq=%d"
            " level=%s"
            " delivered=%s"
            " acpi_route=0x%08" PRIx32
            " int_route=0x%08" PRIx32
            " pirq_route=0x%08" PRIx32
            " watch=%s"
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x\n",
            xemu_xbe_boot_trace_context(), seq,
            source ? source : "unknown",
            route_type ? route_type : "unknown",
            input_irq, pic_irq, level ? "assert" : "deassert",
            xemu_xbe_bool_str(delivered),
            acpi_route, int_route, pirq_route,
            xemu_xbe_bool_str(xemu_xbe_irq_watch_matches(pic_irq)),
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);
}

void xemu_xbe_boot_trace_observe_xbox_pm_sci(const char *reason,
                                             int sci_level,
                                             uint16_t pm1_sts,
                                             uint16_t pm1_en,
                                             uint8_t gpe0_sts,
                                             uint8_t gpe0_en,
                                             int64_t overflow_time,
                                             bool timer_enabled)
{
    static uint64_t seq;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    uint16_t pm1_masked = pm1_sts & pm1_en;
    uint8_t gpe0_masked = gpe0_sts & gpe0_en;
    char timer_pump_fields[256];

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready()) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (!xemu_xbe_irq_trace_gate_allows(12, &wait_state)) {
        return;
    }

    limit = xemu_xbe_pic_irq_probe_limit();
    if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);

    fprintf(stderr,
            "BOOT_MARK b6 xbox-pm=sci-update context=%s"
            " seq=%" PRIu64
            " reason=%s"
            " sci_level=%s"
            " pm1_sts=0x%04" PRIx16
            " pm1_en=0x%04" PRIx16
            " pm1_masked=0x%04" PRIx16
            " gpe0_sts=0x%02x"
            " gpe0_en=0x%02x"
            " gpe0_masked=0x%02x"
            " overflow_time=%" PRId64
            " timer_enabled=%s"
            " watch=%s"
            "%s"
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x\n",
            xemu_xbe_boot_trace_context(), seq,
            reason ? reason : "unknown",
            sci_level ? "assert" : "deassert",
            pm1_sts, pm1_en, pm1_masked,
            (unsigned)gpe0_sts, (unsigned)gpe0_en,
            (unsigned)gpe0_masked,
            overflow_time, xemu_xbe_bool_str(timer_enabled),
            xemu_xbe_bool_str(xemu_xbe_irq_watch_matches(12)),
            xemu_xbe_tcg_timer_pump_trace_fields(
                timer_pump_fields, sizeof(timer_pump_fields)),
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);
}

void xemu_xbe_boot_trace_observe_xbox_pm_evt_write(const char *op,
                                                   uint32_t addr,
                                                   uint64_t value,
                                                   unsigned width,
                                                   uint16_t pm1_sts_before,
                                                   uint16_t pm1_sts_after,
                                                   uint16_t pm1_en_before,
                                                   uint16_t pm1_en_after,
                                                   int64_t overflow_before,
                                                   int64_t overflow_after,
                                                   bool timer_enabled_after)
{
    static uint64_t seq;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    char timer_pump_fields[256];

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready()) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (!xemu_xbe_irq_trace_gate_allows(12, &wait_state)) {
        return;
    }

    limit = xemu_xbe_pic_irq_probe_limit();
    if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);

    fprintf(stderr,
            "BOOT_MARK b6 xbox-pm=evt-write context=%s"
            " seq=%" PRIu64
            " op=%s"
            " addr=0x%02" PRIx32
            " value=0x%016" PRIx64
            " width=%u"
            " pm1_sts_before=0x%04" PRIx16
            " pm1_sts_after=0x%04" PRIx16
            " pm1_sts_delta=0x%04" PRIx16
            " pm1_en_before=0x%04" PRIx16
            " pm1_en_after=0x%04" PRIx16
            " pm1_en_delta=0x%04" PRIx16
            " pm1_masked_after=0x%04" PRIx16
            " overflow_before=%" PRId64
            " overflow_after=%" PRId64
            " timer_enabled_after=%s"
            " watch=%s"
            "%s"
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x\n",
            xemu_xbe_boot_trace_context(), seq, op ? op : "unknown",
            addr, value, width, pm1_sts_before, pm1_sts_after,
            (uint16_t)(pm1_sts_before ^ pm1_sts_after),
            pm1_en_before, pm1_en_after,
            (uint16_t)(pm1_en_before ^ pm1_en_after),
            (uint16_t)(pm1_sts_after & pm1_en_after),
            overflow_before, overflow_after,
            xemu_xbe_bool_str(timer_enabled_after),
            xemu_xbe_bool_str(xemu_xbe_irq_watch_matches(12)),
            xemu_xbe_tcg_timer_pump_trace_fields(
                timer_pump_fields, sizeof(timer_pump_fields)),
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);
}

void xemu_xbe_boot_trace_observe_xbox_pm_timer(const char *phase,
                                               int64_t virtual_now_ns,
                                               int64_t timer_ticks,
                                               int64_t overflow_time,
                                               uint16_t pm1_sts_before,
                                               uint16_t pm1_sts_after,
                                               uint16_t pm1_en)
{
    static uint64_t seq;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    char timer_pump_fields[256];

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready()) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (!xemu_xbe_irq_trace_gate_allows(12, &wait_state)) {
        return;
    }

    limit = xemu_xbe_pic_irq_probe_limit();
    if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);

    fprintf(stderr,
            "BOOT_MARK b6 xbox-pm=tmr-callback context=%s"
            " seq=%" PRIu64
            " phase=%s"
            " virtual_now_ns=%" PRId64
            " timer_ticks=%" PRId64
            " overflow_time=%" PRId64
            " pm1_sts_before=0x%04" PRIx16
            " pm1_sts_after=0x%04" PRIx16
            " pm1_en=0x%04" PRIx16
            " pm1_masked_after=0x%04" PRIx16
            " watch=%s"
            "%s"
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x\n",
            xemu_xbe_boot_trace_context(), seq, phase ? phase : "unknown",
            virtual_now_ns, timer_ticks, overflow_time, pm1_sts_before,
            pm1_sts_after, pm1_en, (uint16_t)(pm1_sts_after & pm1_en),
            xemu_xbe_bool_str(xemu_xbe_irq_watch_matches(12)),
            xemu_xbe_tcg_timer_pump_trace_fields(
                timer_pump_fields, sizeof(timer_pump_fields)),
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);
}

void xemu_xbe_boot_trace_observe_ac97_irq_update(int bm_index,
                                                 uint32_t sr_before,
                                                 uint32_t sr_after,
                                                 uint32_t cr,
                                                 uint32_t glob_sta_before,
                                                 uint32_t glob_sta_after,
                                                 uint32_t old_mask,
                                                 uint32_t new_mask,
                                                 int event,
                                                 int level,
                                                 uint8_t civ,
                                                 uint8_t lvi,
                                                 uint8_t piv,
                                                 uint16_t picb,
                                                 uint32_t bdbar,
                                                 uint32_t bd_addr,
                                                 uint32_t bd_ctl_len,
                                                 bool bd_valid)
{
    static uint64_t seq;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    char timer_pump_fields[256];

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready()) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (!xemu_xbe_irq_trace_gate_allows(6, &wait_state)) {
        return;
    }

    limit = xemu_xbe_pic_irq_probe_limit();
    if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);

    fprintf(stderr,
            "BOOT_MARK b6 ac97=irq-update context=%s"
            " seq=%" PRIu64
            " bm_index=%d"
            " sr_before=0x%04" PRIx32
            " sr_after=0x%04" PRIx32
            " old_mask=0x%04" PRIx32
            " new_mask=0x%04" PRIx32
            " cr=0x%02" PRIx32
            " glob_sta_before=0x%08" PRIx32
            " glob_sta_after=0x%08" PRIx32
            " event=%s"
            " level=%s"
            " civ=%u"
            " lvi=%u"
            " piv=%u"
            " picb=%u"
            " bdbar=0x%08" PRIx32
            " bd_addr=0x%08" PRIx32
            " bd_ctl_len=0x%08" PRIx32
            " bd_valid=%s"
            " watch=%s"
            "%s"
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x\n",
            xemu_xbe_boot_trace_context(), seq, bm_index,
            sr_before, sr_after, old_mask, new_mask, cr,
            glob_sta_before, glob_sta_after,
            xemu_xbe_bool_str(event != 0),
            level ? "assert" : "deassert",
            civ, lvi, piv, picb, bdbar, bd_addr, bd_ctl_len,
            xemu_xbe_bool_str(bd_valid),
            xemu_xbe_bool_str(xemu_xbe_irq_watch_matches(6)),
            xemu_xbe_tcg_timer_pump_trace_fields(
                timer_pump_fields, sizeof(timer_pump_fields)),
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);
}

void xemu_xbe_boot_trace_observe_ac97_bm_write(const char *reg,
                                               int bm_index,
                                               uint32_t addr,
                                               uint32_t value,
                                               unsigned width,
                                               uint32_t bdbar_before,
                                               uint32_t bdbar_after,
                                               uint8_t civ_before,
                                               uint8_t civ_after,
                                               uint8_t lvi_before,
                                               uint8_t lvi_after,
                                               uint8_t piv_before,
                                               uint8_t piv_after,
                                               uint16_t sr_before,
                                               uint16_t sr_after,
                                               uint8_t cr_before,
                                               uint8_t cr_after,
                                               uint16_t picb_before,
                                               uint16_t picb_after,
                                               uint32_t bd_addr_before,
                                               uint32_t bd_addr_after,
                                               uint32_t bd_ctl_len_before,
                                               uint32_t bd_ctl_len_after,
                                               bool bd_valid_before,
                                               bool bd_valid_after)
{
    static uint64_t seq;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    char timer_pump_fields[256];

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready()) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (!xemu_xbe_irq_trace_gate_allows(6, &wait_state)) {
        return;
    }

    limit = xemu_xbe_pic_irq_probe_limit();
    if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);

    fprintf(stderr,
            "BOOT_MARK b6 ac97=bm-write context=%s"
            " seq=%" PRIu64
            " reg=%s"
            " bm_index=%d"
            " addr=0x%02" PRIx32
            " value=0x%08" PRIx32
            " width=%u"
            " bdbar_before=0x%08" PRIx32
            " bdbar_after=0x%08" PRIx32
            " civ_before=%u"
            " civ_after=%u"
            " lvi_before=%u"
            " lvi_after=%u"
            " piv_before=%u"
            " piv_after=%u"
            " sr_before=0x%04" PRIx16
            " sr_after=0x%04" PRIx16
            " cr_before=0x%02x"
            " cr_after=0x%02x"
            " picb_before=%u"
            " picb_after=%u"
            " bd_addr_before=0x%08" PRIx32
            " bd_addr_after=0x%08" PRIx32
            " bd_ctl_len_before=0x%08" PRIx32
            " bd_ctl_len_after=0x%08" PRIx32
            " bd_valid_before=%s"
            " bd_valid_after=%s"
            " watch=%s"
            "%s"
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x\n",
            xemu_xbe_boot_trace_context(), seq, reg ? reg : "unknown",
            bm_index, addr, value, width, bdbar_before, bdbar_after,
            civ_before, civ_after, lvi_before, lvi_after, piv_before,
            piv_after, sr_before, sr_after, (unsigned)cr_before,
            (unsigned)cr_after,
            picb_before, picb_after, bd_addr_before, bd_addr_after,
            bd_ctl_len_before, bd_ctl_len_after,
            xemu_xbe_bool_str(bd_valid_before),
            xemu_xbe_bool_str(bd_valid_after),
            xemu_xbe_bool_str(xemu_xbe_irq_watch_matches(6)),
            xemu_xbe_tcg_timer_pump_trace_fields(
                timer_pump_fields, sizeof(timer_pump_fields)),
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);
}

void xemu_xbe_boot_trace_observe_ac97_callback(const char *callback,
                                               int bm_index,
                                               int free_or_avail,
                                               uint32_t sr,
                                               uint32_t cr,
                                               uint8_t civ,
                                               uint8_t lvi,
                                               uint8_t piv,
                                               uint16_t picb,
                                               uint32_t bdbar,
                                               uint32_t bd_addr,
                                               uint32_t bd_ctl_len,
                                               bool bd_valid)
{
    static uint64_t seq;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    char timer_pump_fields[256];

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready()) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (!xemu_xbe_irq_trace_gate_allows(6, &wait_state)) {
        return;
    }

    limit = xemu_xbe_pic_irq_probe_limit();
    if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);

    fprintf(stderr,
            "BOOT_MARK b6 ac97=callback context=%s"
            " seq=%" PRIu64
            " callback=%s"
            " bm_index=%d"
            " free_or_avail=%d"
            " sr=0x%04" PRIx32
            " cr=0x%02" PRIx32
            " civ=%u"
            " lvi=%u"
            " piv=%u"
            " picb=%u"
            " bdbar=0x%08" PRIx32
            " bd_addr=0x%08" PRIx32
            " bd_ctl_len=0x%08" PRIx32
            " bd_ioc=%s"
            " bd_bup=%s"
            " bd_valid=%s"
            " watch=%s"
            "%s"
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x\n",
            xemu_xbe_boot_trace_context(), seq, callback ? callback : "unknown",
            bm_index, free_or_avail, sr, cr, civ, lvi, piv, picb, bdbar,
            bd_addr, bd_ctl_len,
            xemu_xbe_bool_str((bd_ctl_len & (1U << 31)) != 0),
            xemu_xbe_bool_str((bd_ctl_len & (1U << 30)) != 0),
            xemu_xbe_bool_str(bd_valid),
            xemu_xbe_bool_str(xemu_xbe_irq_watch_matches(6)),
            xemu_xbe_tcg_timer_pump_trace_fields(
                timer_pump_fields, sizeof(timer_pump_fields)),
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);
}

void xemu_xbe_boot_trace_observe_ac97_transfer(int bm_index,
                                               const char *phase,
                                               int elapsed_remaining,
                                               int temp,
                                               int stop,
                                               uint32_t sr_before,
                                               uint32_t sr_after,
                                               uint32_t cr,
                                               uint8_t civ,
                                               uint8_t lvi,
                                               uint8_t piv,
                                               uint16_t picb,
                                               uint32_t bdbar,
                                               uint32_t bd_addr,
                                               uint32_t bd_ctl_len,
                                               bool bd_valid)
{
    static uint64_t seq;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    char timer_pump_fields[256];

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready()) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (!xemu_xbe_irq_trace_gate_allows(6, &wait_state)) {
        return;
    }

    limit = xemu_xbe_pic_irq_probe_limit();
    if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);

    fprintf(stderr,
            "BOOT_MARK b6 ac97=transfer context=%s"
            " seq=%" PRIu64
            " bm_index=%d"
            " phase=%s"
            " elapsed_remaining=%d"
            " temp=%d"
            " stop=%s"
            " sr_before=0x%04" PRIx32
            " sr_after=0x%04" PRIx32
            " cr=0x%02" PRIx32
            " civ=%u"
            " lvi=%u"
            " piv=%u"
            " picb=%u"
            " bdbar=0x%08" PRIx32
            " bd_addr=0x%08" PRIx32
            " bd_ctl_len=0x%08" PRIx32
            " bd_ioc=%s"
            " bd_bup=%s"
            " bd_valid=%s"
            " watch=%s"
            "%s"
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x\n",
            xemu_xbe_boot_trace_context(), seq, bm_index,
            phase ? phase : "unknown", elapsed_remaining, temp,
            xemu_xbe_bool_str(stop != 0), sr_before, sr_after, cr, civ, lvi,
            piv, picb, bdbar, bd_addr, bd_ctl_len,
            xemu_xbe_bool_str((bd_ctl_len & 0x80000000u) != 0),
            xemu_xbe_bool_str((bd_ctl_len & 0x40000000u) != 0),
            xemu_xbe_bool_str(bd_valid),
            xemu_xbe_bool_str(xemu_xbe_irq_watch_matches(6)),
            xemu_xbe_tcg_timer_pump_trace_fields(
                timer_pump_fields, sizeof(timer_pump_fields)),
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);
}

void xemu_xbe_boot_trace_observe_pic_irq_ack(int intno,
                                             int guest_irq,
                                             int master_irq,
                                             int slave_irq,
                                             uint32_t master_irr_before,
                                             uint32_t master_irr_after,
                                             uint32_t master_imr,
                                             uint32_t master_isr_before,
                                             uint32_t master_isr_after,
                                             uint32_t master_elcr,
                                             uint32_t slave_irr_before,
                                             uint32_t slave_irr_after,
                                             uint32_t slave_imr,
                                             uint32_t slave_isr_before,
                                             uint32_t slave_isr_after,
                                             uint32_t slave_elcr)
{
    static uint64_t seq;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready()) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (xemu_xbe_irq_after_pfifo_empty_only() &&
        !xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(&wait_state)) {
        return;
    }

    limit = xemu_xbe_pic_irq_probe_limit();
    if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);

    fprintf(stderr,
            "BOOT_MARK b6 pic=irq-ack context=%s"
            " seq=%" PRIu64
            " intno=0x%02x"
            " guest_irq=%d"
            " master_irq=%d"
            " slave_irq=%d"
            " master_irr_before=0x%02" PRIx32
            " master_irr_after=0x%02" PRIx32
            " master_imr=0x%02" PRIx32
            " master_isr_before=0x%02" PRIx32
            " master_isr_after=0x%02" PRIx32
            " master_elcr=0x%02" PRIx32
            " slave_irr_before=0x%02" PRIx32
            " slave_irr_after=0x%02" PRIx32
            " slave_imr=0x%02" PRIx32
            " slave_isr_before=0x%02" PRIx32
            " slave_isr_after=0x%02" PRIx32
            " slave_elcr=0x%02" PRIx32
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x\n",
            xemu_xbe_boot_trace_context(), seq,
            intno, guest_irq, master_irq, slave_irq,
            master_irr_before, master_irr_after, master_imr,
            master_isr_before, master_isr_after, master_elcr,
            slave_irr_before, slave_irr_after, slave_imr,
            slave_isr_before, slave_isr_after, slave_elcr,
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);
}

void xemu_xbe_boot_trace_observe_cpu_hard_irq(const char *op,
                                              uint32_t mask,
                                              uint32_t request_before,
                                              uint32_t request_after)
{
    static uint64_t seq;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready() ||
        request_before == request_after) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (xemu_xbe_irq_after_pfifo_empty_only() &&
        !xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(&wait_state)) {
        return;
    }

    limit = xemu_xbe_cpu_hard_irq_probe_limit();
    if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);

    fprintf(stderr,
            "BOOT_MARK b6 cpu=hard-irq context=%s"
            " seq=%" PRIu64
            " op=%s"
            " mask=0x%08" PRIx32
            " request_before=0x%08" PRIx32
            " request_after=0x%08" PRIx32
            " cpu_known=%s"
            " cpu_mode=%s"
            " cpl=%" PRIu32
            " eip=0x%08" PRIx64
            " cs=0x%04" PRIx32
            " esp=0x%08" PRIx64
            " eflags=0x%08" PRIx64
            " interrupts_enabled=%s"
            " irq_inhibited=%s"
            " cpu_exit_request=%s"
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x\n",
            xemu_xbe_boot_trace_context(), seq,
            op ? op : "unknown", mask, request_before, request_after,
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);
}

void xemu_xbe_boot_trace_observe_cpu_hard_irq_service(const char *phase,
                                                      int intno)
{
    static uint64_t seq;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_stack_probe stack_probe;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready()) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (xemu_xbe_irq_after_pfifo_empty_only() &&
        !xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(&wait_state)) {
        return;
    }

    limit = xemu_xbe_cpu_hard_irq_probe_limit();
    if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);
    xemu_xbe_capture_stack_probe(&exec_ctx, &stack_probe);

    fprintf(stderr,
            "BOOT_MARK b6 cpu=hard-irq-service context=%s"
            " seq=%" PRIu64
            " phase=%s"
            " intno=0x%02x"
            " cpu_known=%s"
            " cpu_mode=%s"
            " cpl=%" PRIu32
            " eip=0x%08" PRIx64
            " cs=0x%04" PRIx32
            " esp=0x%08" PRIx64
            " eflags=0x%08" PRIx64
            " hflags=0x%08" PRIx64
            " interrupts_enabled=%s"
            " irq_inhibited=%s"
            " cpu_interrupt_request=0x%08" PRIx32
            " pending_interrupt=%s"
            " cpu_exit_request=%s"
            " cpu_exception_index=%" PRId32
            " stack_read=%s"
            " stack_words=%u"
            " stack_hash=0x%016" PRIx64
            " stack0=0x%08" PRIx32
            " stack1=0x%08" PRIx32
            " stack2=0x%08" PRIx32
            " stack3=0x%08" PRIx32
            " stack4=0x%08" PRIx32
            " stack5=0x%08" PRIx32
            " stack6=0x%08" PRIx32
            " stack7=0x%08" PRIx32
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x\n",
            xemu_xbe_boot_trace_context(), seq,
            phase ? phase : "unknown", intno & 0xff,
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags, exec_ctx.hflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            exec_ctx.cpu_exception_index,
            xemu_xbe_bool_str(stack_probe.read_ok),
            XEMU_XBE_IRQ_STACK_WORDS,
            stack_probe.hash,
            stack_probe.words[0],
            stack_probe.words[1],
            stack_probe.words[2],
            stack_probe.words[3],
            stack_probe.words[4],
            stack_probe.words[5],
            stack_probe.words[6],
            stack_probe.words[7],
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);
}

bool xemu_xbe_boot_trace_defer_cpu_hard_irq_service(void)
{
    static uint64_t seq;
    const char *mode = xemu_xbe_tcg_timer_pump_mode();
    bool mode_defer_to_idle =
        !g_ascii_strcasecmp(
            mode, "pit-before-pfifo-transition-activity-defer-to-idle") ||
        xemu_xbe_tcg_timer_pump_mode_is_pfifo_pre_commit(mode);
    bool transition_seen;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    struct xemu_xbe_pfifo_activity_snapshot activity;
    uint32_t wait_dma_to_put = 0;
    uint32_t activity_dma_to_put = 0;
    bool wait_dma_to_put_known;
    bool activity_dma_to_put_known;

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready() ||
        (g_ascii_strcasecmp(mode,
                            "pit-before-pfifo-transition-activity-defer") &&
         g_ascii_strcasecmp(
             mode, "pit-before-pfifo-transition-activity-pre-tb-defer") &&
         !mode_defer_to_idle) ||
        xemu_xbe_tcg_timer_pump_trace.sequence == 0) {
        return false;
    }

    transition_seen = xemu_xbe_pfifo_stream_idle_transition_observed();
    if (!mode_defer_to_idle && transition_seen) {
        return false;
    }

    limit = xemu_xbe_cpu_hard_irq_probe_limit();
    xemu_xbe_capture_exec_context(&exec_ctx);
    if (mode_defer_to_idle &&
        transition_seen &&
        xemu_xbe_exec_context_is_idle_loop_serviceable(&exec_ctx, false)) {
        return false;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    xemu_xbe_boot_trace_latest_pfifo_activity(&activity);
    wait_dma_to_put_known =
        xemu_xbe_wait_state_dma_to_put(&wait_state, &wait_dma_to_put);
    activity_dma_to_put_known =
        xemu_xbe_pfifo_activity_dma_to_put(&activity, &activity_dma_to_put);

    if (limit > 0 && seq < (uint64_t)limit) {
        seq++;
        fprintf(stderr,
                "BOOT_MARK b6 cpu=hard-irq-defer context=%s"
                " seq=%" PRIu64
                " mode=%s"
                " transition_seen=%s"
                " cpu_known=%s"
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
                " cpu_exit_request=%s"
                " wait_present=%s"
                " wait_generation=%" PRIu64
                " wait_source=%s"
                " wait_op=%s"
                " wait_seq=%" PRIu64
                " wait_dma_get=0x%08" PRIx32
                " wait_dma_put=0x%08" PRIx32
                " wait_dma_to_put_known=%s"
                " wait_dma_to_put=%" PRIu32
                " wait_pfifo_known=%s"
                " activity_present=%s"
                " activity_generation=%" PRIu64
                " activity_source=%s"
                " activity_phase=%s"
                " activity_seq=%" PRIu64
                " activity_method=0x%04" PRIx32
                " activity_dma_get_reg=0x%08" PRIx32
                " activity_dma_put=0x%08" PRIx32
                " activity_dma_to_put_known=%s"
                " activity_dma_to_put=%" PRIu32
                " activity_active=%s"
                " activity_pfifo_lock_released=%s"
                " activity_pgraph_locked=%s"
                " activity_final_transition_candidate=%s\n",
                xemu_xbe_boot_trace_context(), seq, mode,
                xemu_xbe_bool_str(xemu_xbe_pfifo_stream_idle_transition_observed()),
                xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
                exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector,
                exec_ctx.esp, exec_ctx.computed_eflags,
                xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
                xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
                exec_ctx.cpu_interrupt_request,
                xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
                xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
                xemu_xbe_bool_str(wait_state.present),
                wait_state.generation,
                wait_state.present ? wait_state.state.source : "none",
                wait_state.present ? wait_state.state.op : "none",
                wait_state.present ? wait_state.state.seq : 0,
                wait_state.present ? wait_state.state.dma_get : 0,
                wait_state.present ? wait_state.state.dma_put : 0,
                xemu_xbe_bool_str(wait_dma_to_put_known), wait_dma_to_put,
                xemu_xbe_bool_str(wait_state.present &&
                                  wait_state.state.pfifo_known),
                xemu_xbe_bool_str(activity.present), activity.generation,
                activity.present ? activity.state.source : "none",
                activity.present ? activity.state.phase : "none",
                activity.present ? activity.state.seq : 0,
                activity.present ? activity.state.method : 0,
                activity.present ? activity.state.dma_get_reg : 0,
                activity.present ? activity.state.dma_put : 0,
                xemu_xbe_bool_str(activity_dma_to_put_known),
                activity_dma_to_put,
                xemu_xbe_bool_str(activity.present && activity.state.active),
                xemu_xbe_bool_str(activity.present &&
                                  activity.state.pfifo_lock_released),
                xemu_xbe_bool_str(activity.present &&
                                  activity.state.pgraph_locked),
                xemu_xbe_bool_str(activity.present &&
                                  activity.state.final_transition_candidate));
    }

    return true;
}

void xemu_xbe_boot_trace_observe_iret(const char *phase,
                                      int shift,
                                      int next_eip)
{
    static uint64_t seq;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_stack_probe stack_probe;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready()) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (xemu_xbe_irq_after_pfifo_empty_only() &&
        !xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(&wait_state)) {
        return;
    }

    limit = xemu_xbe_iret_probe_limit();
    if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);
    xemu_xbe_capture_stack_probe(&exec_ctx, &stack_probe);

    fprintf(stderr,
            "BOOT_MARK b6 cpu=iret context=%s"
            " seq=%" PRIu64
            " phase=%s"
            " shift=%d"
            " next_eip=0x%08x"
            " cpu_known=%s"
            " cpu_mode=%s"
            " cpl=%" PRIu32
            " eip=0x%08" PRIx64
            " cs=0x%04" PRIx32
            " esp=0x%08" PRIx64
            " eflags=0x%08" PRIx64
            " hflags=0x%08" PRIx64
            " interrupts_enabled=%s"
            " irq_inhibited=%s"
            " cpu_interrupt_request=0x%08" PRIx32
            " pending_interrupt=%s"
            " cpu_exit_request=%s"
            " cpu_exception_index=%" PRId32
            " stack_read=%s"
            " stack_words=%u"
            " stack_hash=0x%016" PRIx64
            " stack0=0x%08" PRIx32
            " stack1=0x%08" PRIx32
            " stack2=0x%08" PRIx32
            " stack3=0x%08" PRIx32
            " stack4=0x%08" PRIx32
            " stack5=0x%08" PRIx32
            " stack6=0x%08" PRIx32
            " stack7=0x%08" PRIx32
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x\n",
            xemu_xbe_boot_trace_context(), seq,
            phase ? phase : "unknown", shift, next_eip,
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags, exec_ctx.hflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            exec_ctx.cpu_exception_index,
            xemu_xbe_bool_str(stack_probe.read_ok),
            XEMU_XBE_IRQ_STACK_WORDS,
            stack_probe.hash,
            stack_probe.words[0],
            stack_probe.words[1],
            stack_probe.words[2],
            stack_probe.words[3],
            stack_probe.words[4],
            stack_probe.words[5],
            stack_probe.words[6],
            stack_probe.words[7],
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);
}

void xemu_xbe_boot_trace_observe_pit_irq_timer(int64_t current_time,
                                               int64_t expire_time,
                                               int irq_level,
                                               int mode,
                                               int gate,
                                               int count,
                                               int64_t count_load_time,
                                               int64_t next_transition_time)
{
    static uint64_t seq;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready()) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    if (xemu_xbe_irq_after_pfifo_empty_only() &&
        !xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty(&wait_state)) {
        return;
    }

    limit = xemu_xbe_pit_irq_probe_limit();
    if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);

    fprintf(stderr,
            "BOOT_MARK b6 pit=irq-timer context=%s"
            " seq=%" PRIu64
            " current_time=%" PRId64
            " expire_time=%" PRId64
            " irq_level=%d"
            " mode=%d"
            " gate=%d"
            " count=%d"
            " count_load_time=%" PRId64
            " next_transition_time=%" PRId64
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x\n",
            xemu_xbe_boot_trace_context(), seq,
            current_time, expire_time, irq_level, mode, gate, count,
            count_load_time, next_transition_time,
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);
}

void xemu_xbe_boot_trace_observe_main_loop_timers(
    const char *source,
    int64_t timeout_ns,
    int poll_ret,
    int64_t virtual_now_before,
    int64_t virtual_deadline_before,
    bool virtual_has_timers_before,
    bool virtual_expired_before,
    bool timers_progress,
    int64_t virtual_now_after,
    int64_t virtual_deadline_after,
    bool virtual_has_timers_after,
    bool virtual_expired_after)
{
    static uint64_t seq;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    uint64_t memory_watch_phys;
    uint32_t memory_watch_value;
    bool memory_watch_value_read;

    if (!xemu_xbe_boot_trace_enabled() ||
        !xemu_xbe_boot_trace_entry_ready()) {
        return;
    }
    if (!xemu_xbe_main_loop_timer_source_is_browser_diagnostic(source) &&
        !xemu_xbe_boot_trace_main_loop_timer_pump_ready()) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    limit = xemu_xbe_main_loop_timer_probe_limit();
    if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);
    memory_watch_value_read = xemu_xbe_boot_trace_memory_watch_sample(
        &memory_watch_phys, &memory_watch_value);

    fprintf(stderr,
            "BOOT_MARK b6 main-loop=timers context=%s"
            " source=%s"
            " seq=%" PRIu64
            " timeout_ns=%" PRId64
            " poll_ret=%d"
            " timer_progress=%s"
            " virtual_now_before=%" PRId64
            " virtual_deadline_before=%" PRId64
            " virtual_has_timers_before=%s"
            " virtual_expired_before=%s"
            " virtual_now_after=%" PRId64
            " virtual_deadline_after=%" PRId64
            " virtual_has_timers_after=%s"
            " virtual_expired_after=%s"
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " memory_watch_phys=0x%08" PRIx64
            " memory_watch_value_read=%s"
            " memory_watch_value=0x%08" PRIx32
            " stream_idle=%s"
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x\n",
            xemu_xbe_boot_trace_context(),
            source && source[0] ? source : "unknown",
            seq, timeout_ns, poll_ret,
            xemu_xbe_bool_str(timers_progress),
            virtual_now_before, virtual_deadline_before,
            xemu_xbe_bool_str(virtual_has_timers_before),
            xemu_xbe_bool_str(virtual_expired_before),
            virtual_now_after, virtual_deadline_after,
            xemu_xbe_bool_str(virtual_has_timers_after),
            xemu_xbe_bool_str(virtual_expired_after),
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            memory_watch_phys,
            xemu_xbe_bool_str(memory_watch_value_read),
            memory_watch_value,
            xemu_xbe_bool_str(xemu_xbe_nv2a_wait_is_stream_idle(&wait_state)),
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);
}

void xemu_xbe_boot_trace_observe_browser_timer_opportunity(
    const char *source,
    bool ready,
    uint64_t progress_events,
    int64_t progress_limit,
    int64_t virtual_now,
    int64_t virtual_deadline,
    bool virtual_has_timers,
    bool virtual_expired)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    static uint64_t seq;
    int64_t limit;
    int64_t virtual_deadline_delta = -1;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    uint32_t wait_dma_to_put = 0;
    bool wait_dma_to_put_known;
    uint64_t memory_watch_phys;
    uint32_t memory_watch_value;
    bool memory_watch_value_read;
    bool entry_ready;
    const char *reason;
    const char *pfifo_empty_blocker;

    if (!xemu_xbe_boot_trace_enabled()) {
        return;
    }

    entry_ready = xemu_xbe_boot_trace_entry_ready();
    limit = xemu_xbe_timer_opportunity_probe_limit();
    if (!entry_ready || limit <= 0 || seq >= (uint64_t)limit) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    xemu_xbe_capture_exec_context(&exec_ctx);
    wait_dma_to_put_known =
        xemu_xbe_wait_state_dma_to_put(&wait_state, &wait_dma_to_put);
    memory_watch_value_read = xemu_xbe_boot_trace_memory_watch_sample(
        &memory_watch_phys, &memory_watch_value);

    reason = ready ? "ready" :
        xemu_xbe_main_loop_timer_pump_block_reason(&wait_state);
    if (!reason) {
        reason = "ready-recompute-mismatch";
    }
    pfifo_empty_blocker =
        xemu_xbe_nv2a_wait_pfifo_empty_blocker(&wait_state);
    if (virtual_deadline >= 0) {
        virtual_deadline_delta = virtual_deadline - virtual_now;
    }

    seq++;
    fprintf(stderr,
            "BOOT_MARK b6 headless=timer-opportunity context=%s"
            " seq=%" PRIu64
            " source=%s"
            " ready=%s"
            " reason=%s"
            " entry_ready=%s"
            " transition_seen=%s"
            " progress_events=%" PRIu64
            " progress_limit=%" PRId64
            " virtual_now=%" PRId64
            " virtual_deadline=%" PRId64
            " virtual_deadline_delta=%" PRId64
            " virtual_has_timers=%s"
            " virtual_expired=%s"
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " memory_watch_phys=0x%08" PRIx64
            " memory_watch_value_read=%s"
            " memory_watch_value=0x%08" PRIx32
            " stream_idle=%s"
            " wait_present=%s"
            " wait_generation=%" PRIu64
            " wait_source=%s"
            " wait_op=%s"
            " pfifo_empty_blocker=%s"
            " wait_seq=%" PRIu64
            " wait_dma_get=0x%08" PRIx32
            " wait_dma_put=0x%08" PRIx32
            " wait_dma_to_put_known=%s"
            " wait_dma_to_put=%" PRIu32
            " wait_pfifo_known=%s"
            " wait_fifo_access=%s"
            " wait_pmc_pending=0x%08" PRIx32
            " wait_pmc_enabled=0x%08" PRIx32
            " wait_pfifo_pending=0x%08" PRIx32
            " wait_pfifo_enabled=0x%08" PRIx32
            " wait_pcrtc_pending=0x%08" PRIx32
            " wait_pcrtc_enabled=0x%08" PRIx32
            " wait_pgraph_pending=0x%08" PRIx32
            " wait_pgraph_enabled=0x%08" PRIx32 "\n",
            xemu_xbe_boot_trace_context(), seq,
            source && source[0] ? source : "unknown",
            xemu_xbe_bool_str(ready), reason,
            xemu_xbe_bool_str(entry_ready),
            xemu_xbe_bool_str(xemu_xbe_pfifo_stream_idle_transition_observed()),
            progress_events, progress_limit, virtual_now, virtual_deadline,
            virtual_deadline_delta,
            xemu_xbe_bool_str(virtual_has_timers),
            xemu_xbe_bool_str(virtual_expired),
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            memory_watch_phys,
            xemu_xbe_bool_str(memory_watch_value_read),
            memory_watch_value,
            xemu_xbe_bool_str(xemu_xbe_nv2a_wait_is_stream_idle(&wait_state)),
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            pfifo_empty_blocker,
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.dma_get : 0,
            wait_state.present ? wait_state.state.dma_put : 0,
            xemu_xbe_bool_str(wait_dma_to_put_known), wait_dma_to_put,
            xemu_xbe_bool_str(wait_state.present &&
                              wait_state.state.pfifo_known),
            xemu_xbe_bool_str(wait_state.present &&
                              wait_state.state.fifo_access),
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);
#else
    (void)source;
    (void)ready;
    (void)progress_events;
    (void)progress_limit;
    (void)virtual_now;
    (void)virtual_deadline;
    (void)virtual_has_timers;
    (void)virtual_expired;
#endif
}

void xemu_xbe_boot_trace_observe_tcg_timer_pump(
    uint64_t observed_tbs,
    int64_t interval_tbs,
    int64_t virtual_now_before,
    int64_t virtual_deadline_before,
    bool virtual_has_timers_before,
    bool virtual_expired_before,
    bool timers_progress,
    int64_t virtual_now_after,
    int64_t virtual_deadline_after,
    bool virtual_has_timers_after,
    bool virtual_expired_after)
{
    static uint64_t seq;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;

    limit = xemu_xbe_tcg_timer_pump_probe_limit();
    if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);
    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);

    fprintf(stderr,
            "BOOT_MARK b6 tcg=timer-pump context=%s"
            " seq=%" PRIu64
            " mode=%s"
            " observed_tbs=%" PRIu64
            " interval_tbs=%" PRId64
            " timer_progress=%s"
            " virtual_now_before=%" PRId64
            " virtual_deadline_before=%" PRId64
            " virtual_has_timers_before=%s"
            " virtual_expired_before=%s"
            " virtual_now_after=%" PRId64
            " virtual_deadline_after=%" PRId64
            " virtual_has_timers_after=%s"
            " virtual_expired_after=%s"
            " cpu_known=%s"
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
            " cpu_exit_request=%s"
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x\n",
            xemu_xbe_boot_trace_context(), seq, xemu_xbe_tcg_timer_pump_mode(),
            observed_tbs, interval_tbs, xemu_xbe_bool_str(timers_progress),
            virtual_now_before, virtual_deadline_before,
            xemu_xbe_bool_str(virtual_has_timers_before),
            xemu_xbe_bool_str(virtual_expired_before),
            virtual_now_after, virtual_deadline_after,
            xemu_xbe_bool_str(virtual_has_timers_after),
            xemu_xbe_bool_str(virtual_expired_after),
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0);

    xemu_xbe_pre_first_read_scheduler_note_timer_pump(timers_progress);
}

void xemu_xbe_boot_trace_observe_pfifo_pre_commit_timer_pump(
    const XemuXbeBootTracePfifoActivityState *state,
    uint64_t observed_pumps,
    int64_t interval_tbs,
    int64_t virtual_now_before,
    int64_t virtual_deadline_before,
    bool virtual_has_timers_before,
    bool virtual_expired_before,
    bool timers_progress,
    int64_t virtual_now_after,
    int64_t virtual_deadline_after,
    bool virtual_has_timers_after,
    bool virtual_expired_after)
{
    static uint64_t seq;
    int64_t limit;
    struct xemu_xbe_exec_context exec_ctx;

    if (!state) {
        return;
    }

    limit = xemu_xbe_tcg_timer_pump_probe_limit();
    if (seq >= (uint64_t)limit) {
        return;
    }

    seq++;
    xemu_xbe_capture_exec_context(&exec_ctx);
    fprintf(stderr,
            "BOOT_MARK b6 pfifo=pre-commit-timer-pump context=%s"
            " seq=%" PRIu64
            " mode=%s"
            " observed_pumps=%" PRIu64
            " interval_tbs=%" PRId64
            " timer_progress=%s"
            " virtual_now_before=%" PRId64
            " virtual_deadline_before=%" PRId64
            " virtual_has_timers_before=%s"
            " virtual_expired_before=%s"
            " virtual_now_after=%" PRId64
            " virtual_deadline_after=%" PRId64
            " virtual_has_timers_after=%s"
            " virtual_expired_after=%s"
            " activity_source=%s"
            " activity_phase=%s"
            " activity_seq=%" PRIu64
            " active=%s"
            " dma_get_reg=0x%08" PRIx32
            " dma_get_before=0x%08" PRIx32
            " dma_get_after=0x%08" PRIx32
            " dma_put=0x%08" PRIx32
            " final_transition_candidate=%s"
            " cpu_known=%s"
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
            " cpu_exit_request=%s\n",
            xemu_xbe_boot_trace_context(), seq, xemu_xbe_tcg_timer_pump_mode(),
            observed_pumps, interval_tbs, xemu_xbe_bool_str(timers_progress),
            virtual_now_before, virtual_deadline_before,
            xemu_xbe_bool_str(virtual_has_timers_before),
            xemu_xbe_bool_str(virtual_expired_before),
            virtual_now_after, virtual_deadline_after,
            xemu_xbe_bool_str(virtual_has_timers_after),
            xemu_xbe_bool_str(virtual_expired_after),
            state->source ? state->source : "unknown",
            state->phase ? state->phase : "unknown",
            state->seq, xemu_xbe_bool_str(state->active),
            state->dma_get_reg, state->dma_get_before, state->dma_get_after,
            state->dma_put,
            xemu_xbe_bool_str(state->final_transition_candidate),
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request));
}

static const struct xbe_section_header *xemu_xbe_section_header_at(
    const struct xbe *xbe,
    uint32_t index);

static bool xemu_xbe_image_pc_in_executable_section(uint64_t image_pc,
                                                    uint32_t tb_size,
                                                    uint32_t *section_index,
                                                    uint32_t *section_flags,
                                                    uint32_t *section_start,
                                                    uint64_t *section_end)
{
    const struct xbe *xbe = xemu_get_xbe_info();
    uint32_t base;
    uint32_t sections;
    uint32_t section_headers_addr;
    uint64_t table_offset;
    uint64_t table_bytes;

    *section_index = UINT32_MAX;
    *section_flags = 0;
    *section_start = 0;
    *section_end = 0;

    if (!xbe || !xbe->headers || !xbe->header) {
        return false;
    }

    base = ldl_le_p(&xbe->header->m_base);
    sections = ldl_le_p(&xbe->header->m_sections);
    section_headers_addr = ldl_le_p(&xbe->header->m_section_headers_addr);
    if (!sections || section_headers_addr < base) {
        return false;
    }

    table_offset = (uint64_t)section_headers_addr - base;
    table_bytes = (uint64_t)sections * sizeof(struct xbe_section_header);
    if (table_offset > xbe->headers_len ||
        table_bytes > xbe->headers_len - table_offset) {
        return false;
    }

    for (uint32_t index = 0; index < sections; index++) {
        const struct xbe_section_header *section =
            xemu_xbe_section_header_at(xbe, index);
        uint32_t flags = ldl_le_p(&section->m_flags);
        uint32_t virtual_addr = ldl_le_p(&section->m_virtual_addr);
        uint32_t virtual_size = ldl_le_p(&section->m_virtual_size);
        uint64_t virtual_end = (uint64_t)virtual_addr + virtual_size;

        if (!(flags & XEMU_XBE_SECTION_FLAG_EXECUTABLE) || !virtual_size ||
            virtual_end <= virtual_addr) {
            continue;
        }
        if (!xemu_xbe_pc_range_overlaps(image_pc, tb_size,
                                        virtual_addr, virtual_size)) {
            continue;
        }

        *section_index = index;
        *section_flags = flags;
        *section_start = virtual_addr;
        *section_end = virtual_end;
        return true;
    }

    return false;
}

static void xemu_xbe_boot_trace_exec_section_miss(
    uint64_t pc,
    uint32_t tb_size,
    const char *address_mode,
    uint64_t image_pc,
    const struct xemu_xbe_pc_mapping *pc_mapping,
    const struct xemu_xbe_pc_mapping *image_mapping,
    const char *phys_match,
    const char *source)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    uint32_t section_index;
    uint32_t section_flags;
    uint32_t section_start;
    uint64_t section_end;
    const char *entry_relation;
    uint64_t entry_distance;
    uint8_t guest_phys_bytes[XEMU_XBE_EXEC_CODE_PROBE_BYTES];
    uint8_t image_phys_bytes[XEMU_XBE_EXEC_CODE_PROBE_BYTES];
    bool guest_phys_code_read = false;
    bool image_phys_code_read = false;
    uint64_t guest_phys_code_hash = 0;
    uint64_t image_phys_code_hash = 0;
    bool phys_code_hash_match = false;
    const char *phys_delta_direction = "unknown";
    uint64_t phys_delta = 0;

    if (obs->exec_section_miss_marked || obs->executed_marked ||
        !obs->loaded_marked || !obs->size) {
        return;
    }

    if (!address_mode ||
        strcmp(address_mode, "high-alias-mismatch") != 0) {
        return;
    }

    if (!xemu_xbe_image_pc_in_executable_section(image_pc, tb_size,
                                                 &section_index,
                                                 &section_flags,
                                                 &section_start,
                                                 &section_end)) {
        return;
    }

    if (pc_mapping && pc_mapping->mapped && image_mapping &&
        image_mapping->mapped) {
        if (image_mapping->phys_addr >= pc_mapping->phys_addr) {
            phys_delta = image_mapping->phys_addr - pc_mapping->phys_addr;
            phys_delta_direction = "image-minus-guest";
        } else {
            phys_delta = pc_mapping->phys_addr - image_mapping->phys_addr;
            phys_delta_direction = "guest-minus-image";
        }

        if (xemu_xbe_read_phys_probe_bytes(pc_mapping->phys_addr,
                                           guest_phys_bytes,
                                           sizeof(guest_phys_bytes))) {
            guest_phys_code_read = true;
            guest_phys_code_hash =
                xemu_xbe_fnv1a64(guest_phys_bytes,
                                  sizeof(guest_phys_bytes));
        }
        if (xemu_xbe_read_phys_probe_bytes(image_mapping->phys_addr,
                                           image_phys_bytes,
                                           sizeof(image_phys_bytes))) {
            image_phys_code_read = true;
            image_phys_code_hash =
                xemu_xbe_fnv1a64(image_phys_bytes,
                                  sizeof(image_phys_bytes));
        }
    }

    phys_code_hash_match = guest_phys_code_read && image_phys_code_read &&
                           guest_phys_code_hash == image_phys_code_hash;
    xemu_xbe_pc_relation_to_loaded_entry(image_pc, tb_size, &entry_relation,
                                         &entry_distance);

    obs->exec_section_miss_marked = true;
    fprintf(stderr,
            "BOOT_MARK b6 dashboard=xbe-exec-section-miss context=%s"
            " reason=high-alias-phys-mismatch"
            " entry_ready=%s"
            " entry=0x%08" PRIx32
            " entry_relation=%s"
            " entry_distance=%" PRIu64
            " guest_pc=0x%08" PRIx64
            " image_pc=0x%08" PRIx64
            " image_base=0x%08" PRIx32
            " image_size=%" PRIu32
            " tb_size=%" PRIu32
            " address_mode=%s"
            " guest_phys_mapped=%s"
            " guest_phys=0x%08" PRIx64
            " image_phys_mapped=%s"
            " image_phys=0x%08" PRIx64
            " phys_match=%s"
            " phys_delta_direction=%s"
            " phys_delta=0x%08" PRIx64
            " section_index=%" PRIu32
            " section_flags=0x%08" PRIx32
            " section_virtual_addr=0x%08" PRIx32
            " section_virtual_end=0x%08" PRIx64
            " guest_phys_code_read=%s"
            " guest_phys_code_hash=0x%016" PRIx64
            " image_phys_code_read=%s"
            " image_phys_code_hash=0x%016" PRIx64
            " phys_code_hash_match=%s"
            " source=%s\n",
            xemu_xbe_boot_trace_context(), xemu_xbe_bool_str(obs->entry_marked),
            obs->entry, entry_relation, entry_distance, pc, image_pc,
            obs->base, obs->size, tb_size, address_mode,
            xemu_xbe_bool_str(pc_mapping && pc_mapping->mapped),
            (pc_mapping && pc_mapping->mapped) ?
                (uint64_t)pc_mapping->phys_addr : 0,
            xemu_xbe_bool_str(image_mapping && image_mapping->mapped),
            (image_mapping && image_mapping->mapped) ?
                (uint64_t)image_mapping->phys_addr : 0,
            phys_match ? phys_match : "unknown",
            phys_delta_direction, phys_delta, section_index, section_flags,
            section_start, section_end,
            xemu_xbe_bool_str(guest_phys_code_read), guest_phys_code_hash,
            xemu_xbe_bool_str(image_phys_code_read), image_phys_code_hash,
            xemu_xbe_bool_str(phys_code_hash_match),
            source ? source : "pc-sample");
}

static bool xemu_xbe_boot_trace_mark_executed(uint64_t pc, uint32_t tb_size,
                                              const char *source)
{
    static bool started_emitted;
    static bool ended_emitted;
    const char *address_mode;
    const char *phys_match;
    uint64_t image_pc = 0;
    struct xemu_xbe_pc_mapping pc_mapping;
    struct xemu_xbe_pc_mapping image_mapping = { 0 };
    uint32_t section_index;
    uint32_t section_flags;
    uint32_t section_start;
    uint64_t section_end;

    xemu_call_chain_trace_once(&started_emitted, "started",
                               "xemu_xbe_boot_trace_mark_executed");

    if (!xemu_xbe_pc_overlaps_loaded_image(pc, tb_size, &address_mode,
                                           &image_pc, &pc_mapping,
                                           &image_mapping)) {
        phys_match = xemu_xbe_phys_match_status(address_mode, &pc_mapping,
                                                &image_mapping);
        xemu_xbe_boot_trace_exec_section_miss(pc, tb_size, address_mode,
                                              image_pc, &pc_mapping,
                                              &image_mapping, phys_match,
                                              source);
        xemu_call_chain_trace_once(&ended_emitted, "ended",
                                   "xemu_xbe_boot_trace_mark_executed");
        return false;
    }
    phys_match = xemu_xbe_phys_match_status(address_mode, &pc_mapping,
                                            &image_mapping);
    if (strcmp(phys_match, "yes") != 0 ||
        !xemu_xbe_image_pc_in_executable_section(image_pc, tb_size,
                                                 &section_index,
                                                 &section_flags,
                                                 &section_start,
                                                 &section_end)) {
        xemu_xbe_boot_trace_exec_section_miss(pc, tb_size, address_mode,
                                              image_pc, &pc_mapping,
                                              &image_mapping, phys_match,
                                              source);
        xemu_call_chain_trace_once(&ended_emitted, "ended",
                                   "xemu_xbe_boot_trace_mark_executed");
        return false;
    }

    xemu_xbe_loaded_observation.executed_marked = true;
    fprintf(stderr,
            "BOOT_MARK b6 dashboard=xbe-executed context=%s"
            " guest_pc=0x%08" PRIx64
            " image_pc=0x%08" PRIx64
            " image_base=0x%08" PRIx32
            " image_size=%" PRIu32
            " tb_size=%" PRIu32
            " address_mode=%s"
            " phys_match=%s"
            " guest_phys=0x%08" PRIx64
            " image_phys=0x%08" PRIx64
            " section_index=%" PRIu32
            " section_flags=0x%08" PRIx32
            " section_virtual_addr=0x%08" PRIx32
            " section_virtual_end=0x%08" PRIx64
            " source=%s\n",
            xemu_xbe_boot_trace_context(), pc, image_pc,
            xemu_xbe_loaded_observation.base,
            xemu_xbe_loaded_observation.size,
            tb_size, address_mode, phys_match,
            pc_mapping.mapped ? (uint64_t)pc_mapping.phys_addr : 0,
            image_mapping.mapped ? (uint64_t)image_mapping.phys_addr : 0,
            section_index, section_flags, section_start, section_end,
            source ? source : "pc-sample");

    xemu_call_chain_trace_once(&ended_emitted, "ended",
                               "xemu_xbe_boot_trace_mark_executed");
    return true;
}

static void xemu_xbe_boot_trace_executed_detector_proof(uint64_t pc,
                                                        uint32_t tb_size,
                                                        const char *subject,
                                                        const char *source)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    const char *address_mode;
    const char *phys_match;
    uint64_t image_pc = 0;
    struct xemu_xbe_pc_mapping pc_mapping;
    struct xemu_xbe_pc_mapping image_mapping = { 0 };
    uint32_t section_index;
    uint32_t section_flags;
    uint32_t section_start;
    uint64_t section_end;
    bool overlaps;
    bool executable_section;
    bool accepted;
    const char *reason = "accepted";
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_code_probe code_probe;

    if (obs->executed_detector_proof_marked || !obs->loaded_marked ||
        !obs->entry_marked || !obs->size) {
        return;
    }

    overlaps = xemu_xbe_pc_overlaps_loaded_image(pc, tb_size, &address_mode,
                                                 &image_pc, &pc_mapping,
                                                 &image_mapping);
    phys_match = xemu_xbe_phys_match_status(address_mode, &pc_mapping,
                                            &image_mapping);
    executable_section =
        xemu_xbe_image_pc_in_executable_section(image_pc, tb_size,
                                                &section_index,
                                                &section_flags,
                                                &section_start,
                                                &section_end);
    accepted = overlaps && strcmp(phys_match, "yes") == 0 &&
               executable_section;

    if (!overlaps) {
        reason = "no-loaded-image-overlap";
    } else if (strcmp(phys_match, "yes") != 0) {
        reason = "phys-match-not-yes";
    } else if (!executable_section) {
        reason = "not-executable-section";
    }

    xemu_xbe_capture_exec_context(&exec_ctx);
    xemu_xbe_capture_code_probe(pc, &exec_ctx, &code_probe);

    obs->executed_detector_proof_marked = true;
    fprintf(stderr,
            "BOOT_MARK b6 dashboard=xbe-executed-detector-proof context=%s"
            " result=%s"
            " reason=%s"
            " subject=%s"
            " guest_pc=0x%08" PRIx64
            " image_pc=0x%08" PRIx64
            " image_base=0x%08" PRIx32
            " image_size=%" PRIu32
            " tb_size=%" PRIu32
            " address_mode=%s"
            " overlaps_loaded_image=%s"
            " phys_match=%s"
            " guest_phys_mapped=%s"
            " guest_phys=0x%08" PRIx64
            " image_phys_mapped=%s"
            " image_phys=0x%08" PRIx64
            " executable_section=%s"
            " section_index=%" PRIu32
            " section_flags=0x%08" PRIx32
            " section_virtual_addr=0x%08" PRIx32
            " section_virtual_end=0x%08" PRIx64
            " code_read=%s"
            " code_hash=0x%016" PRIx64
            " opcode=0x%02" PRIx8
            " cpu_known=%s"
            " eip=0x%08" PRIx64
            " source=%s\n",
            xemu_xbe_boot_trace_context(),
            accepted ? "pass" : "fail", reason, subject ? subject : "pc",
            pc, image_pc, obs->base, obs->size, tb_size, address_mode,
            xemu_xbe_bool_str(overlaps), phys_match,
            xemu_xbe_bool_str(pc_mapping.mapped),
            pc_mapping.mapped ? (uint64_t)pc_mapping.phys_addr : 0,
            xemu_xbe_bool_str(image_mapping.mapped),
            image_mapping.mapped ? (uint64_t)image_mapping.phys_addr : 0,
            xemu_xbe_bool_str(executable_section), section_index,
            section_flags, section_start, section_end,
            xemu_xbe_bool_str(code_probe.read_ok), code_probe.hash,
            code_probe.opcode, xemu_xbe_bool_str(exec_ctx.cpu_known),
            exec_ctx.eip, source ? source : "detector-proof");
}

static const struct xbe_section_header *xemu_xbe_section_header_at(
    const struct xbe *xbe,
    uint32_t index)
{
    uint32_t base = ldl_le_p(&xbe->header->m_base);
    uint32_t section_headers_addr =
        ldl_le_p(&xbe->header->m_section_headers_addr);
    uint64_t table_offset = (uint64_t)section_headers_addr - base;

    return (const struct xbe_section_header *)
        (xbe->headers + table_offset +
         (uint64_t)index * sizeof(struct xbe_section_header));
}

static void xemu_xbe_boot_trace_section_map(const struct xbe *xbe,
                                            const char *context,
                                            const char *phase)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    uint32_t base;
    uint32_t sections;
    uint32_t section_headers_addr;
    uint64_t table_offset;
    uint64_t table_bytes;
    uint32_t emitted;
    uint32_t executable_sections = 0;
    int entry_section = -1;
    const char *invalid_reason = NULL;
    bool entry_ready_phase = phase && strcmp(phase, "entry-ready") == 0;

    if (entry_ready_phase) {
        if (!obs->entry_marked) {
            return;
        }
        if (obs->section_map_entry_ready_marked) {
            return;
        }
        obs->section_map_entry_ready_marked = true;
    } else {
        phase = "loaded";
        if (obs->section_map_loaded_marked) {
            return;
        }
        obs->section_map_loaded_marked = true;
    }

    if (!phase) {
        phase = "loaded";
    }

    if (!xbe || !xbe->headers || !xbe->header) {
        invalid_reason = "missing-xbe";
        base = obs->base;
        sections = 0;
        section_headers_addr = 0;
        table_offset = 0;
        table_bytes = 0;
        goto invalid;
    }

    base = ldl_le_p(&xbe->header->m_base);
    sections = ldl_le_p(&xbe->header->m_sections);
    section_headers_addr = ldl_le_p(&xbe->header->m_section_headers_addr);
    table_offset = (uint64_t)section_headers_addr - base;
    table_bytes = (uint64_t)sections * sizeof(struct xbe_section_header);

    if (!sections) {
        invalid_reason = "zero-sections";
        goto invalid;
    }
    if (section_headers_addr < base) {
        invalid_reason = "section-table-before-base";
        goto invalid;
    }
    if (table_offset > xbe->headers_len ||
        table_bytes > xbe->headers_len - table_offset) {
        invalid_reason = "section-table-outside-headers";
        goto invalid;
    }

    for (uint32_t index = 0; index < sections; index++) {
        const struct xbe_section_header *section =
            xemu_xbe_section_header_at(xbe, index);
        uint32_t flags = ldl_le_p(&section->m_flags);
        uint32_t virtual_addr = ldl_le_p(&section->m_virtual_addr);
        uint32_t virtual_size = ldl_le_p(&section->m_virtual_size);
        uint64_t virtual_end = (uint64_t)virtual_addr + virtual_size;

        if (flags & XEMU_XBE_SECTION_FLAG_EXECUTABLE) {
            executable_sections++;
        }
        if (entry_section < 0 && virtual_size &&
            obs->entry >= virtual_addr && obs->entry < virtual_end) {
            entry_section = (int)index;
        }
    }

    emitted = MIN(sections, XEMU_XBE_SECTION_MAP_DEFAULT_LIMIT);
    fprintf(stderr,
            "BOOT_MARK b6 dashboard=xbe-section-map context=%s"
            " status=ready"
            " phase=%s"
            " sections=%" PRIu32
            " emitted=%" PRIu32
            " executable_sections=%" PRIu32
            " entry_section=%d"
            " entry=0x%08" PRIx32
            " section_headers_addr=0x%08" PRIx32
            " headers_size=%" PRIu32
            " header_bytes=%" PRIu32
            " source=virtual-header\n",
            context, phase, sections, emitted, executable_sections, entry_section,
            obs->entry, section_headers_addr, obs->headers_size,
            xbe->headers_len);

    for (uint32_t index = 0; index < emitted; index++) {
        const struct xbe_section_header *section =
            xemu_xbe_section_header_at(xbe, index);
        uint32_t flags = ldl_le_p(&section->m_flags);
        uint32_t virtual_addr = ldl_le_p(&section->m_virtual_addr);
        uint32_t virtual_size = ldl_le_p(&section->m_virtual_size);
        uint32_t raw_addr = ldl_le_p(&section->m_raw_addr);
        uint32_t raw_size = ldl_le_p(&section->m_sizeof_raw);
        uint64_t virtual_end = (uint64_t)virtual_addr + virtual_size;
        bool contains_entry = virtual_size &&
            obs->entry >= virtual_addr && obs->entry < virtual_end;
        struct xemu_xbe_pc_mapping start_mapping =
            xemu_xbe_translate_pc(virtual_addr);
        struct xemu_xbe_pc_mapping entry_mapping =
            contains_entry ? xemu_xbe_translate_pc(obs->entry) :
                             (struct xemu_xbe_pc_mapping) { 0 };

        fprintf(stderr,
                "BOOT_MARK b6 dashboard=xbe-section context=%s"
                " phase=%s"
                " index=%" PRIu32
                " flags=0x%08" PRIx32
                " executable=%s"
                " writable=%s"
                " preload=%s"
                " virtual_addr=0x%08" PRIx32
                " virtual_size=%" PRIu32
                " virtual_end=0x%08" PRIx64
                " raw_addr=0x%08" PRIx32
                " raw_size=%" PRIu32
                " contains_entry=%s"
                " start_phys_mapped=%s"
                " start_phys=0x%08" PRIx64
                " entry_phys_mapped=%s"
                " entry_phys=0x%08" PRIx64
                " source=virtual-header\n",
                context, phase, index, flags,
                xemu_xbe_bool_str(flags & XEMU_XBE_SECTION_FLAG_EXECUTABLE),
                xemu_xbe_bool_str(flags & XEMU_XBE_SECTION_FLAG_WRITABLE),
                xemu_xbe_bool_str(flags & XEMU_XBE_SECTION_FLAG_PRELOAD),
                virtual_addr, virtual_size, virtual_end, raw_addr, raw_size,
                xemu_xbe_bool_str(contains_entry),
                xemu_xbe_bool_str(start_mapping.mapped),
                start_mapping.mapped ? (uint64_t)start_mapping.phys_addr : 0,
                xemu_xbe_bool_str(entry_mapping.mapped),
                entry_mapping.mapped ? (uint64_t)entry_mapping.phys_addr : 0);
    }

    return;

invalid:
    fprintf(stderr,
            "BOOT_MARK b6 dashboard=xbe-section-map context=%s"
            " status=invalid"
            " phase=%s"
            " reason=%s"
            " sections=%" PRIu32
            " section_headers_addr=0x%08" PRIx32
            " headers_size=%" PRIu32
            " header_bytes=%" PRIu32
            " source=virtual-header\n",
            context, phase, invalid_reason ? invalid_reason : "unknown",
            sections, section_headers_addr, obs->headers_size,
            xbe ? xbe->headers_len : 0);
}

static bool xemu_xbe_boot_trace_entry_probe(uint32_t entry,
                                            const char *context)
{
    const struct xemu_xbe_loaded_observation *obs =
        &xemu_xbe_loaded_observation;
    const char *entry_relation;
    const char *entry_address_mode;
    const char *entry_phys_match;
    uint64_t entry_distance;
    uint64_t entry_image_pc;
    struct xemu_xbe_pc_mapping entry_mapping;
    struct xemu_xbe_pc_mapping entry_image_mapping;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_code_probe entry_code_probe;

    xemu_xbe_pc_relation_to_loaded_image(entry, 1, &entry_relation,
                                         &entry_distance);
    xemu_xbe_pc_overlaps_loaded_image(entry, 1, &entry_address_mode,
                                      &entry_image_pc, &entry_mapping,
                                      &entry_image_mapping);
    entry_phys_match = xemu_xbe_phys_match_status(entry_address_mode,
                                                  &entry_mapping,
                                                  &entry_image_mapping);
    xemu_xbe_capture_exec_context(&exec_ctx);
    xemu_xbe_capture_code_probe(entry, &exec_ctx, &entry_code_probe);

    fprintf(stderr,
            "BOOT_MARK b6 dashboard=xbe-entry-probe context=%s"
            " status=%s"
            " guest_entry=0x%08" PRIx32
            " image_pc=0x%08" PRIx64
            " entry_offset=0x%08" PRIx64
            " image_base=0x%08" PRIx32
            " image_size=%" PRIu32
            " relation=%s"
            " distance=%" PRIu64
            " address_mode=%s"
            " entry_phys_mapped=%s"
            " entry_phys=0x%08" PRIx64
            " image_phys_mapped=%s"
            " image_phys=0x%08" PRIx64
            " phys_match=%s"
            " entry_code_read=%s"
            " entry_code_hash=0x%016" PRIx64
            " entry_opcode=0x%02" PRIx8
            " entry_opcode2_known=%s"
            " entry_opcode2=0x%02" PRIx8
            " entry_modrm_known=%s"
            " entry_modrm=0x%02" PRIx8
            " entry_branch_kind=%s"
            " entry_branch_target_known=%s"
            " entry_branch_target=0x%08" PRIx64
            " source=virtual-header\n",
            context, entry_code_probe.read_ok ? "ready" : "unreadable",
            entry, entry_image_pc,
            (entry >= obs->base) ? (uint64_t)(entry - obs->base) : 0,
            obs->base, obs->size, entry_relation, entry_distance,
            entry_address_mode,
            xemu_xbe_bool_str(entry_mapping.mapped),
            entry_mapping.mapped ? (uint64_t)entry_mapping.phys_addr : 0,
            xemu_xbe_bool_str(entry_image_mapping.mapped),
            entry_image_mapping.mapped ?
                (uint64_t)entry_image_mapping.phys_addr : 0,
            entry_phys_match,
            xemu_xbe_bool_str(entry_code_probe.read_ok),
            entry_code_probe.hash, entry_code_probe.opcode,
            xemu_xbe_bool_str(entry_code_probe.opcode2_known),
            entry_code_probe.opcode2,
            xemu_xbe_bool_str(entry_code_probe.modrm_known),
            entry_code_probe.modrm,
            entry_code_probe.branch.kind,
            xemu_xbe_bool_str(entry_code_probe.branch.target_known),
            entry_code_probe.branch.target);

    return entry_code_probe.read_ok;
}

static void xemu_xbe_boot_trace_alias_compare_probe(
    uint64_t observed_count,
    uint64_t pc,
    uint32_t tb_size,
    const char *relation,
    uint64_t distance,
    const char *address_mode,
    uint64_t image_pc,
    const struct xemu_xbe_pc_mapping *pc_mapping,
    const struct xemu_xbe_pc_mapping *image_mapping,
    const struct xemu_xbe_exec_context *exec_ctx,
    const struct xemu_xbe_code_probe *pc_code_probe,
    const char *source)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    struct xemu_xbe_code_probe image_code_probe;
    const char *phys_match;
    bool code_hash_match;
    int64_t limit;

    if (!address_mode ||
        (strcmp(address_mode, "high-alias") != 0 &&
         strcmp(address_mode, "high-alias-mismatch") != 0)) {
        return;
    }

    limit = xemu_xbe_alias_compare_probe_limit();
    if (limit == 0 ||
        obs->exec_alias_compare_probe_count >= (uint64_t)limit) {
        return;
    }

    xemu_xbe_capture_code_probe(image_pc, exec_ctx, &image_code_probe);
    code_hash_match = pc_code_probe && pc_code_probe->read_ok &&
                      image_code_probe.read_ok &&
                      pc_code_probe->hash == image_code_probe.hash;
    phys_match = xemu_xbe_phys_match_status(address_mode, pc_mapping,
                                            image_mapping);

    obs->exec_alias_compare_probe_count++;
    fprintf(stderr,
            "BOOT_MARK b6 dashboard=xbe-alias-compare context=%s"
            " observed_seq=%" PRIu64
            " alias_seq=%" PRIu64
            " entry_ready=%s"
            " entry=0x%08" PRIx32
            " guest_pc=0x%08" PRIx64
            " image_pc=0x%08" PRIx64
            " tb_size=%" PRIu32
            " image_base=0x%08" PRIx32
            " image_size=%" PRIu32
            " relation=%s"
            " distance=%" PRIu64
            " address_mode=%s"
            " guest_phys_mapped=%s"
            " guest_phys=0x%08" PRIx64
            " image_phys_mapped=%s"
            " image_phys=0x%08" PRIx64
            " phys_match=%s"
            " guest_code_read=%s"
            " guest_code_hash=0x%016" PRIx64
            " image_code_read=%s"
            " image_code_hash=0x%016" PRIx64
            " code_hash_match=%s"
            " cpu_known=%s"
            " cpu_mode=%s"
            " cpl=%" PRIu32
            " eip=0x%08" PRIx64
            " cs=0x%04" PRIx32
            " source=%s\n",
            xemu_xbe_boot_trace_context(), observed_count,
            obs->exec_alias_compare_probe_count,
            xemu_xbe_bool_str(obs->entry_marked), obs->entry,
            pc, image_pc, tb_size, obs->base, obs->size,
            relation ? relation : "unknown", distance, address_mode,
            xemu_xbe_bool_str(pc_mapping && pc_mapping->mapped),
            (pc_mapping && pc_mapping->mapped) ?
                (uint64_t)pc_mapping->phys_addr : 0,
            xemu_xbe_bool_str(image_mapping && image_mapping->mapped),
            (image_mapping && image_mapping->mapped) ?
                (uint64_t)image_mapping->phys_addr : 0,
            phys_match,
            xemu_xbe_bool_str(pc_code_probe && pc_code_probe->read_ok),
            (pc_code_probe && pc_code_probe->read_ok) ?
                pc_code_probe->hash : 0,
            xemu_xbe_bool_str(image_code_probe.read_ok),
            image_code_probe.read_ok ? image_code_probe.hash : 0,
            xemu_xbe_bool_str(code_hash_match),
            xemu_xbe_bool_str(exec_ctx && exec_ctx->cpu_known),
            exec_ctx ? exec_ctx->mode : "unknown",
            exec_ctx ? exec_ctx->cpl : 0,
            exec_ctx ? exec_ctx->eip : 0,
            exec_ctx ? exec_ctx->cs_selector : 0,
            source ? source : "tcg-tb");
}

static bool xemu_xbe_find_loaded_image_phys_match(
    hwaddr guest_phys,
    uint64_t *image_pc,
    struct xemu_xbe_pc_mapping *image_mapping)
{
    const struct xemu_xbe_loaded_observation *obs =
        &xemu_xbe_loaded_observation;
    uint64_t base = obs->base;
    uint64_t end = base + obs->size;
    uint64_t page_offset = guest_phys & ~TARGET_PAGE_MASK;
    uint64_t page;

    *image_pc = 0;
    *image_mapping = (struct xemu_xbe_pc_mapping) { 0 };

    if (!obs->loaded_marked || !obs->size || end <= base) {
        return false;
    }

    for (page = base & TARGET_PAGE_MASK; page < end; page += TARGET_PAGE_SIZE) {
        uint64_t candidate = page + page_offset;
        struct xemu_xbe_pc_mapping candidate_mapping;

        if (candidate < base || candidate >= end || candidate > UINT32_MAX) {
            continue;
        }

        candidate_mapping = xemu_xbe_translate_pc(candidate);
        if (!candidate_mapping.mapped) {
            continue;
        }

        if (candidate_mapping.phys_addr == guest_phys) {
            *image_pc = candidate;
            *image_mapping = candidate_mapping;
            return true;
        }
    }

    return false;
}

static void xemu_xbe_boot_trace_phys_compare_probe(
    uint64_t observed_count,
    uint64_t pc,
    uint32_t tb_size,
    const struct xemu_xbe_exec_context *exec_ctx,
    const struct xemu_xbe_code_probe *pc_code_probe,
    const char *source)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    struct xemu_xbe_pc_mapping pc_mapping;
    struct xemu_xbe_pc_mapping image_mapping = { 0 };
    struct xemu_xbe_code_probe image_code_probe;
    const char *guest_relation;
    const char *image_entry_relation;
    const char *result;
    const char *phys_match;
    uint64_t guest_distance;
    uint64_t image_entry_distance;
    uint64_t image_pc = 0;
    uint8_t guest_phys_bytes[XEMU_XBE_EXEC_CODE_PROBE_BYTES];
    bool guest_phys_code_read = false;
    uint64_t guest_phys_code_hash = 0;
    bool code_hash_match = false;
    bool match;
    int64_t limit;

    if (!obs->loaded_marked || obs->executed_marked || !obs->entry_marked ||
        !obs->size) {
        return;
    }

    limit = xemu_xbe_phys_compare_probe_limit();
    if (limit == 0 ||
        obs->exec_phys_compare_probe_count >= (uint64_t)limit) {
        return;
    }

    pc_mapping = xemu_xbe_translate_pc(pc);
    match = pc_mapping.mapped &&
            xemu_xbe_find_loaded_image_phys_match(pc_mapping.phys_addr,
                                                  &image_pc,
                                                  &image_mapping);
    result = match ? "match" : "no-match";
    phys_match = match ? "yes" : (pc_mapping.mapped ? "no" : "unknown");

    xemu_xbe_pc_relation_to_loaded_image(pc, tb_size, &guest_relation,
                                         &guest_distance);
    if (match) {
        xemu_xbe_pc_relation_to_loaded_entry(image_pc, tb_size,
                                             &image_entry_relation,
                                             &image_entry_distance);
        xemu_xbe_capture_code_probe(image_pc, exec_ctx, &image_code_probe);
    } else {
        image_entry_relation = "unknown";
        image_entry_distance = 0;
        image_code_probe = (struct xemu_xbe_code_probe) { 0 };
    }

    if (pc_mapping.mapped &&
        xemu_xbe_read_phys_probe_bytes(pc_mapping.phys_addr,
                                       guest_phys_bytes,
                                       sizeof(guest_phys_bytes))) {
        guest_phys_code_read = true;
        guest_phys_code_hash =
            xemu_xbe_fnv1a64(guest_phys_bytes, sizeof(guest_phys_bytes));
    }

    code_hash_match = match && guest_phys_code_read &&
                      image_code_probe.read_ok &&
                      guest_phys_code_hash == image_code_probe.hash;

    obs->exec_phys_compare_probe_count++;
    fprintf(stderr,
            "BOOT_MARK b6 dashboard=xbe-phys-compare context=%s"
            " result=%s"
            " observed_seq=%" PRIu64
            " phys_seq=%" PRIu64
            " entry_ready=%s"
            " entry=0x%08" PRIx32
            " guest_pc=0x%08" PRIx64
            " tb_size=%" PRIu32
            " image_base=0x%08" PRIx32
            " image_size=%" PRIu32
            " guest_relation=%s"
            " guest_distance=%" PRIu64
            " image_pc=0x%08" PRIx64
            " image_entry_relation=%s"
            " image_entry_distance=%" PRIu64
            " guest_phys_mapped=%s"
            " guest_phys=0x%08" PRIx64
            " image_phys_mapped=%s"
            " image_phys=0x%08" PRIx64
            " phys_match=%s"
            " pc_code_read=%s"
            " pc_code_hash=0x%016" PRIx64
            " guest_phys_code_read=%s"
            " guest_phys_code_hash=0x%016" PRIx64
            " image_code_read=%s"
            " image_code_hash=0x%016" PRIx64
            " code_hash_match=%s"
            " cpu_known=%s"
            " cpu_mode=%s"
            " cpl=%" PRIu32
            " eip=0x%08" PRIx64
            " cs=0x%04" PRIx32
            " source=%s\n",
            xemu_xbe_boot_trace_context(), result, observed_count,
            obs->exec_phys_compare_probe_count,
            xemu_xbe_bool_str(obs->entry_marked), obs->entry, pc, tb_size,
            obs->base, obs->size, guest_relation, guest_distance, image_pc,
            image_entry_relation, image_entry_distance,
            xemu_xbe_bool_str(pc_mapping.mapped),
            pc_mapping.mapped ? (uint64_t)pc_mapping.phys_addr : 0,
            xemu_xbe_bool_str(image_mapping.mapped),
            image_mapping.mapped ? (uint64_t)image_mapping.phys_addr : 0,
            phys_match,
            xemu_xbe_bool_str(pc_code_probe && pc_code_probe->read_ok),
            (pc_code_probe && pc_code_probe->read_ok) ? pc_code_probe->hash : 0,
            xemu_xbe_bool_str(guest_phys_code_read), guest_phys_code_hash,
            xemu_xbe_bool_str(image_code_probe.read_ok),
            image_code_probe.read_ok ? image_code_probe.hash : 0,
            xemu_xbe_bool_str(code_hash_match),
            xemu_xbe_bool_str(exec_ctx && exec_ctx->cpu_known),
            exec_ctx ? exec_ctx->mode : "unknown",
            exec_ctx ? exec_ctx->cpl : 0,
            exec_ctx ? exec_ctx->eip : 0,
            exec_ctx ? exec_ctx->cs_selector : 0,
            source ? source : "tcg-tb");
}

static void xemu_xbe_boot_trace_exec_probe(uint64_t pc, uint32_t tb_size,
                                           const char *source)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    uint64_t base = obs->base;
    uint64_t end = base + obs->size;
    uint64_t observed_count;
    uint64_t stride;
    int64_t limit;
    const char *relation;
    const char *address_mode;
    const char *phys_match;
    uint64_t distance;
    uint64_t image_pc;
    struct xemu_xbe_pc_mapping pc_mapping;
    struct xemu_xbe_pc_mapping image_mapping;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_code_probe code_probe;
    const char *branch_relation;
    const char *branch_entry_relation;
    const char *branch_address_mode;
    const char *branch_phys_match;
    uint64_t branch_distance;
    uint64_t branch_entry_distance;
    uint64_t branch_image_pc;
    struct xemu_xbe_pc_mapping branch_mapping;
    struct xemu_xbe_pc_mapping branch_image_mapping;

    if (!obs->loaded_marked || obs->executed_marked || !obs->size) {
        return;
    }

    if (!obs->entry_marked) {
        return;
    }

    limit = xemu_xbe_exec_probe_limit();
    if (limit == 0 || obs->exec_probe_count >= (uint64_t)limit) {
        return;
    }

    observed_count = ++obs->exec_probe_observed_count;
    stride = xemu_xbe_exec_probe_stride();
    if (observed_count > XEMU_XBE_EXEC_PROBE_INITIAL_SAMPLES &&
        observed_count % stride != 0) {
        return;
    }

    xemu_xbe_pc_relation_to_loaded_image(pc, tb_size, &relation, &distance);

    xemu_xbe_pc_overlaps_loaded_image(pc, tb_size, &address_mode, &image_pc,
                                      &pc_mapping, &image_mapping);
    phys_match = xemu_xbe_phys_match_status(address_mode, &pc_mapping,
                                            &image_mapping);
    xemu_xbe_capture_exec_context(&exec_ctx);
    xemu_xbe_capture_code_probe(pc, &exec_ctx, &code_probe);
    xemu_xbe_boot_trace_phys_compare_probe(observed_count, pc, tb_size,
                                           &exec_ctx, &code_probe, source);
    xemu_xbe_boot_trace_alias_compare_probe(observed_count, pc, tb_size,
                                            relation, distance, address_mode,
                                            image_pc, &pc_mapping,
                                            &image_mapping, &exec_ctx,
                                            &code_probe, source);
    if (code_probe.branch.target_known) {
        xemu_xbe_pc_relation_to_loaded_image(code_probe.branch.target, 1,
                                             &branch_relation,
                                             &branch_distance);
        xemu_xbe_pc_overlaps_loaded_image(code_probe.branch.target, 1,
                                          &branch_address_mode,
                                          &branch_image_pc,
                                          &branch_mapping,
                                          &branch_image_mapping);
        xemu_xbe_pc_relation_to_loaded_entry(branch_image_pc, 1,
                                             &branch_entry_relation,
                                             &branch_entry_distance);
        branch_phys_match = xemu_xbe_phys_match_status(branch_address_mode,
                                                       &branch_mapping,
                                                       &branch_image_mapping);
    } else {
        branch_relation = "unknown";
        branch_entry_relation = "unknown";
        branch_distance = 0;
        branch_entry_distance = 0;
        branch_address_mode = "unknown";
        branch_image_pc = 0;
        branch_mapping = (struct xemu_xbe_pc_mapping) { 0 };
        branch_image_mapping = (struct xemu_xbe_pc_mapping) { 0 };
        branch_phys_match = "unknown";
    }

    xemu_xbe_boot_trace_dispatch_probe(observed_count, pc, &exec_ctx, source);

    obs->exec_probe_count++;

    fprintf(stderr,
            "BOOT_MARK b6 dashboard=xbe-exec-probe context=%s"
            " observed_seq=%" PRIu64
            " observed_tbs=%" PRIu64
            " guest_pc=0x%08" PRIx64
            " image_pc=0x%08" PRIx64
            " tb_size=%" PRIu32
            " image_base=0x%08" PRIx64
            " image_end=0x%08" PRIx64
            " image_size=%" PRIu32
            " entry_ready=%s"
            " entry=0x%08" PRIx32
            " relation=%s"
            " distance=%" PRIu64
            " address_mode=%s"
            " guest_phys_mapped=%s"
            " guest_phys=0x%08" PRIx64
            " image_phys_mapped=%s"
            " image_phys=0x%08" PRIx64
            " phys_match=%s"
            " cpu_known=%s"
            " cpu_mode=%s"
            " cpl=%" PRIu32
            " eip=0x%08" PRIx64
            " cs=0x%04" PRIx32
            " cs_base=0x%08" PRIx64
            " ss=0x%04" PRIx32
            " ss_base=0x%08" PRIx64
            " esp=0x%08" PRIx64
            " ebp=0x%08" PRIx64
            " eax=0x%08" PRIx64
            " ebx=0x%08" PRIx64
            " ecx=0x%08" PRIx64
            " edx=0x%08" PRIx64
            " esi=0x%08" PRIx64
            " edi=0x%08" PRIx64
            " eflags=0x%08" PRIx64
            " hflags=0x%08" PRIx64
            " cr0=0x%08" PRIx64
            " cr3=0x%08" PRIx64
            " cr4=0x%08" PRIx64
            " efer=0x%08" PRIx64
            " pc_code_read=%s"
            " pc_code_hash=0x%016" PRIx64
            " pc_opcode=0x%02" PRIx8
            " pc_opcode2_known=%s"
            " pc_opcode2=0x%02" PRIx8
            " pc_modrm_known=%s"
            " pc_modrm=0x%02" PRIx8
            " branch_kind=%s"
            " branch_operand_addr_known=%s"
            " branch_operand_addr=0x%08" PRIx64
            " branch_target_known=%s"
            " branch_target=0x%08" PRIx64
            " branch_image_pc=0x%08" PRIx64
            " branch_relation=%s"
            " branch_distance=%" PRIu64
            " branch_entry_relation=%s"
            " branch_entry_distance=%" PRIu64
            " branch_address_mode=%s"
            " branch_phys_mapped=%s"
            " branch_phys=0x%08" PRIx64
            " branch_image_phys_mapped=%s"
            " branch_image_phys=0x%08" PRIx64
            " branch_phys_match=%s"
            " source=%s\n",
            xemu_xbe_boot_trace_context(), obs->exec_probe_count,
            observed_count, pc, image_pc, tb_size, base, end, obs->size,
            xemu_xbe_bool_str(obs->entry_marked), obs->entry,
            relation, distance, address_mode,
            xemu_xbe_bool_str(pc_mapping.mapped),
            pc_mapping.mapped ? (uint64_t)pc_mapping.phys_addr : 0,
            xemu_xbe_bool_str(image_mapping.mapped),
            image_mapping.mapped ? (uint64_t)image_mapping.phys_addr : 0,
            phys_match,
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip,
            exec_ctx.cs_selector, exec_ctx.cs_base,
            exec_ctx.ss_selector, exec_ctx.ss_base,
            exec_ctx.esp, exec_ctx.ebp, exec_ctx.eax, exec_ctx.ebx,
            exec_ctx.ecx, exec_ctx.edx, exec_ctx.esi, exec_ctx.edi,
            exec_ctx.eflags, exec_ctx.hflags,
            exec_ctx.cr0, exec_ctx.cr3, exec_ctx.cr4, exec_ctx.efer,
            xemu_xbe_bool_str(code_probe.read_ok), code_probe.hash,
            code_probe.opcode,
            xemu_xbe_bool_str(code_probe.opcode2_known), code_probe.opcode2,
            xemu_xbe_bool_str(code_probe.modrm_known), code_probe.modrm,
            code_probe.branch.kind,
            xemu_xbe_bool_str(code_probe.branch.operand_addr_known),
            code_probe.branch.operand_addr,
            xemu_xbe_bool_str(code_probe.branch.target_known),
            code_probe.branch.target, branch_image_pc,
            branch_relation, branch_distance,
            branch_entry_relation, branch_entry_distance,
            branch_address_mode,
            xemu_xbe_bool_str(branch_mapping.mapped),
            branch_mapping.mapped ? (uint64_t)branch_mapping.phys_addr : 0,
            xemu_xbe_bool_str(branch_image_mapping.mapped),
            branch_image_mapping.mapped ?
                (uint64_t)branch_image_mapping.phys_addr : 0,
            branch_phys_match,
            source ? source : "pc-sample");
}

void xemu_xbe_boot_trace_observe_exec(uint64_t guest_pc, uint32_t tb_size,
                                      const char *source)
{
    static bool started_emitted;
    static bool ended_emitted;

    xemu_call_chain_trace_once(&started_emitted, "started",
                               "xemu_xbe_boot_trace_observe_exec");

    if (!xemu_xbe_loaded_observation.loaded_marked ||
        xemu_xbe_loaded_observation.executed_marked) {
        const struct xemu_xbe_dma_header_observation *obs =
            &xemu_xbe_dma_observation;

        if (!xemu_xbe_loaded_observation.loaded_marked &&
            obs->present &&
            !xemu_xbe_dma_observation.preload_direct_exec_candidate_marked &&
            xemu_xbe_pc_range_overlaps(guest_pc, tb_size, obs->image_base,
                                       obs->image_size)) {
            xemu_xbe_dma_observation.preload_direct_exec_candidate_marked =
                true;
            fprintf(stderr,
                    "BOOT_MARK b6 dashboard=xbe-preload-direct-exec-candidate"
                    " context=%s"
                    " guest_pc=0x%08" PRIx64
                    " image_base=0x%08" PRIx32
                    " image_size=%" PRIu32
                    " headers_size=%" PRIu32
                    " entry=0x%08" PRIx32
                    " tb_size=%" PRIu32
                    " read_lba=%" PRId64
                    " dma_addr=0x%08" PRIx64
                    " source=%s\n",
                    xemu_xbe_boot_trace_context(), guest_pc, obs->image_base,
                    obs->image_size, obs->headers_size, obs->entry, tb_size,
                    obs->read_lba, obs->dma_addr,
                    source ? source : "tcg-tb");
        }
        xemu_call_chain_trace_once(&ended_emitted, "ended",
                                   "xemu_xbe_boot_trace_observe_exec");
        return;
    }

    if (!xemu_xbe_boot_trace_mark_executed(guest_pc, tb_size, source)) {
        xemu_xbe_boot_trace_exec_probe(guest_pc, tb_size, source);
    }
    xemu_call_chain_trace_once(&ended_emitted, "ended",
                               "xemu_xbe_boot_trace_observe_exec");
}

static bool xemu_xbe_power_of_two(uint64_t value)
{
    return value != 0 && (value & (value - 1)) == 0;
}

static struct xemu_xbe_exec_edge_observation *xemu_xbe_exec_edge_observe(
    uint64_t start_pc, uint64_t next_pc, uint32_t tb_size, int tb_exit)
{
    struct xemu_xbe_exec_edge_observation *free_slot = NULL;

    for (int i = 0; i < XEMU_XBE_EXEC_EDGE_MAX; i++) {
        struct xemu_xbe_exec_edge_observation *edge =
            &xemu_xbe_exec_edge_observations[i];

        if (!edge->used) {
            if (!free_slot) {
                free_slot = edge;
            }
            continue;
        }

        if (edge->start_pc == start_pc &&
            edge->next_pc == next_pc &&
            edge->tb_size == tb_size &&
            edge->tb_exit == tb_exit) {
            edge->hits++;
            return edge;
        }
    }

    if (!free_slot) {
        return NULL;
    }

    free_slot->used = true;
    free_slot->start_pc = start_pc;
    free_slot->next_pc = next_pc;
    free_slot->tb_size = tb_size;
    free_slot->tb_exit = tb_exit;
    free_slot->hits = 1;
    return free_slot;
}

static const char *xemu_xbe_entry_target_status(
    const struct xemu_xbe_target_classification *classification)
{
    if (strcmp(classification->phys_match, "yes") == 0) {
        return "near-phys-match";
    }
    if (strcmp(classification->phys_match, "no") == 0) {
        return "near-phys-mismatch";
    }
    if (strcmp(classification->phys_match, "not-applicable") == 0) {
        return "near-non-image-alias";
    }
    return "near-phys-unknown";
}

static void xemu_xbe_boot_trace_dispatch_probe(
    uint64_t observed_count,
    uint64_t pc,
    const struct xemu_xbe_exec_context *exec_ctx,
    const char *source)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    int64_t limit = xemu_xbe_dispatch_probe_limit();
    uint64_t window = xemu_xbe_entry_target_window();
    struct xemu_xbe_dispatch_candidate reg_candidate = {
        .label = "none",
        .index = -1,
    };
    struct xemu_xbe_dispatch_candidate stack_candidate = {
        .label = "none",
        .index = -1,
    };
    unsigned reg_phys_match_count = 0;
    unsigned reg_entry_near_count = 0;
    unsigned reg_high_alias_mismatch_count = 0;
    unsigned stack_phys_match_count = 0;
    unsigned stack_entry_near_count = 0;
    unsigned stack_high_alias_mismatch_count = 0;
    uint8_t stack_bytes[XEMU_XBE_DISPATCH_STACK_BYTES];
    bool stack_read = false;
    uint64_t stack_hash = 0;

    if (limit == 0 ||
        obs->exec_dispatch_probe_count >= (uint64_t)limit ||
        !exec_ctx->cpu_known) {
        return;
    }

    struct {
        const char *name;
        uint64_t value;
    } regs[] = {
        { "eax", exec_ctx->eax },
        { "ebx", exec_ctx->ebx },
        { "ecx", exec_ctx->ecx },
        { "edx", exec_ctx->edx },
        { "esi", exec_ctx->esi },
        { "edi", exec_ctx->edi },
        { "ebp", exec_ctx->ebp },
        { "esp", exec_ctx->esp },
    };

    for (size_t i = 0; i < G_N_ELEMENTS(regs); i++) {
        struct xemu_xbe_target_classification classification;

        xemu_xbe_classify_value(regs[i].value, &classification);
        if (strcmp(classification.phys_match, "yes") == 0) {
            reg_phys_match_count++;
        }
        if (xemu_xbe_classification_entry_near(&classification)) {
            reg_entry_near_count++;
        }
        if (xemu_xbe_classification_high_alias_mismatch(&classification)) {
            reg_high_alias_mismatch_count++;
        }
        xemu_xbe_consider_dispatch_candidate(&reg_candidate, regs[i].name,
                                             (int)i, regs[i].value,
                                             &classification);
    }

    if (exec_ctx->esp <= UINT32_MAX &&
        virt_dma_memory_read((vaddr)(uint32_t)exec_ctx->esp, stack_bytes,
                             sizeof(stack_bytes)) == sizeof(stack_bytes)) {
        stack_read = true;
        stack_hash = xemu_xbe_fnv1a64(stack_bytes, sizeof(stack_bytes));

        for (int i = 0; i < XEMU_XBE_DISPATCH_STACK_WORDS; i++) {
            uint32_t value = ldl_le_p(stack_bytes + i * sizeof(uint32_t));
            struct xemu_xbe_target_classification classification;

            xemu_xbe_classify_value(value, &classification);
            if (strcmp(classification.phys_match, "yes") == 0) {
                stack_phys_match_count++;
            }
            if (xemu_xbe_classification_entry_near(&classification)) {
                stack_entry_near_count++;
            }
            if (xemu_xbe_classification_high_alias_mismatch(
                    &classification)) {
                stack_high_alias_mismatch_count++;
            }
            xemu_xbe_consider_dispatch_candidate(&stack_candidate, "stack",
                                                 i, value, &classification);
        }
    }

    obs->exec_dispatch_probe_count++;
    fprintf(stderr,
            "BOOT_MARK b6 dashboard=xbe-dispatch-probe context=%s"
            " observed_seq=%" PRIu64
            " observed_tbs=%" PRIu64
            " guest_pc=0x%08" PRIx64
            " image_base=0x%08" PRIx32
            " image_size=%" PRIu32
            " headers_size=%" PRIu32
            " entry=0x%08" PRIx32
            " entry_ready=%s"
            " entry_window=%" PRIu64
            " cpu_known=%s"
            " cpu_mode=%s"
            " cpl=%" PRIu32
            " eip=0x%08" PRIx64
            " cs=0x%04" PRIx32
            " esp=0x%08" PRIx64
            " reg_phys_match_count=%u"
            " reg_entry_near_count=%u"
            " reg_high_alias_mismatch_count=%u"
            " reg_first_candidate=%s"
            " reg_first_index=%d"
            " reg_first_value=0x%08" PRIx64
            " reg_first_image_pc=0x%08" PRIx64
            " reg_first_offset=0x%08" PRIx64
            " reg_first_in_headers=%s"
            " reg_first_relation=%s"
            " reg_first_entry_relation=%s"
            " reg_first_entry_distance=%" PRIu64
            " reg_first_address_mode=%s"
            " reg_first_phys_match=%s"
            " reg_first_status=%s"
            " stack_read=%s"
            " stack_words=%u"
            " stack_hash=0x%016" PRIx64
            " stack_phys_match_count=%u"
            " stack_entry_near_count=%u"
            " stack_high_alias_mismatch_count=%u"
            " stack_first_index=%d"
            " stack_first_value=0x%08" PRIx64
            " stack_first_image_pc=0x%08" PRIx64
            " stack_first_offset=0x%08" PRIx64
            " stack_first_in_headers=%s"
            " stack_first_relation=%s"
            " stack_first_entry_relation=%s"
            " stack_first_entry_distance=%" PRIu64
            " stack_first_address_mode=%s"
            " stack_first_phys_match=%s"
            " stack_first_status=%s"
            " source=%s\n",
            xemu_xbe_boot_trace_context(), obs->exec_dispatch_probe_count,
            observed_count, pc, obs->base, obs->size, obs->headers_size,
            obs->entry, xemu_xbe_bool_str(obs->entry_marked), window,
            xemu_xbe_bool_str(exec_ctx->cpu_known), exec_ctx->mode,
            exec_ctx->cpl, exec_ctx->eip, exec_ctx->cs_selector,
            exec_ctx->esp,
            reg_phys_match_count, reg_entry_near_count,
            reg_high_alias_mismatch_count,
            reg_candidate.present ? reg_candidate.label : "none",
            reg_candidate.present ? reg_candidate.index : -1,
            reg_candidate.present ? reg_candidate.value : 0,
            reg_candidate.present ?
                reg_candidate.classification.image_pc : 0,
            reg_candidate.present ?
                xemu_xbe_image_offset(
                    reg_candidate.classification.image_pc) : 0,
            xemu_xbe_bool_str(reg_candidate.present &&
                              xemu_xbe_image_pc_in_headers(
                                  reg_candidate.classification.image_pc)),
            reg_candidate.present ?
                reg_candidate.classification.relation : "unknown",
            reg_candidate.present ?
                reg_candidate.classification.entry_relation : "unknown",
            reg_candidate.present ?
                reg_candidate.classification.entry_distance : 0,
            reg_candidate.present ?
                reg_candidate.classification.address_mode : "unknown",
            reg_candidate.present ?
                reg_candidate.classification.phys_match : "unknown",
            reg_candidate.present ?
                xemu_xbe_entry_target_status(&reg_candidate.classification) :
                "none",
            xemu_xbe_bool_str(stack_read), XEMU_XBE_DISPATCH_STACK_WORDS,
            stack_hash,
            stack_phys_match_count, stack_entry_near_count,
            stack_high_alias_mismatch_count,
            stack_candidate.present ? stack_candidate.index : -1,
            stack_candidate.present ? stack_candidate.value : 0,
            stack_candidate.present ?
                stack_candidate.classification.image_pc : 0,
            stack_candidate.present ?
                xemu_xbe_image_offset(
                    stack_candidate.classification.image_pc) : 0,
            xemu_xbe_bool_str(stack_candidate.present &&
                              xemu_xbe_image_pc_in_headers(
                                  stack_candidate.classification.image_pc)),
            stack_candidate.present ?
                stack_candidate.classification.relation : "unknown",
            stack_candidate.present ?
                stack_candidate.classification.entry_relation : "unknown",
            stack_candidate.present ?
                stack_candidate.classification.entry_distance : 0,
            stack_candidate.present ?
                stack_candidate.classification.address_mode : "unknown",
            stack_candidate.present ?
                stack_candidate.classification.phys_match : "unknown",
            stack_candidate.present ?
                xemu_xbe_entry_target_status(
                    &stack_candidate.classification) : "none",
            source ? source : "tcg-tb");
}

static const char *xemu_xbe_edge_loop_kind(
    const struct xemu_xbe_exec_edge_observation *edge)
{
    if (!edge) {
        return "unknown";
    }
    if (edge->next_pc == edge->start_pc) {
        return "self";
    }
    if (edge->next_pc == edge->start_pc + edge->tb_size) {
        return "fallthrough";
    }
    if (edge->next_pc < edge->start_pc) {
        return "backward";
    }
    return "forward";
}

static bool xemu_xbe_pc_is_kernel_alias(uint64_t pc)
{
    return pc <= UINT32_MAX && (pc & 0x80000000U);
}

static bool xemu_xbe_nv2a_wait_is_stream_idle(
    const struct xemu_xbe_nv2a_wait_snapshot *wait_state)
{
    return wait_state && wait_state->present &&
           wait_state->state.source &&
           wait_state->state.op &&
           !strcmp(wait_state->state.source, "pfifo-window") &&
           !strcmp(wait_state->state.op, "pusher-empty") &&
           wait_state->state.pfifo_known &&
           wait_state->state.dma_get == wait_state->state.dma_put;
}

static bool xemu_xbe_pc_is_timer_idle_loop(uint64_t pc)
{
    pc &= UINT64_C(0xffffffff);

    return pc == XEMU_XBE_TCG_TIMER_PUMP_IDLE_LOOP_PC_1 ||
           pc == XEMU_XBE_TCG_TIMER_PUMP_IDLE_LOOP_PC_2;
}

static void xemu_xbe_boot_trace_idle_before_pfifo_transition_probe(
    uint64_t observed_count,
    uint64_t start_pc,
    uint64_t next_pc,
    uint32_t tb_size,
    int tb_exit,
    const struct xemu_xbe_exec_edge_observation *edge,
    const char *source)
{
    static uint64_t count;
    int64_t limit = xemu_xbe_idle_before_pfifo_transition_probe_limit();
    struct xemu_xbe_nv2a_wait_snapshot wait_state;
    struct xemu_xbe_pfifo_activity_snapshot pfifo_activity;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_exec_edge_observation transition_edge;
    uint32_t pfifo_activity_dma_to_put_after = 0;

    if (limit == 0 ||
        count >= (uint64_t)limit ||
        xemu_xbe_pfifo_stream_idle_transition_observed() ||
        (!xemu_xbe_pc_is_timer_idle_loop(start_pc) &&
         !xemu_xbe_pc_is_timer_idle_loop(next_pc))) {
        return;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    xemu_xbe_boot_trace_latest_pfifo_activity(&pfifo_activity);
    if (!wait_state.present ||
        !wait_state.state.pfifo_known ||
        xemu_xbe_nv2a_wait_is_stream_idle(&wait_state) ||
        wait_state.state.dma_put == 0 ||
        wait_state.state.dma_get > wait_state.state.dma_put) {
        return;
    }
    if (pfifo_activity.present &&
        pfifo_activity.state.commit_range_known &&
        pfifo_activity.state.dma_get_after <= pfifo_activity.state.dma_put) {
        pfifo_activity_dma_to_put_after =
            pfifo_activity.state.dma_put - pfifo_activity.state.dma_get_after;
    }

    xemu_xbe_capture_exec_context(&exec_ctx);
    transition_edge = (struct xemu_xbe_exec_edge_observation) {
        .used = true,
        .start_pc = start_pc,
        .next_pc = next_pc,
        .tb_size = tb_size,
        .tb_exit = tb_exit,
        .hits = edge ? edge->hits : 1,
    };

    count++;
    fprintf(stderr,
            "BOOT_MARK b6 cpu=idle-before-pfifo-transition context=%s"
            " seq=%" PRIu64
            " observed_tbs=%" PRIu64
            " source=%s"
            " pfifo_transition_seen=%s"
            " loop_kind=%s"
            " edge_hits=%" PRIu64
            " start_pc=0x%08" PRIx64
            " next_pc=0x%08" PRIx64
            " tb_size=%" PRIu32
            " tb_exit=%d"
            " expected_next=0x%08" PRIx64
            " fallthrough_match=%s"
            " cpu_known=%s"
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
            " cpu_exception_index=%" PRId32
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_method=0x%04x"
            " nv2a_parameter=0x%08x"
            " nv2a_dma_get=0x%08x"
            " nv2a_dma_put=0x%08x"
            " nv2a_dma_to_put=%" PRIu32
            " nv2a_dma_state_method=0x%04x"
            " nv2a_dma_state_count=%u"
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x"
            " nv2a_fifo_access=%s"
            " nv2a_pfifo_halt=%s"
            " nv2a_pfifo_kick=%s"
            " nv2a_waiting_flip=%s"
            " nv2a_waiting_nop=%s"
            " nv2a_waiting_context=%s"
            " pfifo_activity_present=%s"
            " pfifo_activity_generation=%" PRIu64
            " pfifo_activity_source=%s"
            " pfifo_activity_phase=%s"
            " pfifo_activity_seq=%" PRIu64
            " pfifo_activity_active=%s"
            " pfifo_activity_method=0x%04x"
            " pfifo_activity_parameter=0x%08x"
            " pfifo_activity_dma_get_reg=0x%08x"
            " pfifo_activity_dma_get_local_known=%s"
            " pfifo_activity_dma_get_local=0x%08x"
            " pfifo_activity_commit_range_known=%s"
            " pfifo_activity_dma_get_before=0x%08x"
            " pfifo_activity_dma_get_after=0x%08x"
            " pfifo_activity_dma_put=0x%08x"
            " pfifo_activity_dma_to_put_after=%" PRIu32
            " pfifo_activity_available=%" PRIu64
            " pfifo_activity_processed=%" PRId64
            " pfifo_activity_pfifo_lock_released=%s"
            " pfifo_activity_pgraph_locked=%s"
            " pfifo_activity_final_transition_candidate=%s"
            " pfifo_activity_fifo_access=%s"
            " pfifo_activity_waiting_flip=%s"
            " pfifo_activity_waiting_nop=%s"
            " pfifo_activity_waiting_context=%s\n",
            xemu_xbe_boot_trace_context(), count, observed_count,
            source ? source : "tcg-tb-post",
            xemu_xbe_bool_str(xemu_xbe_pfifo_stream_idle_transition_observed()),
            xemu_xbe_edge_loop_kind(&transition_edge),
            transition_edge.hits,
            start_pc, next_pc, tb_size, tb_exit, start_pc + tb_size,
            xemu_xbe_bool_str(next_pc == start_pc + tb_size),
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip, exec_ctx.cs_selector, exec_ctx.esp,
            exec_ctx.computed_eflags,
            xemu_xbe_bool_str(exec_ctx.computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx.hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx.cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx.cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx.cpu_halted),
            xemu_xbe_bool_str(exec_ctx.cpu_exit_request),
            exec_ctx.cpu_exception_index,
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.state.source ? wait_state.state.source : "none",
            wait_state.state.op ? wait_state.state.op : "none",
            wait_state.state.seq,
            wait_state.state.method,
            wait_state.state.parameter,
            wait_state.state.dma_get,
            wait_state.state.dma_put,
            wait_state.state.dma_put - wait_state.state.dma_get,
            wait_state.state.dma_state_method,
            wait_state.state.dma_state_count,
            wait_state.state.pmc_pending,
            wait_state.state.pmc_enabled,
            wait_state.state.pfifo_pending,
            wait_state.state.pfifo_enabled,
            wait_state.state.pcrtc_pending,
            wait_state.state.pcrtc_enabled,
            wait_state.state.pgraph_pending,
            wait_state.state.pgraph_enabled,
            xemu_xbe_bool_str(wait_state.state.fifo_access),
            xemu_xbe_bool_str(wait_state.state.pfifo_halt),
            xemu_xbe_bool_str(wait_state.state.pfifo_kick),
            xemu_xbe_bool_str(wait_state.state.pgraph_waiting_flip),
            xemu_xbe_bool_str(wait_state.state.pgraph_waiting_nop),
            xemu_xbe_bool_str(wait_state.state.pgraph_waiting_context),
            xemu_xbe_bool_str(pfifo_activity.present),
            pfifo_activity.generation,
            pfifo_activity.present && pfifo_activity.state.source ?
                pfifo_activity.state.source : "none",
            pfifo_activity.present && pfifo_activity.state.phase ?
                pfifo_activity.state.phase : "none",
            pfifo_activity.present ? pfifo_activity.state.seq : 0,
            xemu_xbe_bool_str(pfifo_activity.present &&
                              pfifo_activity.state.active),
            pfifo_activity.present ? pfifo_activity.state.method : 0,
            pfifo_activity.present ? pfifo_activity.state.parameter : 0,
            pfifo_activity.present ? pfifo_activity.state.dma_get_reg : 0,
            xemu_xbe_bool_str(pfifo_activity.present &&
                              pfifo_activity.state.dma_get_local_known),
            pfifo_activity.present ? pfifo_activity.state.dma_get_local : 0,
            xemu_xbe_bool_str(pfifo_activity.present &&
                              pfifo_activity.state.commit_range_known),
            pfifo_activity.present ? pfifo_activity.state.dma_get_before : 0,
            pfifo_activity.present ? pfifo_activity.state.dma_get_after : 0,
            pfifo_activity.present ? pfifo_activity.state.dma_put : 0,
            pfifo_activity_dma_to_put_after,
            pfifo_activity.present ? pfifo_activity.state.available : 0,
            pfifo_activity.present ? pfifo_activity.state.processed : 0,
            xemu_xbe_bool_str(pfifo_activity.present &&
                              pfifo_activity.state.pfifo_lock_released),
            xemu_xbe_bool_str(pfifo_activity.present &&
                              pfifo_activity.state.pgraph_locked),
            xemu_xbe_bool_str(pfifo_activity.present &&
                              pfifo_activity.state.final_transition_candidate),
            xemu_xbe_bool_str(pfifo_activity.present &&
                              pfifo_activity.state.fifo_access),
            xemu_xbe_bool_str(pfifo_activity.present &&
                              pfifo_activity.state.pgraph_waiting_flip),
            xemu_xbe_bool_str(pfifo_activity.present &&
                              pfifo_activity.state.pgraph_waiting_nop),
            xemu_xbe_bool_str(pfifo_activity.present &&
                              pfifo_activity.state.pgraph_waiting_context));
}

static bool xemu_xbe_boot_trace_after_idle_kernel_loop_available(void)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    int64_t limit = xemu_xbe_kernel_loop_after_idle_probe_limit();
    struct xemu_xbe_nv2a_wait_snapshot wait_state;

    if (limit == 0 ||
        obs->exec_kernel_loop_after_idle_probe_count >= (uint64_t)limit) {
        return false;
    }

    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    return xemu_xbe_nv2a_wait_is_stream_idle(&wait_state);
}

static bool xemu_xbe_boot_trace_kernel_loop_probe(
    uint64_t observed_count,
    const char *probe,
    const struct xemu_xbe_exec_edge_observation *edge,
    const struct xemu_xbe_exec_context *exec_ctx,
    const struct xemu_xbe_code_probe *start_code_probe,
    const struct xemu_xbe_code_probe *next_code_probe,
    bool require_min_hits,
    bool require_stream_idle,
    const char *source)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    int64_t limit = xemu_xbe_kernel_loop_probe_limit();
    int64_t after_idle_limit = xemu_xbe_kernel_loop_after_idle_probe_limit();
    int64_t effective_limit;
    uint64_t *counter;
    uint64_t emitted_seq;
    uint64_t min_hits = xemu_xbe_kernel_loop_probe_min_hits();
    bool kernel_alias;
    bool same_page;
    bool stream_idle;
    struct xemu_xbe_nv2a_wait_snapshot wait_state;

    if (!edge || (limit == 0 && after_idle_limit == 0) ||
        (require_min_hits && edge->hits < min_hits) ||
        !exec_ctx->cpu_known) {
        return false;
    }

    kernel_alias = xemu_xbe_pc_is_kernel_alias(edge->start_pc) ||
                   xemu_xbe_pc_is_kernel_alias(edge->next_pc);
    if (!kernel_alias) {
        return false;
    }

    same_page = (edge->start_pc & TARGET_PAGE_MASK) ==
                (edge->next_pc & TARGET_PAGE_MASK);
    xemu_xbe_boot_trace_latest_nv2a_wait_state(&wait_state);
    stream_idle = xemu_xbe_nv2a_wait_is_stream_idle(&wait_state);
    if (require_stream_idle && !stream_idle) {
        return false;
    }

    effective_limit = stream_idle ? after_idle_limit : limit;
    counter = stream_idle ? &obs->exec_kernel_loop_after_idle_probe_count :
              &obs->exec_kernel_loop_probe_count;

    if (effective_limit == 0 || *counter >= (uint64_t)effective_limit) {
        return false;
    }

    (*counter)++;
    emitted_seq = *counter;
    fprintf(stderr,
            "BOOT_MARK b6 dashboard=kernel-loop-probe context=%s"
            " observed_seq=%" PRIu64
            " observed_tbs=%" PRIu64
            " probe=%s"
            " stream_idle=%s"
            " stream_idle_seq=%" PRIu64
            " edge_hits=%" PRIu64
            " min_hits=%" PRIu64
            " entry_ready=%s"
            " entry=0x%08" PRIx32
            " loop_kind=%s"
            " kernel_alias=%s"
            " same_page=%s"
            " start_pc=0x%08" PRIx64
            " next_pc=0x%08" PRIx64
            " tb_size=%" PRIu32
            " tb_exit=%d"
            " expected_next=0x%08" PRIx64
            " fallthrough_match=%s"
            " cpu_known=%s"
            " cpu_mode=%s"
            " cpl=%" PRIu32
            " eip=0x%08" PRIx64
            " cs=0x%04" PRIx32
            " esp=0x%08" PRIx64
            " eflags_raw=0x%08" PRIx64
            " eflags=0x%08" PRIx64
            " interrupts_enabled=%s"
            " flag_zf=%s"
            " flag_cf=%s"
            " flag_sf=%s"
            " flag_of=%s"
            " hflags=0x%08" PRIx64
            " irq_inhibited=%s"
            " cpu_interrupt_request=0x%08" PRIx32
            " pending_interrupt=%s"
            " cpu_halted=%s"
            " cpu_exit_request=%s"
            " cpu_exception_index=%" PRId32
            " nv2a_wait_present=%s"
            " nv2a_wait_generation=%" PRIu64
            " nv2a_wait_source=%s"
            " nv2a_wait_op=%s"
            " nv2a_wait_seq=%" PRIu64
            " nv2a_method=0x%04x"
            " nv2a_parameter=0x%08x"
            " nv2a_dma_get=0x%08x"
            " nv2a_dma_put=0x%08x"
            " nv2a_dma_state_method=0x%04x"
            " nv2a_dma_state_count=%u"
            " nv2a_pmc_pending=0x%08x"
            " nv2a_pmc_enabled=0x%08x"
            " nv2a_pfifo_known=%s"
            " nv2a_pfifo_pending=0x%08x"
            " nv2a_pfifo_enabled=0x%08x"
            " nv2a_pcrtc_pending=0x%08x"
            " nv2a_pcrtc_enabled=0x%08x"
            " nv2a_pgraph_pending=0x%08x"
            " nv2a_pgraph_enabled=0x%08x"
            " nv2a_fifo_access=%s"
            " nv2a_pfifo_halt=%s"
            " nv2a_pfifo_kick=%s"
            " nv2a_waiting_flip=%s"
            " nv2a_waiting_nop=%s"
            " nv2a_waiting_context=%s"
            " start_code_read=%s"
            " start_code_hash=0x%016" PRIx64
            " start_opcode=0x%02" PRIx8
            " start_opcode2_known=%s"
            " start_opcode2=0x%02" PRIx8
            " start_modrm_known=%s"
            " start_modrm=0x%02" PRIx8
            " start_branch_kind=%s"
            " start_branch_target_known=%s"
            " start_branch_target=0x%08" PRIx64
            " start_mem_kind=%s"
            " start_mem_width=%" PRIu32
            " start_mem_addr_known=%s"
            " start_mem_addr=0x%08" PRIx64
            " start_mem_region=%s"
            " start_mem_phys_mapped=%s"
            " start_mem_phys=0x%08" PRIx64
            " start_mem_value_read=%s"
            " start_mem_value=0x%08" PRIx32
            " next_code_read=%s"
            " next_code_hash=0x%016" PRIx64
            " next_opcode=0x%02" PRIx8
            " next_opcode2_known=%s"
            " next_opcode2=0x%02" PRIx8
            " next_modrm_known=%s"
            " next_modrm=0x%02" PRIx8
            " next_branch_kind=%s"
            " next_branch_target_known=%s"
            " next_branch_target=0x%08" PRIx64
            " next_mem_kind=%s"
            " next_mem_width=%" PRIu32
            " next_mem_addr_known=%s"
            " next_mem_addr=0x%08" PRIx64
            " next_mem_region=%s"
            " next_mem_phys_mapped=%s"
            " next_mem_phys=0x%08" PRIx64
            " next_mem_value_read=%s"
            " next_mem_value=0x%08" PRIx32
            " source=%s\n",
            xemu_xbe_boot_trace_context(),
            emitted_seq,
            observed_count, probe ? probe : "unknown",
            xemu_xbe_bool_str(stream_idle),
            stream_idle ? wait_state.state.seq : 0,
            edge->hits, min_hits,
            xemu_xbe_bool_str(obs->entry_marked), obs->entry,
            xemu_xbe_edge_loop_kind(edge),
            xemu_xbe_bool_str(kernel_alias),
            xemu_xbe_bool_str(same_page),
            edge->start_pc, edge->next_pc, edge->tb_size, edge->tb_exit,
            edge->start_pc + edge->tb_size,
            xemu_xbe_bool_str(edge->next_pc ==
                              edge->start_pc + edge->tb_size),
            xemu_xbe_bool_str(exec_ctx->cpu_known), exec_ctx->mode,
            exec_ctx->cpl, exec_ctx->eip, exec_ctx->cs_selector,
            exec_ctx->esp,
            exec_ctx->eflags, exec_ctx->computed_eflags,
            xemu_xbe_bool_str(exec_ctx->computed_eflags & IF_MASK),
            xemu_xbe_bool_str(exec_ctx->computed_eflags & CC_Z),
            xemu_xbe_bool_str(exec_ctx->computed_eflags & CC_C),
            xemu_xbe_bool_str(exec_ctx->computed_eflags & CC_S),
            xemu_xbe_bool_str(exec_ctx->computed_eflags & CC_O),
            exec_ctx->hflags,
            xemu_xbe_bool_str(exec_ctx->hflags & HF_INHIBIT_IRQ_MASK),
            exec_ctx->cpu_interrupt_request,
            xemu_xbe_bool_str(exec_ctx->cpu_interrupt_request != 0),
            xemu_xbe_bool_str(exec_ctx->cpu_halted),
            xemu_xbe_bool_str(exec_ctx->cpu_exit_request),
            exec_ctx->cpu_exception_index,
            xemu_xbe_bool_str(wait_state.present),
            wait_state.generation,
            wait_state.present ? wait_state.state.source : "none",
            wait_state.present ? wait_state.state.op : "none",
            wait_state.present ? wait_state.state.seq : 0,
            wait_state.present ? wait_state.state.method : 0,
            wait_state.present ? wait_state.state.parameter : 0,
            wait_state.present ? wait_state.state.dma_get : 0,
            wait_state.present ? wait_state.state.dma_put : 0,
            wait_state.present ? wait_state.state.dma_state_method : 0,
            wait_state.present ? wait_state.state.dma_state_count : 0,
            wait_state.present ? wait_state.state.pmc_pending : 0,
            wait_state.present ? wait_state.state.pmc_enabled : 0,
            xemu_xbe_bool_str(wait_state.present &&
                              wait_state.state.pfifo_known),
            wait_state.present ? wait_state.state.pfifo_pending : 0,
            wait_state.present ? wait_state.state.pfifo_enabled : 0,
            wait_state.present ? wait_state.state.pcrtc_pending : 0,
            wait_state.present ? wait_state.state.pcrtc_enabled : 0,
            wait_state.present ? wait_state.state.pgraph_pending : 0,
            wait_state.present ? wait_state.state.pgraph_enabled : 0,
            xemu_xbe_bool_str(wait_state.present &&
                              wait_state.state.fifo_access),
            xemu_xbe_bool_str(wait_state.present &&
                              wait_state.state.pfifo_halt),
            xemu_xbe_bool_str(wait_state.present &&
                              wait_state.state.pfifo_kick),
            xemu_xbe_bool_str(wait_state.present &&
                              wait_state.state.pgraph_waiting_flip),
            xemu_xbe_bool_str(wait_state.present &&
                              wait_state.state.pgraph_waiting_nop),
            xemu_xbe_bool_str(wait_state.present &&
                              wait_state.state.pgraph_waiting_context),
            xemu_xbe_bool_str(start_code_probe->read_ok),
            start_code_probe->hash, start_code_probe->opcode,
            xemu_xbe_bool_str(start_code_probe->opcode2_known),
            start_code_probe->opcode2,
            xemu_xbe_bool_str(start_code_probe->modrm_known),
            start_code_probe->modrm,
            start_code_probe->branch.kind,
            xemu_xbe_bool_str(start_code_probe->branch.target_known),
            start_code_probe->branch.target,
            start_code_probe->mem_kind,
            start_code_probe->mem_width,
            xemu_xbe_bool_str(start_code_probe->mem_addr_known),
            start_code_probe->mem_addr,
            start_code_probe->mem_region,
            xemu_xbe_bool_str(start_code_probe->mem_mapping.mapped),
            start_code_probe->mem_mapping.phys_addr,
            xemu_xbe_bool_str(start_code_probe->mem_value_read),
            start_code_probe->mem_value,
            xemu_xbe_bool_str(next_code_probe->read_ok),
            next_code_probe->hash, next_code_probe->opcode,
            xemu_xbe_bool_str(next_code_probe->opcode2_known),
            next_code_probe->opcode2,
            xemu_xbe_bool_str(next_code_probe->modrm_known),
            next_code_probe->modrm,
            next_code_probe->branch.kind,
            xemu_xbe_bool_str(next_code_probe->branch.target_known),
            next_code_probe->branch.target,
            next_code_probe->mem_kind,
            next_code_probe->mem_width,
            xemu_xbe_bool_str(next_code_probe->mem_addr_known),
            next_code_probe->mem_addr,
            next_code_probe->mem_region,
            xemu_xbe_bool_str(next_code_probe->mem_mapping.mapped),
            next_code_probe->mem_mapping.phys_addr,
            xemu_xbe_bool_str(next_code_probe->mem_value_read),
            next_code_probe->mem_value,
            source ? source : "tcg-tb-edge");
    return true;
}

static void xemu_xbe_boot_trace_entry_target_probe(
    const char *probe,
    uint64_t observed_count,
    uint64_t start_pc,
    uint64_t site_pc,
    const struct xemu_xbe_code_probe *code_probe,
    const struct xemu_xbe_target_classification *classification,
    const struct xemu_xbe_exec_context *exec_ctx,
    const char *source)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    int64_t limit = xemu_xbe_entry_target_limit();
    uint64_t window = xemu_xbe_entry_target_window();
    struct xemu_xbe_code_probe target_code_probe;
    struct xemu_xbe_code_probe target_image_code_probe;
    bool target_code_hash_match;

    if (limit == 0 ||
        obs->exec_entry_target_probe_count >= (uint64_t)limit ||
        !code_probe->branch.target_known ||
        strcmp(classification->entry_relation, "unknown") == 0 ||
        classification->entry_distance > window) {
        return;
    }

    xemu_xbe_capture_code_probe(code_probe->branch.target, exec_ctx,
                                &target_code_probe);
    xemu_xbe_capture_code_probe(classification->image_pc, exec_ctx,
                                &target_image_code_probe);
    target_code_hash_match = target_code_probe.read_ok &&
                             target_image_code_probe.read_ok &&
                             target_code_probe.hash ==
                             target_image_code_probe.hash;

    obs->exec_entry_target_probe_count++;
    fprintf(stderr,
            "BOOT_MARK b6 dashboard=xbe-entry-target-probe context=%s"
            " observed_seq=%" PRIu64
            " observed_tbs=%" PRIu64
            " probe=%s"
            " start_pc=0x%08" PRIx64
            " site_pc=0x%08" PRIx64
            " image_base=0x%08" PRIx64
            " entry=0x%08" PRIx32
            " entry_ready=%s"
            " window=%" PRIu64
            " branch_kind=%s"
            " branch_operand_addr_known=%s"
            " branch_operand_addr=0x%08" PRIx64
            " branch_target=0x%08" PRIx64
            " target_image_pc=0x%08" PRIx64
            " target_relation=%s"
            " target_distance=%" PRIu64
            " target_entry_relation=%s"
            " target_entry_distance=%" PRIu64
            " target_address_mode=%s"
            " target_phys_mapped=%s"
            " target_phys=0x%08" PRIx64
            " target_image_phys_mapped=%s"
            " target_image_phys=0x%08" PRIx64
            " target_phys_match=%s"
            " target_status=%s"
            " target_code_read=%s"
            " target_code_hash=0x%016" PRIx64
            " target_opcode=0x%02" PRIx8
            " target_image_code_read=%s"
            " target_image_code_hash=0x%016" PRIx64
            " target_image_opcode=0x%02" PRIx8
            " target_code_hash_match=%s"
            " cpu_known=%s"
            " cpu_mode=%s"
            " cpl=%" PRIu32
            " eip=0x%08" PRIx64
            " cs=0x%04" PRIx32
            " esp=0x%08" PRIx64
            " site_code_read=%s"
            " site_code_hash=0x%016" PRIx64
            " site_opcode=0x%02" PRIx8
            " site_modrm_known=%s"
            " site_modrm=0x%02" PRIx8
            " source=%s\n",
            xemu_xbe_boot_trace_context(),
            obs->exec_entry_target_probe_count, observed_count,
            probe ? probe : "unknown",
            start_pc, site_pc, (uint64_t)obs->base, obs->entry,
            xemu_xbe_bool_str(obs->entry_marked), window,
            code_probe->branch.kind,
            xemu_xbe_bool_str(code_probe->branch.operand_addr_known),
            code_probe->branch.operand_addr,
            code_probe->branch.target,
            classification->image_pc,
            classification->relation,
            classification->distance,
            classification->entry_relation,
            classification->entry_distance,
            classification->address_mode,
            xemu_xbe_bool_str(classification->mapping.mapped),
            classification->mapping.mapped ?
                (uint64_t)classification->mapping.phys_addr : 0,
            xemu_xbe_bool_str(classification->image_mapping.mapped),
            classification->image_mapping.mapped ?
                (uint64_t)classification->image_mapping.phys_addr : 0,
            classification->phys_match,
            xemu_xbe_entry_target_status(classification),
            xemu_xbe_bool_str(target_code_probe.read_ok),
            target_code_probe.read_ok ? target_code_probe.hash : 0,
            target_code_probe.opcode,
            xemu_xbe_bool_str(target_image_code_probe.read_ok),
            target_image_code_probe.read_ok ? target_image_code_probe.hash : 0,
            target_image_code_probe.opcode,
            xemu_xbe_bool_str(target_code_hash_match),
            xemu_xbe_bool_str(exec_ctx->cpu_known), exec_ctx->mode,
            exec_ctx->cpl, exec_ctx->eip,
            exec_ctx->cs_selector, exec_ctx->esp,
            xemu_xbe_bool_str(code_probe->read_ok), code_probe->hash,
            code_probe->opcode,
            xemu_xbe_bool_str(code_probe->modrm_known),
            code_probe->modrm,
            source ? source : "tcg-tb-post");
}

static void xemu_xbe_boot_trace_exec_edge_probe(
    uint64_t observed_count,
    const struct xemu_xbe_exec_edge_observation *edge,
    const char *source)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    int64_t limit = xemu_xbe_exec_edge_limit();
    const char *start_relation;
    const char *start_address_mode;
    const char *start_phys_match;
    uint64_t start_distance;
    uint64_t start_image_pc;
    struct xemu_xbe_pc_mapping start_mapping;
    struct xemu_xbe_pc_mapping start_image_mapping;
    const char *next_relation;
    const char *next_address_mode;
    const char *next_phys_match;
    uint64_t next_distance;
    uint64_t next_image_pc;
    struct xemu_xbe_pc_mapping next_mapping;
    struct xemu_xbe_pc_mapping next_image_mapping;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_code_probe start_code_probe;
    struct xemu_xbe_code_probe next_code_probe;
    struct xemu_xbe_target_classification next_branch_classification;

    if (!edge || limit == 0 ||
        obs->exec_edge_probe_count >= (uint64_t)limit ||
        !xemu_xbe_power_of_two(edge->hits)) {
        return;
    }

    xemu_xbe_pc_relation_to_loaded_image(edge->start_pc, edge->tb_size,
                                         &start_relation,
                                         &start_distance);
    xemu_xbe_pc_overlaps_loaded_image(edge->start_pc, edge->tb_size,
                                      &start_address_mode,
                                      &start_image_pc,
                                      &start_mapping,
                                      &start_image_mapping);
    start_phys_match = xemu_xbe_phys_match_status(start_address_mode,
                                                  &start_mapping,
                                                  &start_image_mapping);

    xemu_xbe_pc_relation_to_loaded_image(edge->next_pc, 1,
                                         &next_relation,
                                         &next_distance);
    xemu_xbe_pc_overlaps_loaded_image(edge->next_pc, 1,
                                      &next_address_mode,
                                      &next_image_pc,
                                      &next_mapping,
                                      &next_image_mapping);
    next_phys_match = xemu_xbe_phys_match_status(next_address_mode,
                                                 &next_mapping,
                                                 &next_image_mapping);

    xemu_xbe_capture_exec_context(&exec_ctx);
    xemu_xbe_capture_code_probe(edge->start_pc, &exec_ctx, &start_code_probe);
    xemu_xbe_capture_code_probe(edge->next_pc, &exec_ctx, &next_code_probe);
    xemu_xbe_boot_trace_alias_compare_probe(observed_count, edge->start_pc,
                                            edge->tb_size, start_relation,
                                            start_distance,
                                            start_address_mode,
                                            start_image_pc, &start_mapping,
                                            &start_image_mapping, &exec_ctx,
                                            &start_code_probe, source);
    xemu_xbe_boot_trace_alias_compare_probe(observed_count, edge->next_pc, 1,
                                            next_relation, next_distance,
                                            next_address_mode, next_image_pc,
                                            &next_mapping,
                                            &next_image_mapping, &exec_ctx,
                                            &next_code_probe, source);
    xemu_xbe_classify_branch_target(&next_code_probe.branch,
                                    &next_branch_classification);
    xemu_xbe_boot_trace_entry_target_probe("edge-next-branch",
                                           observed_count,
                                           edge->start_pc,
                                           edge->next_pc,
                                           &next_code_probe,
                                           &next_branch_classification,
                                           &exec_ctx,
                                           source);
    xemu_xbe_boot_trace_kernel_loop_probe(observed_count, "edge",
                                          edge, &exec_ctx,
                                          &start_code_probe,
                                          &next_code_probe, true, false,
                                          source);

    obs->exec_edge_probe_count++;
    fprintf(stderr,
            "BOOT_MARK b6 dashboard=xbe-exec-edge context=%s"
            " observed_seq=%" PRIu64
            " observed_tbs=%" PRIu64
            " edge_hits=%" PRIu64
            " entry_ready=%s"
            " entry=0x%08" PRIx32
            " start_pc=0x%08" PRIx64
            " start_image_pc=0x%08" PRIx64
            " tb_size=%" PRIu32
            " tb_exit=%d"
            " expected_next=0x%08" PRIx64
            " next_pc=0x%08" PRIx64
            " next_image_pc=0x%08" PRIx64
            " fallthrough_match=%s"
            " start_relation=%s"
            " start_distance=%" PRIu64
            " start_address_mode=%s"
            " start_phys_mapped=%s"
            " start_phys=0x%08" PRIx64
            " start_image_phys_mapped=%s"
            " start_image_phys=0x%08" PRIx64
            " start_phys_match=%s"
            " next_relation=%s"
            " next_distance=%" PRIu64
            " next_address_mode=%s"
            " next_phys_mapped=%s"
            " next_phys=0x%08" PRIx64
            " next_image_phys_mapped=%s"
            " next_image_phys=0x%08" PRIx64
            " next_phys_match=%s"
            " cpu_known=%s"
            " cpu_mode=%s"
            " cpl=%" PRIu32
            " eip=0x%08" PRIx64
            " cs=0x%04" PRIx32
            " esp=0x%08" PRIx64
            " next_code_read=%s"
            " next_code_hash=0x%016" PRIx64
            " next_opcode=0x%02" PRIx8
            " next_opcode2_known=%s"
            " next_opcode2=0x%02" PRIx8
            " next_modrm_known=%s"
            " next_modrm=0x%02" PRIx8
            " next_branch_kind=%s"
            " next_branch_operand_addr_known=%s"
            " next_branch_operand_addr=0x%08" PRIx64
            " next_branch_target_known=%s"
            " next_branch_target=0x%08" PRIx64
            " next_branch_image_pc=0x%08" PRIx64
            " next_branch_relation=%s"
            " next_branch_distance=%" PRIu64
            " next_branch_entry_relation=%s"
            " next_branch_entry_distance=%" PRIu64
            " next_branch_address_mode=%s"
            " next_branch_phys_mapped=%s"
            " next_branch_phys=0x%08" PRIx64
            " next_branch_image_phys_mapped=%s"
            " next_branch_image_phys=0x%08" PRIx64
            " next_branch_phys_match=%s"
            " source=%s\n",
            xemu_xbe_boot_trace_context(), obs->exec_edge_probe_count,
            observed_count, edge->hits,
            xemu_xbe_bool_str(obs->entry_marked), obs->entry,
            edge->start_pc, start_image_pc, edge->tb_size, edge->tb_exit,
            edge->start_pc + edge->tb_size, edge->next_pc, next_image_pc,
            xemu_xbe_bool_str(edge->next_pc ==
                              edge->start_pc + edge->tb_size),
            start_relation, start_distance, start_address_mode,
            xemu_xbe_bool_str(start_mapping.mapped),
            start_mapping.mapped ? (uint64_t)start_mapping.phys_addr : 0,
            xemu_xbe_bool_str(start_image_mapping.mapped),
            start_image_mapping.mapped ?
                (uint64_t)start_image_mapping.phys_addr : 0,
            start_phys_match,
            next_relation, next_distance, next_address_mode,
            xemu_xbe_bool_str(next_mapping.mapped),
            next_mapping.mapped ? (uint64_t)next_mapping.phys_addr : 0,
            xemu_xbe_bool_str(next_image_mapping.mapped),
            next_image_mapping.mapped ?
                (uint64_t)next_image_mapping.phys_addr : 0,
            next_phys_match,
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip,
            exec_ctx.cs_selector, exec_ctx.esp,
            xemu_xbe_bool_str(next_code_probe.read_ok), next_code_probe.hash,
            next_code_probe.opcode,
            xemu_xbe_bool_str(next_code_probe.opcode2_known),
            next_code_probe.opcode2,
            xemu_xbe_bool_str(next_code_probe.modrm_known),
            next_code_probe.modrm,
            next_code_probe.branch.kind,
            xemu_xbe_bool_str(next_code_probe.branch.operand_addr_known),
            next_code_probe.branch.operand_addr,
            xemu_xbe_bool_str(next_code_probe.branch.target_known),
            next_code_probe.branch.target,
            next_branch_classification.image_pc,
            next_branch_classification.relation,
            next_branch_classification.distance,
            next_branch_classification.entry_relation,
            next_branch_classification.entry_distance,
            next_branch_classification.address_mode,
            xemu_xbe_bool_str(next_branch_classification.mapping.mapped),
            next_branch_classification.mapping.mapped ?
                (uint64_t)next_branch_classification.mapping.phys_addr : 0,
            xemu_xbe_bool_str(
                next_branch_classification.image_mapping.mapped),
            next_branch_classification.image_mapping.mapped ?
                (uint64_t)next_branch_classification.image_mapping.phys_addr :
                0,
            next_branch_classification.phys_match,
            source ? source : "tcg-tb-edge");
}

void xemu_xbe_boot_trace_observe_exec_transition(uint64_t start_pc,
                                                 uint32_t tb_size,
                                                 int tb_exit,
                                                 const char *source)
{
    struct xemu_xbe_loaded_observation *obs = &xemu_xbe_loaded_observation;
    uint64_t expected_next = start_pc + tb_size;
    uint64_t next_pc = 0;
    bool next_pc_known;
    uint64_t observed_count;
    uint64_t stride;
    int64_t limit;
    const char *start_relation;
    const char *start_address_mode;
    const char *start_phys_match;
    uint64_t start_distance;
    uint64_t start_image_pc;
    struct xemu_xbe_pc_mapping start_mapping;
    struct xemu_xbe_pc_mapping start_image_mapping;
    const char *next_relation;
    const char *next_address_mode;
    const char *next_phys_match;
    uint64_t next_distance;
    uint64_t next_image_pc;
    struct xemu_xbe_pc_mapping next_mapping;
    struct xemu_xbe_pc_mapping next_image_mapping;
    struct xemu_xbe_exec_context exec_ctx;
    struct xemu_xbe_code_probe start_code_probe;
    struct xemu_xbe_code_probe next_code_probe;
    struct xemu_xbe_target_classification next_branch_classification;
    struct xemu_xbe_exec_edge_observation *edge;
    struct xemu_xbe_exec_edge_observation transition_edge;
    bool transition_probe_captured = false;
    bool after_idle_kernel_loop_emitted = false;

    if (!obs->loaded_marked || obs->executed_marked || !obs->size) {
        return;
    }

    next_pc_known = xemu_xbe_current_pc(&next_pc);
    if (next_pc_known &&
        xemu_xbe_boot_trace_mark_executed(next_pc, 1, source)) {
        return;
    }

    if (!obs->entry_marked) {
        return;
    }

    observed_count = ++obs->exec_transition_probe_observed_count;
    xemu_xbe_latest_exec_transition =
        (struct xemu_xbe_exec_transition_snapshot) {
            .valid = true,
            .next_pc_known = next_pc_known,
            .observed_count = observed_count,
            .start_pc = start_pc,
            .next_pc = next_pc_known ? next_pc : 0,
            .tb_size = tb_size,
            .tb_exit = tb_exit,
        };
    edge = next_pc_known ?
        xemu_xbe_exec_edge_observe(start_pc, next_pc, tb_size, tb_exit) :
        NULL;
    xemu_xbe_boot_trace_exec_edge_probe(observed_count, edge, source);
    if (next_pc_known) {
        xemu_xbe_boot_trace_idle_before_pfifo_transition_probe(
            observed_count, start_pc, next_pc, tb_size, tb_exit, edge, source);
    }

    if (next_pc_known &&
        xemu_xbe_boot_trace_after_idle_kernel_loop_available()) {
        xemu_xbe_capture_exec_context(&exec_ctx);
        xemu_xbe_capture_code_probe(start_pc, &exec_ctx, &start_code_probe);
        xemu_xbe_capture_code_probe(next_pc, &exec_ctx, &next_code_probe);
        transition_probe_captured = true;
        transition_edge = (struct xemu_xbe_exec_edge_observation) {
            .used = true,
            .start_pc = start_pc,
            .next_pc = next_pc,
            .tb_size = tb_size,
            .tb_exit = tb_exit,
            .hits = edge ? edge->hits : 1,
        };
        after_idle_kernel_loop_emitted =
            xemu_xbe_boot_trace_kernel_loop_probe(
                observed_count, "after-idle-transition-sample",
                &transition_edge, &exec_ctx, &start_code_probe,
                &next_code_probe, false, true, source);
    }

    limit = xemu_xbe_exec_probe_limit();
    if (limit == 0 ||
        obs->exec_transition_probe_count >= (uint64_t)limit) {
        return;
    }

    stride = xemu_xbe_exec_probe_stride();
    if (observed_count > XEMU_XBE_EXEC_PROBE_INITIAL_SAMPLES &&
        observed_count % stride != 0) {
        return;
    }

    xemu_xbe_pc_relation_to_loaded_image(start_pc, tb_size,
                                         &start_relation,
                                         &start_distance);
    xemu_xbe_pc_overlaps_loaded_image(start_pc, tb_size,
                                      &start_address_mode,
                                      &start_image_pc,
                                      &start_mapping,
                                      &start_image_mapping);
    start_phys_match = xemu_xbe_phys_match_status(start_address_mode,
                                                  &start_mapping,
                                                  &start_image_mapping);

    if (next_pc_known) {
        xemu_xbe_pc_relation_to_loaded_image(next_pc, 1,
                                             &next_relation,
                                             &next_distance);
        xemu_xbe_pc_overlaps_loaded_image(next_pc, 1,
                                          &next_address_mode,
                                          &next_image_pc,
                                          &next_mapping,
                                          &next_image_mapping);
        next_phys_match = xemu_xbe_phys_match_status(next_address_mode,
                                                     &next_mapping,
                                                     &next_image_mapping);
    } else {
        next_relation = "unknown";
        next_distance = 0;
        next_address_mode = "unknown";
        next_image_pc = 0;
        next_mapping = (struct xemu_xbe_pc_mapping) { 0 };
        next_image_mapping = (struct xemu_xbe_pc_mapping) { 0 };
        next_phys_match = "unknown";
    }

    if (!transition_probe_captured) {
        xemu_xbe_capture_exec_context(&exec_ctx);
        xemu_xbe_capture_code_probe(start_pc, &exec_ctx, &start_code_probe);
        memset(&next_code_probe, 0, sizeof(next_code_probe));
        next_code_probe.branch.kind = "unknown";
        if (next_pc_known) {
            xemu_xbe_capture_code_probe(next_pc, &exec_ctx, &next_code_probe);
        }
    }
    xemu_xbe_classify_branch_target(&next_code_probe.branch,
                                    &next_branch_classification);
    xemu_xbe_boot_trace_entry_target_probe("transition-next-branch",
                                           observed_count,
                                           start_pc,
                                           next_pc,
                                           &next_code_probe,
                                           &next_branch_classification,
                                           &exec_ctx,
                                           source);
    if (next_pc_known && !after_idle_kernel_loop_emitted) {
        transition_edge = (struct xemu_xbe_exec_edge_observation) {
            .used = true,
            .start_pc = start_pc,
            .next_pc = next_pc,
            .tb_size = tb_size,
            .tb_exit = tb_exit,
            .hits = edge ? edge->hits : 1,
        };
        xemu_xbe_boot_trace_kernel_loop_probe(observed_count,
                                              "transition-sample",
                                              &transition_edge, &exec_ctx,
                                              &start_code_probe,
                                              &next_code_probe, false, false,
                                              source);
    }

    obs->exec_transition_probe_count++;

    fprintf(stderr,
            "BOOT_MARK b6 dashboard=xbe-exec-transition context=%s"
            " observed_seq=%" PRIu64
            " observed_tbs=%" PRIu64
            " start_pc=0x%08" PRIx64
            " start_image_pc=0x%08" PRIx64
            " tb_size=%" PRIu32
            " tb_exit=%d"
            " expected_next=0x%08" PRIx64
            " entry_ready=%s"
            " entry=0x%08" PRIx32
            " next_pc_known=%s"
            " next_pc=0x%08" PRIx64
            " next_image_pc=0x%08" PRIx64
            " fallthrough_match=%s"
            " start_relation=%s"
            " start_distance=%" PRIu64
            " start_address_mode=%s"
            " start_phys_mapped=%s"
            " start_phys=0x%08" PRIx64
            " start_image_phys_mapped=%s"
            " start_image_phys=0x%08" PRIx64
            " start_phys_match=%s"
            " next_relation=%s"
            " next_distance=%" PRIu64
            " next_address_mode=%s"
            " next_phys_mapped=%s"
            " next_phys=0x%08" PRIx64
            " next_image_phys_mapped=%s"
            " next_image_phys=0x%08" PRIx64
            " next_phys_match=%s"
            " cpu_known=%s"
            " cpu_mode=%s"
            " cpl=%" PRIu32
            " eip=0x%08" PRIx64
            " cs=0x%04" PRIx32
            " esp=0x%08" PRIx64
            " next_code_read=%s"
            " next_code_hash=0x%016" PRIx64
            " next_opcode=0x%02" PRIx8
            " next_opcode2_known=%s"
            " next_opcode2=0x%02" PRIx8
            " next_modrm_known=%s"
            " next_modrm=0x%02" PRIx8
            " next_branch_kind=%s"
            " next_branch_operand_addr_known=%s"
            " next_branch_operand_addr=0x%08" PRIx64
            " next_branch_target_known=%s"
            " next_branch_target=0x%08" PRIx64
            " next_branch_image_pc=0x%08" PRIx64
            " next_branch_relation=%s"
            " next_branch_distance=%" PRIu64
            " next_branch_entry_relation=%s"
            " next_branch_entry_distance=%" PRIu64
            " next_branch_address_mode=%s"
            " next_branch_phys_mapped=%s"
            " next_branch_phys=0x%08" PRIx64
            " next_branch_image_phys_mapped=%s"
            " next_branch_image_phys=0x%08" PRIx64
            " next_branch_phys_match=%s"
            " source=%s\n",
            xemu_xbe_boot_trace_context(),
            obs->exec_transition_probe_count, observed_count,
            start_pc, start_image_pc, tb_size, tb_exit, expected_next,
            xemu_xbe_bool_str(obs->entry_marked), obs->entry,
            xemu_xbe_bool_str(next_pc_known), next_pc, next_image_pc,
            xemu_xbe_bool_str(next_pc_known && next_pc == expected_next),
            start_relation, start_distance, start_address_mode,
            xemu_xbe_bool_str(start_mapping.mapped),
            start_mapping.mapped ? (uint64_t)start_mapping.phys_addr : 0,
            xemu_xbe_bool_str(start_image_mapping.mapped),
            start_image_mapping.mapped ?
                (uint64_t)start_image_mapping.phys_addr : 0,
            start_phys_match,
            next_relation, next_distance, next_address_mode,
            xemu_xbe_bool_str(next_mapping.mapped),
            next_mapping.mapped ? (uint64_t)next_mapping.phys_addr : 0,
            xemu_xbe_bool_str(next_image_mapping.mapped),
            next_image_mapping.mapped ?
                (uint64_t)next_image_mapping.phys_addr : 0,
            next_phys_match,
            xemu_xbe_bool_str(exec_ctx.cpu_known), exec_ctx.mode,
            exec_ctx.cpl, exec_ctx.eip,
            exec_ctx.cs_selector, exec_ctx.esp,
            xemu_xbe_bool_str(next_code_probe.read_ok), next_code_probe.hash,
            next_code_probe.opcode,
            xemu_xbe_bool_str(next_code_probe.opcode2_known),
            next_code_probe.opcode2,
            xemu_xbe_bool_str(next_code_probe.modrm_known),
            next_code_probe.modrm,
            next_code_probe.branch.kind,
            xemu_xbe_bool_str(next_code_probe.branch.operand_addr_known),
            next_code_probe.branch.operand_addr,
            xemu_xbe_bool_str(next_code_probe.branch.target_known),
            next_code_probe.branch.target,
            next_branch_classification.image_pc,
            next_branch_classification.relation,
            next_branch_classification.distance,
            next_branch_classification.entry_relation,
            next_branch_classification.entry_distance,
            next_branch_classification.address_mode,
            xemu_xbe_bool_str(next_branch_classification.mapping.mapped),
            next_branch_classification.mapping.mapped ?
                (uint64_t)next_branch_classification.mapping.phys_addr : 0,
            xemu_xbe_bool_str(
                next_branch_classification.image_mapping.mapped),
            next_branch_classification.image_mapping.mapped ?
                (uint64_t)next_branch_classification.image_mapping.phys_addr :
                0,
            next_branch_classification.phys_match,
            source ? source : "tcg-tb-post");
}

static void xemu_xbe_probe_page_tables(vaddr vaddr,
                                       struct xemu_xbe_page_probe *probe)
{
    memset(probe, 0, sizeof(*probe));
    probe->status = "unsupported";

#if defined(TARGET_I386)
    CPUState *cs = qemu_get_cpu(0);
    X86CPU *cpu;
    CPUX86State *env;
    bool paging;
    bool pae;
    bool pse;

    if (!cs) {
        probe->status = "no-cpu";
        return;
    }

    cpu_synchronize_state(cs);
    cpu = X86_CPU(cs);
    env = &cpu->env;

    probe->cpu_known = true;
    probe->cr0 = env->cr[0];
    probe->cr3 = env->cr[3];
    probe->cr4 = env->cr[4];
    probe->efer = env->efer;

    paging = probe->cr0 & CR0_PG_MASK;
    pae = probe->cr4 & CR4_PAE_MASK;
    pse = probe->cr4 & CR4_PSE_MASK;

    if (!paging) {
        probe->status = "paging-off";
        return;
    }

    if (env->hflags & HF_CS64_MASK) {
        probe->status = "long-mode";
        return;
    }

    if (pae) {
        uint64_t pdpe;
        uint64_t pde;
        unsigned pdpe_index = (vaddr >> 30) & 0x3;
        unsigned pde_index = (vaddr >> 21) & 0x1ff;
        unsigned pte_index = (vaddr >> 12) & 0x1ff;

        probe->pdpe_addr = (probe->cr3 & 0xffffffe0ULL) + pdpe_index * 8;
        pdpe = ldq_le_phys(&address_space_memory, probe->pdpe_addr);
        probe->pdpe = pdpe;
        if (!(pdpe & PG_PRESENT_MASK)) {
            probe->status = "pdpe-not-present";
            return;
        }

        probe->pde_addr = (pdpe & PG_ADDRESS_MASK) + pde_index * 8;
        pde = ldq_le_phys(&address_space_memory, probe->pde_addr);
        probe->pde = pde;
        if (!(pde & PG_PRESENT_MASK)) {
            probe->status = "pde-not-present";
            return;
        }
        if (pde & PG_PSE_MASK) {
            probe->status = "mapped-large-page";
            return;
        }

        probe->pte_addr = (pde & PG_ADDRESS_MASK) + pte_index * 8;
        probe->pte = ldq_le_phys(&address_space_memory, probe->pte_addr);
        if (!(probe->pte & PG_PRESENT_MASK)) {
            probe->status = "pte-not-present";
            return;
        }

        probe->status = "mapped-page";
        return;
    }

    probe->pde_addr = (probe->cr3 & 0xfffff000ULL) +
                      (((uint32_t)vaddr >> 22) & 0x3ff) * 4;
    probe->pde = ldl_le_phys(&address_space_memory, probe->pde_addr);
    if (!(probe->pde & PG_PRESENT_MASK)) {
        probe->status = "pde-not-present";
        return;
    }
    if ((probe->pde & PG_PSE_MASK) && pse) {
        probe->status = "mapped-large-page";
        return;
    }

    probe->pte_addr = (probe->pde & 0xfffff000ULL) +
                      (((uint32_t)vaddr >> 12) & 0x3ff) * 4;
    probe->pte = ldl_le_phys(&address_space_memory, probe->pte_addr);
    if (!(probe->pte & PG_PRESENT_MASK)) {
        probe->status = "pte-not-present";
        return;
    }

    probe->status = "mapped-page";
#endif
}

static int64_t xemu_xbe_virtual_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_VIRTUAL_PROBE_DEFAULT_LIMIT;
    const char *value;
    char *end = NULL;

    if (initialized) {
        return limit;
    }

    initialized = true;
    value = getenv("XEMU_BOOT_TRACE_XBE_VIRTUAL_PROBE_LIMIT");
    if (!value || !value[0]) {
        return limit;
    }

    limit = g_ascii_strtoll(value, &end, 10);
    if (end == value || limit < 0) {
        fprintf(stderr,
                "Invalid XEMU_BOOT_TRACE_XBE_VIRTUAL_PROBE_LIMIT='%s'; using %d\n",
                value, XEMU_XBE_VIRTUAL_PROBE_DEFAULT_LIMIT);
        limit = XEMU_XBE_VIRTUAL_PROBE_DEFAULT_LIMIT;
    }

    return limit;
}

static int64_t xemu_xbe_read_progress_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_READ_PROGRESS_DEFAULT_LIMIT;
    const char *value;
    char *end = NULL;

    if (initialized) {
        return limit;
    }

    initialized = true;
    value = getenv("XEMU_BOOT_TRACE_XBE_READ_PROGRESS_LIMIT");
    if (!value || !value[0]) {
        return limit;
    }

    limit = g_ascii_strtoll(value, &end, 10);
    if (end == value || limit < 0) {
        fprintf(stderr,
                "Invalid XEMU_BOOT_TRACE_XBE_READ_PROGRESS_LIMIT='%s'; using %d\n",
                value, XEMU_XBE_READ_PROGRESS_DEFAULT_LIMIT);
        limit = XEMU_XBE_READ_PROGRESS_DEFAULT_LIMIT;
    }

    return limit;
}

static int64_t xemu_xbe_exec_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_EXEC_PROBE_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_EXEC_PROBE_LIMIT",
        "xbe_exec_probe_limit.txt",
        XEMU_XBE_EXEC_PROBE_DEFAULT_LIMIT);

    return limit;
}

static int64_t xemu_xbe_exec_edge_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_EXEC_EDGE_DEFAULT_LIMIT;
    const char *value;
    char *end = NULL;

    if (initialized) {
        return limit;
    }

    initialized = true;
    value = getenv("XEMU_BOOT_TRACE_XBE_EXEC_EDGE_LIMIT");
    if (!value || !value[0]) {
        return limit;
    }

    limit = g_ascii_strtoll(value, &end, 10);
    if (end == value || limit < 0) {
        fprintf(stderr,
                "Invalid XEMU_BOOT_TRACE_XBE_EXEC_EDGE_LIMIT='%s'; using %d\n",
                value, XEMU_XBE_EXEC_EDGE_DEFAULT_LIMIT);
        limit = XEMU_XBE_EXEC_EDGE_DEFAULT_LIMIT;
    }

    return limit;
}

static int64_t xemu_xbe_edge_decision_limit(void)
{
    return xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT",
        "xbe_edge_decision_limit.txt",
        0);
}

static int64_t xemu_xbe_entry_target_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_ENTRY_TARGET_DEFAULT_LIMIT;
    const char *value;
    char *end = NULL;

    if (initialized) {
        return limit;
    }

    initialized = true;
    value = getenv("XEMU_BOOT_TRACE_XBE_ENTRY_TARGET_LIMIT");
    if (!value || !value[0]) {
        return limit;
    }

    limit = g_ascii_strtoll(value, &end, 10);
    if (end == value || limit < 0) {
        fprintf(stderr,
                "Invalid XEMU_BOOT_TRACE_XBE_ENTRY_TARGET_LIMIT='%s'; using %d\n",
                value, XEMU_XBE_ENTRY_TARGET_DEFAULT_LIMIT);
        limit = XEMU_XBE_ENTRY_TARGET_DEFAULT_LIMIT;
    }

    return limit;
}

static int64_t xemu_xbe_dispatch_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_DISPATCH_PROBE_DEFAULT_LIMIT;
    const char *value;
    char *end = NULL;

    if (initialized) {
        return limit;
    }

    initialized = true;
    value = getenv("XEMU_BOOT_TRACE_XBE_DISPATCH_LIMIT");
    if (!value || !value[0]) {
        return limit;
    }

    limit = g_ascii_strtoll(value, &end, 10);
    if (end == value || limit < 0) {
        fprintf(stderr,
                "Invalid XEMU_BOOT_TRACE_XBE_DISPATCH_LIMIT='%s'; using %d\n",
                value, XEMU_XBE_DISPATCH_PROBE_DEFAULT_LIMIT);
        limit = XEMU_XBE_DISPATCH_PROBE_DEFAULT_LIMIT;
    }

    return limit;
}

static int64_t xemu_xbe_kernel_loop_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_KERNEL_LOOP_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT",
        "xbe_kernel_loop_limit.txt",
        XEMU_XBE_KERNEL_LOOP_DEFAULT_LIMIT);

    return limit;
}

static int64_t xemu_xbe_kernel_loop_after_idle_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_KERNEL_LOOP_AFTER_IDLE_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT",
        "xbe_kernel_loop_after_idle_limit.txt",
        XEMU_XBE_KERNEL_LOOP_AFTER_IDLE_DEFAULT_LIMIT);

    return limit;
}

static int64_t xemu_xbe_idle_before_pfifo_transition_probe_limit(void)
{
    static bool initialized;
    static int64_t limit =
        XEMU_XBE_IDLE_BEFORE_PFIFO_TRANSITION_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_IDLE_BEFORE_PFIFO_TRANSITION_LIMIT",
        "xbe_idle_before_pfifo_transition_limit.txt",
        XEMU_XBE_IDLE_BEFORE_PFIFO_TRANSITION_DEFAULT_LIMIT);

    return limit;
}

static int64_t xemu_xbe_alias_compare_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_ALIAS_COMPARE_DEFAULT_LIMIT;
    const char *value;
    char *end = NULL;

    if (initialized) {
        return limit;
    }

    initialized = true;
    value = getenv("XEMU_BOOT_TRACE_XBE_ALIAS_COMPARE_LIMIT");
    if (!value || !value[0]) {
        return limit;
    }

    limit = g_ascii_strtoll(value, &end, 10);
    if (end == value || limit < 0) {
        fprintf(stderr,
                "Invalid XEMU_BOOT_TRACE_XBE_ALIAS_COMPARE_LIMIT='%s'; using %d\n",
                value, XEMU_XBE_ALIAS_COMPARE_DEFAULT_LIMIT);
        limit = XEMU_XBE_ALIAS_COMPARE_DEFAULT_LIMIT;
    }

    return limit;
}

static int64_t xemu_xbe_phys_compare_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_PHYS_COMPARE_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_PHYS_COMPARE_LIMIT",
        "xbe_phys_compare_limit.txt",
        XEMU_XBE_PHYS_COMPARE_DEFAULT_LIMIT);

    return limit;
}

static bool xemu_xbe_boot_trace_read_fixture_setting(const char *file_name,
                                                     char *buffer,
                                                     size_t buffer_size)
{
    const char *dirs[] = {
        "/xemu-fixtures",
        "/xemu-smoke",
        "/xemu-smoke-out",
        NULL,
    };

    for (int i = 0; dirs[i]; i++) {
        char path[PATH_MAX];
        FILE *fp;

        snprintf(path, sizeof(path), "%s/%s", dirs[i], file_name);
        fp = fopen(path, "r");
        if (!fp) {
            continue;
        }

        if (fgets(buffer, buffer_size, fp)) {
            buffer[strcspn(buffer, "\r\n")] = 0;
        } else {
            buffer[0] = 0;
        }
        fclose(fp);

        if (buffer[0]) {
            return true;
        }
    }

    return false;
}

static int64_t xemu_xbe_boot_trace_limit_setting(const char *env_name,
                                                 const char *file_name,
                                                 int64_t default_limit)
{
    char file_value[64];
    const char *value = getenv(env_name);
    const char *source = env_name;
    char *end = NULL;
    int64_t limit;

    if (!value || !value[0]) {
        if (!xemu_xbe_boot_trace_read_fixture_setting(file_name, file_value,
                                                     sizeof(file_value))) {
            return default_limit;
        }
        value = file_value;
        source = file_name;
    }

    limit = g_ascii_strtoll(value, &end, 10);
    if (end == value || limit < 0) {
        fprintf(stderr, "Invalid %s='%s'; using %" PRId64 "\n",
                source, value, default_limit);
        limit = default_limit;
    }

    return limit;
}

#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
static uint64_t xemu_xbe_boot_trace_u64_setting(const char *env_name,
                                                const char *file_name,
                                                uint64_t default_value)
{
    char file_value[64];
    const char *value = getenv(env_name);
    const char *source = env_name;
    char *end = NULL;
    uint64_t parsed;

    if (!value || !value[0]) {
        if (!xemu_xbe_boot_trace_read_fixture_setting(file_name, file_value,
                                                     sizeof(file_value))) {
            return default_value;
        }
        value = file_value;
        source = file_name;
    }

    parsed = g_ascii_strtoull(value, &end, 0);
    if (end == value || *end) {
        fprintf(stderr, "Invalid %s='%s'; using 0x%08" PRIx64 "\n",
                source, value, default_value);
        parsed = default_value;
    }

    return parsed;
}
#endif

static bool xemu_xbe_boot_trace_bool_setting(const char *env_name,
                                             const char *file_name,
                                             bool default_value)
{
    char file_value[64];
    const char *value = getenv(env_name);

    if (!value || !value[0]) {
        if (!xemu_xbe_boot_trace_read_fixture_setting(file_name, file_value,
                                                     sizeof(file_value))) {
            return default_value;
        }
        value = file_value;
    }

    if (!g_ascii_strcasecmp(value, "0") ||
        !g_ascii_strcasecmp(value, "false") ||
        !g_ascii_strcasecmp(value, "no") ||
        !g_ascii_strcasecmp(value, "off")) {
        return false;
    }

    return true;
}

static bool xemu_xbe_irq_after_pfifo_empty_only(void)
{
    static bool initialized;
    static bool enabled;

    if (initialized) {
        return enabled;
    }

    initialized = true;
    enabled = xemu_xbe_boot_trace_bool_setting(
        "XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY",
        "xbe_irq_after_pfifo_empty_only.txt",
        false);

    return enabled;
}

static bool xemu_xbe_irq_watch_matches(int guest_irq)
{
    static bool initialized;
    static bool all;
    static bool watched[16];

    if (!initialized) {
        char file_value[128];
        const char *value = getenv("XEMU_BOOT_TRACE_XBE_IRQ_WATCH");

        initialized = true;
        if (!value || !value[0]) {
            if (!xemu_xbe_boot_trace_read_fixture_setting(
                    "xbe_irq_watch.txt", file_value, sizeof(file_value))) {
                value = NULL;
            } else {
                value = file_value;
            }
        }

        if (value && value[0]) {
            char **tokens = g_strsplit_set(value, ", \t", -1);

            for (char **token = tokens; token && *token; token++) {
                char *end = NULL;
                uint64_t irq;

                if (!(*token)[0]) {
                    continue;
                }
                if (!g_ascii_strcasecmp(*token, "all") ||
                    !strcmp(*token, "*")) {
                    all = true;
                    continue;
                }

                irq = g_ascii_strtoull(*token, &end, 0);
                if (end == *token || *end || irq >= G_N_ELEMENTS(watched)) {
                    fprintf(stderr,
                            "Invalid XEMU_BOOT_TRACE_XBE_IRQ_WATCH token='%s'; "
                            "ignoring\n",
                            *token);
                    continue;
                }
                watched[irq] = true;
            }
            g_strfreev(tokens);
        }
    }

    return all || (guest_irq >= 0 &&
                   guest_irq < (int)G_N_ELEMENTS(watched) &&
                   watched[guest_irq]);
}

static int64_t xemu_xbe_pit_irq_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_PIT_IRQ_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_PIT_IRQ_LIMIT",
        "xbe_pit_irq_limit.txt",
        XEMU_XBE_PIT_IRQ_DEFAULT_LIMIT);

    return limit;
}

static int64_t xemu_xbe_main_loop_timer_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_MAIN_LOOP_TIMER_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_MAIN_LOOP_TIMER_LIMIT",
        "xbe_main_loop_timer_limit.txt",
        XEMU_XBE_MAIN_LOOP_TIMER_DEFAULT_LIMIT);

    return limit;
}

static int64_t xemu_xbe_timer_opportunity_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_TIMER_OPPORTUNITY_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_TIMER_OPPORTUNITY_LIMIT",
        "xbe_timer_opportunity_limit.txt",
        XEMU_XBE_TIMER_OPPORTUNITY_DEFAULT_LIMIT);

    return limit;
}

static int64_t xemu_xbe_tick_block_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_TICK_BLOCK_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_TICK_BLOCK_LIMIT",
        "xbe_tick_block_limit.txt",
        XEMU_XBE_TICK_BLOCK_DEFAULT_LIMIT);

    return limit;
}

static int64_t xemu_xbe_tick_block_irq_defer_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_TICK_BLOCK_IRQ_DEFER_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_TICK_BLOCK_IRQ_DEFER_LIMIT",
        "xbe_tick_block_irq_defer_limit.txt",
        XEMU_XBE_TICK_BLOCK_IRQ_DEFER_DEFAULT_LIMIT);

    return limit;
}

static bool xemu_xbe_tick_block_irq_defer_enabled(void)
{
    static bool initialized;
    static bool enabled;

    if (initialized) {
        return enabled;
    }

    initialized = true;
    enabled = xemu_xbe_boot_trace_bool_setting(
        "XEMU_BOOT_TRACE_XBE_TICK_BLOCK_IRQ_DEFER",
        "xbe_tick_block_irq_defer.txt",
        false);

    return enabled;
}

static int64_t xemu_xbe_pre_first_read_scheduler_tb_budget(void)
{
    static bool initialized;
    static int64_t budget =
        XEMU_XBE_PRE_FIRST_READ_SCHEDULER_DEFAULT_TB_BUDGET;

    if (initialized) {
        return budget;
    }

    initialized = true;
    budget = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_PRE_FIRST_READ_SCHEDULER_TB_BUDGET",
        "xbe_pre_first_read_scheduler_tb_budget.txt",
        XEMU_XBE_PRE_FIRST_READ_SCHEDULER_DEFAULT_TB_BUDGET);

    return budget;
}

int64_t xemu_xbe_boot_trace_tcg_timer_pump_interval(void)
{
    static bool initialized;
    static int64_t interval = XEMU_XBE_TCG_TIMER_PUMP_DEFAULT_INTERVAL;

    if (initialized) {
        return interval;
    }

    initialized = true;
    interval = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL",
        "xbe_tcg_timer_pump_interval.txt",
        XEMU_XBE_TCG_TIMER_PUMP_DEFAULT_INTERVAL);

    return interval;
}

static int64_t xemu_xbe_tcg_timer_pump_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_TCG_TIMER_PUMP_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_LIMIT",
        "xbe_tcg_timer_pump_limit.txt",
        XEMU_XBE_TCG_TIMER_PUMP_DEFAULT_LIMIT);

    return limit;
}

#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
static int64_t xemu_xbe_memory_watch_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_MEMORY_WATCH_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT",
        "xbe_memory_watch_limit.txt",
        XEMU_XBE_MEMORY_WATCH_DEFAULT_LIMIT);

    return limit;
}

static uint64_t xemu_xbe_memory_watch_phys(void)
{
    static bool initialized;
    static uint64_t phys;

    if (initialized) {
        return phys;
    }

    initialized = true;
    phys = xemu_xbe_boot_trace_u64_setting(
        "XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS",
        "xbe_memory_watch_phys.txt",
        0);

    if (phys >= XEMU_XBE_LOW_RAM_BYTES) {
        fprintf(stderr,
                "Invalid XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS=0x%08" PRIx64
                "; only low RAM is supported, disabling\n",
                phys);
        phys = 0;
    }

    return phys;
}
#endif

#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
static bool xemu_xbe_memory_watch_access_enabled(void)
{
    return xemu_xbe_memory_watch_access_mode() !=
           XEMU_XBE_MEMORY_WATCH_ACCESS_OFF;
}

static bool xemu_xbe_memory_watch_access_matches(bool write)
{
    switch (xemu_xbe_memory_watch_access_mode()) {
    case XEMU_XBE_MEMORY_WATCH_ACCESS_ALL:
        return true;
    case XEMU_XBE_MEMORY_WATCH_ACCESS_READ:
        return !write;
    case XEMU_XBE_MEMORY_WATCH_ACCESS_WRITE:
        return write;
    case XEMU_XBE_MEMORY_WATCH_ACCESS_OFF:
    default:
        return false;
    }
}

static const char *xemu_xbe_memory_watch_access_mode_name(void)
{
    switch (xemu_xbe_memory_watch_access_mode()) {
    case XEMU_XBE_MEMORY_WATCH_ACCESS_ALL:
        return "all";
    case XEMU_XBE_MEMORY_WATCH_ACCESS_READ:
        return "read";
    case XEMU_XBE_MEMORY_WATCH_ACCESS_WRITE:
        return "write";
    case XEMU_XBE_MEMORY_WATCH_ACCESS_OFF:
    default:
        return "off";
    }
}

static XemuXbeMemoryWatchAccessMode xemu_xbe_memory_watch_access_mode(void)
{
    static bool initialized;
    static XemuXbeMemoryWatchAccessMode mode =
        XEMU_XBE_MEMORY_WATCH_ACCESS_OFF;
    char file_value[64];
    const char *value;
    const char *source;

    if (initialized) {
        return mode;
    }

    initialized = true;
    value = getenv("XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS");
    source = "XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS";

    if (!value || !value[0]) {
        if (!xemu_xbe_boot_trace_read_fixture_setting(
                "xbe_memory_watch_access.txt", file_value,
                sizeof(file_value))) {
            return mode;
        }
        value = file_value;
        source = "xbe_memory_watch_access.txt";
    }

    if (!g_ascii_strcasecmp(value, "0") ||
        !g_ascii_strcasecmp(value, "false") ||
        !g_ascii_strcasecmp(value, "no") ||
        !g_ascii_strcasecmp(value, "off")) {
        mode = XEMU_XBE_MEMORY_WATCH_ACCESS_OFF;
    } else if (!g_ascii_strcasecmp(value, "read") ||
               !g_ascii_strcasecmp(value, "reads") ||
               !g_ascii_strcasecmp(value, "read-only")) {
        mode = XEMU_XBE_MEMORY_WATCH_ACCESS_READ;
    } else if (!g_ascii_strcasecmp(value, "write") ||
               !g_ascii_strcasecmp(value, "writes") ||
               !g_ascii_strcasecmp(value, "write-only")) {
        mode = XEMU_XBE_MEMORY_WATCH_ACCESS_WRITE;
    } else if (!g_ascii_strcasecmp(value, "1") ||
               !g_ascii_strcasecmp(value, "true") ||
               !g_ascii_strcasecmp(value, "yes") ||
               !g_ascii_strcasecmp(value, "on") ||
               !g_ascii_strcasecmp(value, "all") ||
               !g_ascii_strcasecmp(value, "any")) {
        mode = XEMU_XBE_MEMORY_WATCH_ACCESS_ALL;
    } else {
        fprintf(stderr,
                "Invalid %s='%s'; using memory watch access_filter=all\n",
                source, value);
        mode = XEMU_XBE_MEMORY_WATCH_ACCESS_ALL;
    }

    return mode;
}
#endif

static int64_t xemu_xbe_tcg_timer_pump_gate_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_TCG_TIMER_PUMP_GATE_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_GATE_LIMIT",
        "xbe_tcg_timer_pump_gate_limit.txt",
        XEMU_XBE_TCG_TIMER_PUMP_GATE_DEFAULT_LIMIT);

    return limit;
}

static int64_t xemu_xbe_tcg_timer_pump_after_idle_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_TCG_TIMER_PUMP_AFTER_IDLE_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT",
        "xbe_tcg_timer_pump_after_idle_limit.txt",
        XEMU_XBE_TCG_TIMER_PUMP_AFTER_IDLE_DEFAULT_LIMIT);

    return limit;
}

static int64_t xemu_xbe_pic_irq_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_PIC_IRQ_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_PIC_IRQ_LIMIT",
        "xbe_pic_irq_limit.txt",
        XEMU_XBE_PIC_IRQ_DEFAULT_LIMIT);

    return limit;
}

static int64_t xemu_xbe_cpu_hard_irq_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_CPU_HARD_IRQ_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT",
        "xbe_cpu_hard_irq_limit.txt",
        XEMU_XBE_CPU_HARD_IRQ_DEFAULT_LIMIT);

    return limit;
}

static int64_t xemu_xbe_iret_probe_limit(void)
{
    static bool initialized;
    static int64_t limit = XEMU_XBE_IRET_DEFAULT_LIMIT;

    if (initialized) {
        return limit;
    }

    initialized = true;
    limit = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_IRET_LIMIT",
        "xbe_iret_limit.txt",
        XEMU_XBE_IRET_DEFAULT_LIMIT);

    return limit;
}

static uint64_t xemu_xbe_kernel_loop_probe_min_hits(void)
{
    static bool initialized;
    static uint64_t min_hits = XEMU_XBE_KERNEL_LOOP_DEFAULT_MIN_HITS;
    int64_t value;

    if (initialized) {
        return min_hits;
    }

    initialized = true;
    value = xemu_xbe_boot_trace_limit_setting(
        "XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_MIN_HITS",
        "xbe_kernel_loop_min_hits.txt",
        XEMU_XBE_KERNEL_LOOP_DEFAULT_MIN_HITS);
    if (value <= 0) {
        fprintf(stderr,
                "Invalid XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_MIN_HITS=%" PRId64
                "; using %d\n",
                value, XEMU_XBE_KERNEL_LOOP_DEFAULT_MIN_HITS);
        min_hits = XEMU_XBE_KERNEL_LOOP_DEFAULT_MIN_HITS;
    } else {
        min_hits = value;
    }

    return min_hits;
}

static uint64_t xemu_xbe_entry_target_window(void)
{
    static bool initialized;
    static uint64_t window = XEMU_XBE_ENTRY_TARGET_DEFAULT_WINDOW;
    const char *value;
    char *end = NULL;

    if (initialized) {
        return window;
    }

    initialized = true;
    value = getenv("XEMU_BOOT_TRACE_XBE_ENTRY_TARGET_WINDOW");
    if (!value || !value[0]) {
        return window;
    }

    window = g_ascii_strtoull(value, &end, 10);
    if (end == value || window == 0) {
        fprintf(stderr,
                "Invalid XEMU_BOOT_TRACE_XBE_ENTRY_TARGET_WINDOW='%s'; using %d\n",
                value, XEMU_XBE_ENTRY_TARGET_DEFAULT_WINDOW);
        window = XEMU_XBE_ENTRY_TARGET_DEFAULT_WINDOW;
    }

    return window;
}

static uint64_t xemu_xbe_exec_probe_stride(void)
{
    static bool initialized;
    static uint64_t stride = XEMU_XBE_EXEC_PROBE_DEFAULT_STRIDE;
    char file_value[64];
    const char *value;
    const char *source = "XEMU_BOOT_TRACE_XBE_EXEC_PROBE_STRIDE";
    char *end = NULL;

    if (initialized) {
        return stride;
    }

    initialized = true;
    value = getenv("XEMU_BOOT_TRACE_XBE_EXEC_PROBE_STRIDE");
    if (!value || !value[0]) {
        if (!xemu_xbe_boot_trace_read_fixture_setting(
                "xbe_exec_probe_stride.txt", file_value,
                sizeof(file_value))) {
            return stride;
        }
        value = file_value;
        source = "xbe_exec_probe_stride.txt";
    }

    stride = g_ascii_strtoull(value, &end, 10);
    if (end == value || stride == 0) {
        fprintf(stderr, "Invalid %s='%s'; using %d\n",
                source, value, XEMU_XBE_EXEC_PROBE_DEFAULT_STRIDE);
        stride = XEMU_XBE_EXEC_PROBE_DEFAULT_STRIDE;
    }

    return stride;
}

static const char *xemu_xbe_probe_virtual_header(vaddr image_base,
                                                 hwaddr *phys_addr,
                                                 uint32_t *sig)
{
    *phys_addr = 0;
    *sig = 0;

    if (virt_to_phys(image_base, phys_addr) != 0) {
        return "unmapped";
    }

    if (virt_dma_memory_read(image_base, sig, sizeof(*sig)) != sizeof(*sig)) {
        return "read-fail";
    }

    if (ldl_le_p(sig) == 0x48454258) {
        return "xbeh-present";
    }

    return "mapped-non-xbe";
}

void xemu_xbe_boot_trace_observe_dma_read(int64_t read_lba, int nsectors)
{
    static uint64_t progress_mark_count;
    const struct xemu_xbe_dma_header_observation *obs =
        &xemu_xbe_dma_observation;
    uint64_t expected_sectors;
    uint64_t read_start;
    uint64_t read_end;
    uint64_t old_contiguous;
    uint64_t new_contiguous;
    uint64_t pc = 0;
    hwaddr phys_addr = 0;
    uint32_t sig = 0;
    bool pc_known;
    bool complete;
    const char *status;
    struct xemu_xbe_page_probe page_probe;

    if (!obs->present || !xemu_xbe_boot_trace_enabled() ||
        read_lba < obs->read_lba || nsectors <= 0 || obs->image_size == 0) {
        return;
    }

    expected_sectors = DIV_ROUND_UP((uint64_t)obs->image_size,
                                    XEMU_XBE_IDE_SECTOR_SIZE);
    if ((uint64_t)(read_lba - obs->read_lba) >= expected_sectors) {
        return;
    }

    read_start = (uint64_t)(read_lba - obs->read_lba) *
                 XEMU_XBE_IDE_SECTOR_SIZE;
    read_end = read_start + (uint64_t)nsectors * XEMU_XBE_IDE_SECTOR_SIZE;
    read_end = MIN(read_end, (uint64_t)obs->image_size);
    old_contiguous = xemu_xbe_dma_observation.contiguous_bytes;
    new_contiguous = old_contiguous;
    if (read_start <= old_contiguous && read_end > old_contiguous) {
        new_contiguous = read_end;
        xemu_xbe_dma_observation.contiguous_bytes = new_contiguous;
    }

    complete = new_contiguous >= obs->image_size;
    if (new_contiguous == old_contiguous && !complete) {
        return;
    }

    if (progress_mark_count >= (uint64_t)xemu_xbe_read_progress_limit()) {
        return;
    }

    status = xemu_xbe_probe_virtual_header(obs->image_base, &phys_addr, &sig);
    xemu_xbe_probe_page_tables(obs->image_base, &page_probe);
    pc_known = xemu_xbe_current_pc(&pc);

    progress_mark_count++;
    fprintf(stderr,
            "BOOT_MARK b6 dashboard=xbe-read-progress context=%s"
            " observed_seq=%" PRIu64
            " read_lba=%" PRId64
            " nsectors=%d"
            " start_lba=%" PRId64
            " expected_sectors=%" PRIu64
            " contiguous_bytes=%" PRIu64
            " image_size=%" PRIu32
            " complete=%s"
            " guest_addr=0x%08" PRIx32
            " status=%s"
            " phys_addr=0x%08" PRIx64
            " sig=0x%08" PRIx32
            " guest_pc=0x%08" PRIx64
            " pc_known=%s"
            " page_status=%s"
            " cr0=0x%08" PRIx64
            " cr3=0x%08" PRIx64
            " cr4=0x%08" PRIx64
            " pde_addr=0x%08" PRIx64
            " pde=0x%016" PRIx64
            " pte_addr=0x%08" PRIx64
            " pte=0x%016" PRIx64
            " source=ide-dma-read-progress\n",
            xemu_xbe_boot_trace_context(), obs->sequence, read_lba, nsectors,
            obs->read_lba, expected_sectors, new_contiguous, obs->image_size,
            complete ? "yes" : "no", obs->image_base, status,
            (uint64_t)phys_addr, ldl_le_p(&sig), pc,
            pc_known ? "yes" : "no", page_probe.status, page_probe.cr0,
            page_probe.cr3, page_probe.cr4, (uint64_t)page_probe.pde_addr,
            page_probe.pde, (uint64_t)page_probe.pte_addr, page_probe.pte);

    if (ldl_le_p(&sig) == 0x48454258) {
        xemu_xbe_boot_trace_probe();
    }

    if (complete && !xemu_xbe_dma_observation.read_complete_marked &&
        progress_mark_count < (uint64_t)xemu_xbe_read_progress_limit()) {
        xemu_xbe_dma_observation.read_complete_marked = true;
        progress_mark_count++;
        fprintf(stderr,
                "BOOT_MARK b6 dashboard=xbe-read-complete context=%s"
                " observed_seq=%" PRIu64
                " start_lba=%" PRId64
                " expected_sectors=%" PRIu64
                " contiguous_bytes=%" PRIu64
                " image_size=%" PRIu32
                " guest_addr=0x%08" PRIx32
                " status=%s"
                " phys_addr=0x%08" PRIx64
                " sig=0x%08" PRIx32
                " guest_pc=0x%08" PRIx64
                " pc_known=%s"
                " page_status=%s"
                " cr0=0x%08" PRIx64
                " cr3=0x%08" PRIx64
                " cr4=0x%08" PRIx64
                " pde_addr=0x%08" PRIx64
                " pde=0x%016" PRIx64
                " pte_addr=0x%08" PRIx64
                " pte=0x%016" PRIx64
                " source=ide-dma-read-complete\n",
                xemu_xbe_boot_trace_context(), obs->sequence, obs->read_lba,
                expected_sectors, new_contiguous, obs->image_size,
                obs->image_base, status, (uint64_t)phys_addr, ldl_le_p(&sig),
                pc, pc_known ? "yes" : "no", page_probe.status,
                page_probe.cr0, page_probe.cr3, page_probe.cr4,
                (uint64_t)page_probe.pde_addr, page_probe.pde,
                (uint64_t)page_probe.pte_addr, page_probe.pte);
    }
}

static void xemu_xbe_boot_trace_virtual_probe(void)
{
    static int64_t last_probe_us;
    static uint64_t probe_count;
    static uint64_t last_sequence;
    static uint32_t last_sig = UINT32_MAX;
    static char last_status[32];

    const struct xemu_xbe_dma_header_observation *obs = &xemu_xbe_dma_observation;
    int64_t limit;
    int64_t now_us;
    hwaddr phys_addr = 0;
    uint32_t sig = 0;
    uint64_t pc = 0;
    bool pc_known;
    const char *status;
    struct xemu_xbe_page_probe page_probe;

    if (!obs->present || !xemu_xbe_boot_trace_enabled()) {
        return;
    }

    limit = xemu_xbe_virtual_probe_limit();
    if (limit == 0 || probe_count >= (uint64_t)limit) {
        return;
    }

    status = xemu_xbe_probe_virtual_header(obs->image_base, &phys_addr, &sig);
    xemu_xbe_probe_page_tables(obs->image_base, &page_probe);

    now_us = g_get_monotonic_time();
    if (obs->sequence == last_sequence &&
        sig == last_sig &&
        g_strcmp0(status, last_status) == 0 &&
        last_probe_us &&
        now_us - last_probe_us < XEMU_XBE_VIRTUAL_PROBE_INTERVAL_US) {
        return;
    }

    last_sequence = obs->sequence;
    last_sig = sig;
    g_strlcpy(last_status, status, sizeof(last_status));
    last_probe_us = now_us;
    probe_count++;
    pc_known = xemu_xbe_current_pc(&pc);

    fprintf(stderr,
            "BOOT_MARK b6 dashboard=xbe-virtual-probe context=%s"
            " status=%s"
            " observed_seq=%" PRIu64
            " guest_addr=0x%08" PRIx32
            " phys_addr=0x%08" PRIx64
            " sig=0x%08" PRIx32
            " image_size=%" PRIu32
            " headers_size=%" PRIu32
            " entry=0x%08" PRIx32
            " dma_addr=0x%08" PRIx64
            " guest_pc=0x%08" PRIx64
            " pc_known=%s"
            " page_status=%s"
            " cr0=0x%08" PRIx64
            " cr3=0x%08" PRIx64
            " cr4=0x%08" PRIx64
            " efer=0x%08" PRIx64
            " pdpe_addr=0x%08" PRIx64
            " pdpe=0x%016" PRIx64
            " pde_addr=0x%08" PRIx64
            " pde=0x%016" PRIx64
            " pte_addr=0x%08" PRIx64
            " pte=0x%016" PRIx64
            " source=virtual-probe\n",
            xemu_xbe_boot_trace_context(), status, obs->sequence,
            obs->image_base, (uint64_t)phys_addr, ldl_le_p(&sig),
            obs->image_size, obs->headers_size, obs->entry,
            obs->dma_addr, pc, pc_known ? "yes" : "no",
            page_probe.status, page_probe.cr0, page_probe.cr3,
            page_probe.cr4, page_probe.efer,
            (uint64_t)page_probe.pdpe_addr, page_probe.pdpe,
            (uint64_t)page_probe.pde_addr, page_probe.pde,
            (uint64_t)page_probe.pte_addr, page_probe.pte);
}

bool xemu_xbe_boot_trace_probe(void)
{
    struct xbe *xbe;
    uint32_t base;
    uint32_t image_size;
    uint32_t headers_size;
    uint32_t entry;
    uint32_t title_id;
    hwaddr phys_addr = 0;
    uint64_t end;
    uint64_t pc;
    const char *context;
    bool virtual_header = true;

    if (!xemu_xbe_boot_trace_enabled()) {
        return false;
    }

    xbe = xemu_get_xbe_info();
    if (!xbe || !xbe->header || !xbe->cert) {
        xemu_xbe_boot_trace_virtual_probe();
        xbe = xemu_get_xbe_info_from_phys_scan(&phys_addr);
        virtual_header = false;
    }
    if (!xbe || !xbe->header || !xbe->cert) {
        if (xemu_xbe_current_pc(&pc)) {
            xemu_xbe_boot_trace_mark_executed(pc, 1, "pc-sample");
        }
        return false;
    }

    base = ldl_le_p(&xbe->header->m_base);
    image_size = ldl_le_p(&xbe->header->m_sizeof_image);
    headers_size = ldl_le_p(&xbe->header->m_sizeof_headers);
    entry = ldl_le_p(&xbe->header->m_entry);
    title_id = ldl_le_p(&xbe->cert->m_titleid);
    end = (uint64_t)base + image_size;
    context = xemu_xbe_boot_trace_context();

    if (!image_size || end <= base) {
        return false;
    }

    if (!virtual_header) {
        if (!xemu_xbe_loaded_observation.header_resident_marked) {
            xemu_xbe_loaded_observation.header_resident_marked = true;
            fprintf(stderr,
                    "BOOT_MARK b6 dashboard=xbe-header-resident context=%s"
                    " guest_addr=0x%08" PRIx32
                    " image_size=%" PRIu32
                    " headers_size=%" PRIu32
                    " entry=0x%08" PRIx32
                    " title_id=0x%08" PRIx32
                    " source=physical-scan"
                    " phys_addr=0x%08" PRIx64 "\n",
                    context, base, image_size, headers_size, entry, title_id,
                    (uint64_t)phys_addr);
        }
        return false;
    }

    if (virt_to_phys(base, &phys_addr) != 0) {
        phys_addr = 0;
    }

    xemu_xbe_loaded_observation.base = base;
    xemu_xbe_loaded_observation.size = image_size;
    xemu_xbe_loaded_observation.headers_size = headers_size;
    xemu_xbe_loaded_observation.entry = entry;

    if (!xemu_xbe_loaded_observation.loaded_marked) {
        xemu_xbe_loaded_observation.loaded_marked = true;
        fprintf(stderr,
                "BOOT_MARK b6 dashboard=xbe-loaded context=%s"
                " guest_addr=0x%08" PRIx32
                " image_size=%" PRIu32
                " headers_size=%" PRIu32
                " entry=0x%08" PRIx32
                " title_id=0x%08" PRIx32
                " source=virtual-header"
                " phys_addr=0x%08" PRIx64 "\n",
                context, base, image_size, headers_size, entry, title_id,
                (uint64_t)phys_addr);
    }

    xemu_xbe_boot_trace_section_map(xbe, context, "loaded");

    if (!xemu_xbe_loaded_observation.entry_marked &&
        xemu_xbe_loaded_observation.entry_probe_count <
            XEMU_XBE_ENTRY_PROBE_DEFAULT_LIMIT) {
        xemu_xbe_loaded_observation.entry_probe_count++;
        xemu_xbe_loaded_observation.entry_marked =
            xemu_xbe_boot_trace_entry_probe(entry, context);
    }
    if (xemu_xbe_loaded_observation.entry_marked) {
        xemu_xbe_boot_trace_section_map(xbe, context, "entry-ready");
        xemu_xbe_boot_trace_executed_detector_proof(
            entry, 1, "entry", "entry-ready");
        xemu_xbe_boot_trace_memory_watch_install();
    }

    if (xemu_xbe_current_pc(&pc)) {
        xemu_xbe_boot_trace_mark_executed(pc, 1, "pc-sample");
    }

    return xemu_xbe_loaded_observation.loaded_marked;
}
