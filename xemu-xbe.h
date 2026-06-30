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

#ifndef XEMU_XBE_H
#define XEMU_XBE_H

#include <stdbool.h>
#include <stdint.h>

// http://www.caustik.com/cxbx/download/xbe.htm
#pragma pack(1)
struct xbe_header
{
    uint32_t m_magic;                         // magic number [should be "XBEH"]
    uint8_t  m_digsig[256];                   // digital signature
    uint32_t m_base;                          // base address
    uint32_t m_sizeof_headers;                // size of headers
    uint32_t m_sizeof_image;                  // size of image
    uint32_t m_sizeof_image_header;           // size of image header
    uint32_t m_timedate;                      // timedate stamp
    uint32_t m_certificate_addr;              // certificate address
    uint32_t m_sections;                      // number of sections
    uint32_t m_section_headers_addr;          // section headers address

    struct init_flags
    {
        uint32_t m_mount_utility_drive    : 1;  // mount utility drive flag
        uint32_t m_format_utility_drive   : 1;  // format utility drive flag
        uint32_t m_limit_64mb             : 1;  // limit development kit run time memory to 64mb flag
        uint32_t m_dont_setup_harddisk    : 1;  // don't setup hard disk flag
        uint32_t m_unused                 : 4;  // unused (or unknown)
        uint32_t m_unused_b1              : 8;  // unused (or unknown)
        uint32_t m_unused_b2              : 8;  // unused (or unknown)
        uint32_t m_unused_b3              : 8;  // unused (or unknown)
    } m_init_flags;

    uint32_t m_entry;                         // entry point address
    uint32_t m_tls_addr;                      // thread local storage directory address
    uint32_t m_pe_stack_commit;               // size of stack commit
    uint32_t m_pe_heap_reserve;               // size of heap reserve
    uint32_t m_pe_heap_commit;                // size of heap commit
    uint32_t m_pe_base_addr;                  // original base address
    uint32_t m_pe_sizeof_image;               // size of original image
    uint32_t m_pe_checksum;                   // original checksum
    uint32_t m_pe_timedate;                   // original timedate stamp
    uint32_t m_debug_pathname_addr;           // debug pathname address
    uint32_t m_debug_filename_addr;           // debug filename address
    uint32_t m_debug_unicode_filename_addr;   // debug unicode filename address
    uint32_t m_kernel_image_thunk_addr;       // kernel image thunk address
    uint32_t m_nonkernel_import_dir_addr;     // non kernel import directory address
    uint32_t m_library_versions;              // number of library versions
    uint32_t m_library_versions_addr;         // library versions address
    uint32_t m_kernel_library_version_addr;   // kernel library version address
    uint32_t m_xapi_library_version_addr;     // xapi library version address
    uint32_t m_logo_bitmap_addr;              // logo bitmap address
    uint32_t m_logo_bitmap_size;              // logo bitmap size
};

struct xbe_certificate
{
    uint32_t m_size;                          // size of certificate
    uint32_t m_timedate;                      // timedate stamp
    uint32_t m_titleid;                       // title id
    uint16_t m_title_name[40];                // title name (unicode)
    uint32_t m_alt_title_id[0x10];            // alternate title ids
    uint32_t m_allowed_media;                 // allowed media types
    uint32_t m_game_region;                   // game region
    uint32_t m_game_ratings;                  // game ratings
    uint32_t m_disk_number;                   // disk number
    uint32_t m_version;                       // version
    uint8_t  m_lan_key[16];                   // lan key
    uint8_t  m_sig_key[16];                   // signature key
    uint8_t  m_title_alt_sig_key[16][16];     // alternate signature keys
};

struct xbe_section_header
{
    uint32_t m_flags;                         // section flags
    uint32_t m_virtual_addr;                  // virtual address
    uint32_t m_virtual_size;                  // virtual size
    uint32_t m_raw_addr;                      // file offset
    uint32_t m_sizeof_raw;                    // raw size
    uint32_t m_section_name_addr;             // section name address
    uint32_t m_section_name_ref_count;        // section name reference count
    uint32_t m_head_shared_page_ref_count_addr;
    uint32_t m_tail_shared_page_ref_count_addr;
    uint8_t  m_section_digest[20];            // section digest
};
#pragma pack()

struct xbe {
	// Full XBE headers, copied into an allocated buffer
	uint8_t *headers;
	uint32_t headers_len;

	// Pointers into `headers` (note: little-endian!)
	struct xbe_header *header;
	struct xbe_certificate *cert;
};

