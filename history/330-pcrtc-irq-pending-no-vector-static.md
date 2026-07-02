# 330. PCRTC IRQ Pending No Vector Static

## Purpose

Inspect why the final-window PCRTC interrupt reaches CPU hard-interrupt pending
state in the browser runtime artifact but does not produce a pre-stream CPU
hard-IRQ service, PIC ack, or IRET marker before the guest polls and clears the
NV2A interrupt state.

## Exact Commands

```sh
rg -n "observe_cpu_hard_irq|cpu=hard-irq|observe_pic|pic=irq|observe_iret|BOOT_MARK b6 iret|vector=0x30|interrupt-vector|interrupt.*vector|XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY|irq_after_pfifo" . --glob '!build-real-b3-matrix/**' --glob '!history/**'
sed -n '2698,2748p' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log
sed -n '1288,1340p' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log
rg -n "cpu_interrupt_request=0x00000002|pending_interrupt=yes|cpu_exit_request=yes|pcrtc_pending=0x00000001|pmc_pending=0x01000000|op=intr-clear value=0x00000001|NV_PMC_INTR_0|NV_PMC_INTR_EN_0" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log
sed -n '6400,6555p' xemu-xbe.c
sed -n '6730,6795p' xemu-xbe.c
sed -n '960,1000p' xemu-xbe.c
sed -n '1128,1150p' xemu-xbe.c
sed -n '1215,1240p' xemu-xbe.c
sed -n '2678,2702p' xemu-xbe.c
sed -n '10455,10485p' xemu-xbe.c
sed -n '205,235p' target/i386/tcg/system/seg_helper.c
sed -n '2248,2292p' target/i386/tcg/seg_helper.c
sed -n '70,90p' hw/core/cpu-common.c
rg -n "nv2a_wait_snapshot_is_pfifo_empty|irq_trace_gate_allows|observe_pic_irq_line|observe_pic_irq_ack|irq_watch_matches|xbox_pci|qemu_set_irq|pci_irq_assert|pci_irq_deassert" xemu-xbe.c hw/intc/i8259.c hw/xbox/xbox_pci.c hw/xbox/nv2a/nv2a.c include/hw/pci/pci_device.h hw/pci/pci.c
sed -n '5200,5360p' xemu-xbe.c
sed -n '6290,6365p' xemu-xbe.c
sed -n '10480,10540p' xemu-xbe.c
sed -n '130,245p' hw/intc/i8259.c
sed -n '90,170p' hw/xbox/xbox_pci.c
sed -n '200,230p' hw/xbox/xbox_pci.c
rg -n "lpc=.*route|lpc=irq|irq-route|source=.*pirq|source=.*nv|guest_irq|pic=irq-line|pic=irq-ack|nv2a=irq-line|nv2a=irq-source" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log | sed -n '1,220p'
rg -n "pci_irq_assert|pci_irq_deassert|pci_set_irq|pci_change_irq_level|pci_irq_handler|map_irq|xbox_lpc_map_irq|xbox_lpc_set_irq" hw include | head -n 200
sed -n '170,230p' hw/xbox/xbox_pci.c
sed -n '230,290p' hw/xbox/xbox_pci.c
rg -n "xemu_xbe_boot_trace_observe_lpc_irq_route|lpc=|irq-route" xemu-xbe.c xemu-xbe.h hw/xbox/xbox_pci.c
```

## Inputs / Artifacts

- Browser runtime artifact:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log`
- Trace hooks and filters in `xemu-xbe.c`
- CPU hard-IRQ/IRET hooks in `target/i386/tcg/system/seg_helper.c`,
  `target/i386/tcg/seg_helper.c`, and `hw/core/cpu-common.c`
- PCI/LPC IRQ routing code in `hw/xbox/xbox_pci.c`

## Loop-Guard Field

`pcrtc_irq_pending_but_no_pre_stream_vector_service`

## Findings

`target/i386/tcg/system/seg_helper.c` emits `cpu=hard-irq-service` around
`do_interrupt_x86_hardirq()`, `target/i386/tcg/seg_helper.c` emits
`cpu=iret`, and `hw/core/cpu-common.c` emits `cpu=hard-irq op=reset` when
`CPU_INTERRUPT_HARD` is cleared. If the final-window PCRTC interrupt were being
serviced after the PFIFO-empty snapshot, those markers should be visible.

The browser log shows the final-window PCRTC gate allowed once, then
`nv2a=irq-line line=assert reason=pcrtc`, then the PFIFO stream-idle transition
with `pmc_pending=0x01000000`, `pcrtc_pending=0x00000001`,
`cpu_interrupt_request=0x00000002`, `pending_interrupt=yes`, and
`cpu_exit_request=yes`. This proves the IRQ escaped the NV2A internal state and
became a visible CPU hard-interrupt request.

By the later PFIFO stream-idle boundary snapshot, `cpu_interrupt_request` is
already zero while `pmc_pending=0x01000000` and `pcrtc_pending=0x00000001` are
still pending. The guest then reads `NV_PMC_INTR_EN_0` and `NV_PMC_INTR_0` at
`eip=0x80045b15` / `0x80045b23`, observes `NV_PMC_INTR_0=0x01000000`, later
writes `NV_PMC_INTR_EN_0=0`, and finally clears the PCRTC interrupt source.

There is no pre-stream `cpu=hard-irq op=reset`, `pic=irq-ack`,
`cpu=hard-irq-service`, or `cpu=iret` marker for the PCRTC path. The exact
hard-IRQ marker that later appears belongs to the host-pump/PIT IRQ0 path, not
to the final-window PCRTC IRQ.

The trace filter does not explain the absence. The run uses PFIFO-empty gated
IRQ tracing, and the relevant post-transition state has a PFIFO-empty snapshot,
so a real post-empty service/ack/reset/IRET should not be suppressed by
`xemu_xbe_irq_trace_gate_allows()`.

PCI/LPC routing inspection shows `nv2a_update_irq()` asserts the PCI IRQ and
the Xbox PCI path maps NV2A through the LPC PIRQ route. The absence of
route-level markers before PFIFO empty is plausibly filter-related, but the
`CPU_INTERRUPT_HARD` state at stream-idle transition proves routing reached the
CPU interrupt-request level.

## Decision

The blocker is no longer BQL ownership or an NV2A-local pending bit. It is
delivery/order after the CPU hard-interrupt request is visible: the guest
continues into the PMC polling/clear path before a CPU hard-IRQ vector service,
PIC ack, and IRET are observed for this PCRTC interrupt.

## Next Step

Run the required bounded loop check before any further probe or code change.
The next approved slice should stay focused on why a visible
`CPU_INTERRUPT_HARD` request at the final PFIFO stream-idle transition is not
scheduled into a pre-stream hard-IRQ vector service before the guest polls and
clears PMC/PCRTC state.

## Loop-check progress-method critique included

No. This entry records the static inspection that must be reviewed by the next
loop-check entry.

## Progress-method critique summary

Pending loop-check review.