#ifdef __cplusplus
extern "C" {
#endif

// Get current XBE info
struct xbe *xemu_get_xbe_info(void);

// Poll current XBE state and emit one-shot B6 boot markers when requested.
bool xemu_xbe_boot_trace_probe(void);

// True after a B6 dashboard XBE load marker, before accepted execution evidence.
bool xemu_xbe_boot_trace_loaded(void);

// True once the B6 dashboard XBE entry code is readable.
bool xemu_xbe_boot_trace_entry_ready(void);

// True when browser host-side main-loop timer pumping is allowed for the
// current B6 diagnostic point.
bool xemu_xbe_boot_trace_main_loop_timer_pump_ready(void);

// True when the active browser timer diagnostic should run one QEMU-thread
// main-loop timer pass at the PFIFO stream-idle transition edge.
bool xemu_xbe_boot_trace_main_loop_timer_pump_ready_edge_enabled(void);

// True when the PFIFO ready-edge timer diagnostic should use the native-style
// all-clocks timer dispatch instead of the bounded virtual-only dispatch.
bool xemu_xbe_boot_trace_main_loop_timer_pump_ready_edge_all_timers(void);

// True when the active browser host-side timer diagnostic should make an
// extra pump attempt immediately before the headless host loop sleeps.
bool xemu_xbe_boot_trace_main_loop_timer_pump_presleep_enabled(void);

// True once B6 dashboard XBE execution has been accepted.
bool xemu_xbe_boot_trace_executed(void);

// True after a B6 dashboard XBE DMA/header observation or load marker,
// before accepted execution evidence.
bool xemu_xbe_boot_trace_dashboard_observed(void);

// True when browser TCG-side virtual timer pumping is explicitly enabled for
// the current B6 trace point.
bool xemu_xbe_boot_trace_tcg_timer_pump_ready(void);

// True when the active browser TCG-side timer diagnostic should pump before
// executing the selected translated block instead of after it.
bool xemu_xbe_boot_trace_tcg_timer_pump_before_tb(void);

// Browser TCG-side virtual timer pump interval in translated blocks. Zero
// means disabled.
int64_t xemu_xbe_boot_trace_tcg_timer_pump_interval(void);

// True when the browser TCG-side virtual timer pump should only run timers
// explicitly marked as safe for that diagnostic pump.
bool xemu_xbe_boot_trace_tcg_timer_pump_pit_only(void);

// Mark the current thread as executing the browser TCG-side virtual timer pump
// so device-source diagnostics can attribute callbacks to that pump.
void xemu_xbe_boot_trace_enter_tcg_timer_pump(uint64_t observed_tbs,
                                              int64_t interval_tbs,
                                              int64_t virtual_now_before,
                                              int64_t virtual_deadline_before,
                                              bool virtual_has_timers_before,
                                              bool virtual_expired_before);
void xemu_xbe_boot_trace_leave_tcg_timer_pump(void);

typedef struct XemuXbeBootTraceNv2aWaitState {
    const char *source;
    const char *op;
    uint64_t seq;
    uint32_t method;
    uint32_t parameter;
    uint32_t dma_get;
    uint32_t dma_put;
    uint32_t dma_state_method;
    uint32_t dma_state_count;
    uint32_t pmc_pending;
    uint32_t pmc_enabled;
    uint32_t pfifo_pending;
    uint32_t pfifo_enabled;
    uint32_t pcrtc_pending;
    uint32_t pcrtc_enabled;
    uint32_t pgraph_pending;
    uint32_t pgraph_enabled;
    bool pfifo_known;
    bool fifo_access;
    bool pfifo_halt;
    bool pfifo_kick;
    bool pgraph_waiting_flip;
    bool pgraph_waiting_nop;
    bool pgraph_waiting_context;
} XemuXbeBootTraceNv2aWaitState;

// Record the latest diagnostic-only NV2A/PFIFO/PGRAPH wait-state snapshot.
void xemu_xbe_boot_trace_observe_nv2a_wait_state(
    const XemuXbeBootTraceNv2aWaitState *state);

typedef struct XemuXbeBootTracePfifoActivityState {
    const char *source;
    const char *phase;
    uint64_t seq;
    uint32_t method_entry;
    uint32_t method;
    uint32_t parameter;
    uint32_t dma_get_reg;
    uint32_t dma_get_local;
    uint32_t dma_get_before;
    uint32_t dma_get_after;
    uint32_t dma_put;
    uint32_t dma_state_method;
    uint32_t dma_state_count;
    uint64_t available;
    int64_t processed;
    bool active;
    bool dma_get_local_known;
    bool commit_range_known;
    bool pfifo_lock_released;
    bool pgraph_locked;
    bool final_transition_candidate;
    bool fifo_access;
    bool pgraph_waiting_flip;
    bool pgraph_waiting_nop;
    bool pgraph_waiting_context;
} XemuXbeBootTracePfifoActivityState;

// Record the latest diagnostic-only PFIFO activity phase so CPU-side probes
// can distinguish stale register snapshots from in-flight pusher work.
void xemu_xbe_boot_trace_observe_pfifo_activity(
    const XemuXbeBootTracePfifoActivityState *state);

// True when the PFIFO-side pre-commit PIT pump diagnostic should run for the
// current final stream-idle transition candidate.
bool xemu_xbe_boot_trace_pfifo_pre_commit_timer_pump_ready(
    const XemuXbeBootTracePfifoActivityState *state);

// Emit a focused B6 diagnostic marker at the PFIFO pusher-empty boundary.
void xemu_xbe_boot_trace_observe_pfifo_stream_idle_boundary(
    const XemuXbeBootTraceNv2aWaitState *state);

// Emit a focused B6 diagnostic marker when PFIFO advances into stream-idle.
void xemu_xbe_boot_trace_observe_pfifo_stream_idle_transition(
    const XemuXbeBootTraceNv2aWaitState *state,
    uint32_t dma_get_before,
    uint32_t dma_get_after,
    uint32_t dma_put,
    uint64_t available,
    int64_t processed);

// Record a B6 diagnostic PIC input-line transition after dashboard entry
// code is readable.
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
                                              int output_irq);

// Record a B6 diagnostic PIC acknowledge after dashboard entry code is readable.
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
                                             uint32_t slave_elcr);

// Record a B6 diagnostic Xbox LPC PCI/ACPI interrupt-route transition.
void xemu_xbe_boot_trace_observe_lpc_irq_route(const char *source,
                                               const char *route_type,
                                               int input_irq,
                                               int pic_irq,
                                               int level,
                                               uint32_t acpi_route,
                                               uint32_t int_route,
                                               uint32_t pirq_route,
                                               bool delivered);

// Record a B6 diagnostic Xbox PM SCI source update after dashboard entry
// code is readable.
void xemu_xbe_boot_trace_observe_xbox_pm_sci(const char *reason,
                                             int sci_level,
                                             uint16_t pm1_sts,
                                             uint16_t pm1_en,
                                             uint8_t gpe0_sts,
                                             uint8_t gpe0_en,
                                             int64_t overflow_time,
                                             bool timer_enabled);

// Record a B6 diagnostic Xbox PM1 event-register write after dashboard entry
// code is readable.
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
                                                   bool timer_enabled_after);

// Record a B6 diagnostic Xbox PM timer callback after dashboard entry code is
// readable.
void xemu_xbe_boot_trace_observe_xbox_pm_timer(const char *phase,
                                               int64_t virtual_now_ns,
                                               int64_t timer_ticks,
                                               int64_t overflow_time,
                                               uint16_t pm1_sts_before,
                                               uint16_t pm1_sts_after,
                                               uint16_t pm1_en);

// Record a B6 diagnostic AC97 bus-master interrupt source update after
// dashboard entry code is readable.
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
                                                 bool bd_valid);

// Record a B6 diagnostic AC97 bus-master programming write after dashboard
// entry code is readable.
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
                                               bool bd_valid_after);

// Record a B6 diagnostic AC97 audio callback before bus-master transfer
// processing.
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
                                               bool bd_valid);

// Record a B6 diagnostic AC97 bus-master descriptor-completion transfer after
// dashboard entry code is readable.
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
                                               bool bd_valid);

// Record a B6 diagnostic CPU_INTERRUPT_HARD set/reset transition after
// dashboard entry code is readable.
void xemu_xbe_boot_trace_observe_cpu_hard_irq(const char *op,
                                              uint32_t mask,
                                              uint32_t request_before,
                                              uint32_t request_after);

// Record a B6 diagnostic hard-IRQ service transition around x86 delivery.
void xemu_xbe_boot_trace_observe_cpu_hard_irq_service(const char *phase,
                                                      int intno);

// True when a browser-only B6 diagnostic should leave CPU_INTERRUPT_HARD
// pending until the final PFIFO stream-idle transition has been observed.
bool xemu_xbe_boot_trace_defer_cpu_hard_irq_service(void);

// Record a B6 diagnostic protected-mode IRET transition after dashboard entry
// code is readable.
void xemu_xbe_boot_trace_observe_iret(const char *phase,
                                      int shift,
                                      int next_eip);

// Record a B6 diagnostic i8254/PIT IRQ timer update after dashboard entry
// code is readable.
void xemu_xbe_boot_trace_observe_pit_irq_timer(int64_t current_time,
                                               int64_t expire_time,
                                               int irq_level,
                                               int mode,
                                               int gate,
                                               int count,
                                               int64_t count_load_time,
                                               int64_t next_transition_time);

// Record a B6 diagnostic main-loop timer pass after dashboard entry code is
// readable.
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
    bool virtual_expired_after);

// Record a browser-only B6 diagnostic timer pump from the TCG CPU loop.
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
    bool virtual_expired_after);

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
    bool virtual_expired_after);

// Record an XBE header observed in guest DMA memory for later B6 diagnostics.
void xemu_xbe_boot_trace_observe_dma_header(uint64_t dma_addr,
                                            int64_t read_lba,
                                            int nsectors,
                                            uint32_t image_base,
                                            uint32_t image_size,
                                            uint32_t headers_size,
                                            uint32_t entry);

// Record dashboard XBE IDE DMA read progress after a header observation.
void xemu_xbe_boot_trace_observe_dma_read(int64_t read_lba, int nsectors);

// Record a translated block execution PC for B6 XBE execution detection.
void xemu_xbe_boot_trace_observe_exec(uint64_t guest_pc,
                                      uint32_t tb_size,
                                      const char *source);

// Record the CPU state immediately after a translated block executes.
void xemu_xbe_boot_trace_observe_exec_transition(uint64_t start_pc,
                                                 uint32_t tb_size,
                                                 int tb_exit,
                                                 const char *source);

#ifdef __cplusplus
}
#endif

#endif
