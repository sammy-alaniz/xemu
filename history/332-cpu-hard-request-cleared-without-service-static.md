# 332. CPU Hard Request Cleared Without Service Static

## Purpose

Explain `cpu_hard_request_cleared_without_service_reason` for the
final-window PCRTC browser artifact.

## Exact Commands

```sh
rg -n "CPU_INTERRUPT_HARD|do_interrupt_x86_hardirq|cpu_handle_interrupt|cpu_handle_exception|interrupt_request|cpu_reset_interrupt" accel target include hw system --glob '!build-real-b3-matrix/**'
rg -n "cpu=hard-irq|hard-irq-service|observe_cpu_hard_irq|observe_pic_irq_ack|observe_pic_irq_line|cpu_interrupt|cpu_reset_interrupt" xemu-xbe.c hw/intc target/i386 hw/core include --glob '!build-real-b3-matrix/**'
rg -n "do_interrupt_x86_hardirq|pic_read_irq|cpu_get_pic_interrupt|apic_get_interrupt|env->eflags|IF_MASK|HF_INHIBIT_IRQ_MASK|hflags" target/i386 hw/intc include --glob '!build-real-b3-matrix/**'
sed -n '850,970p' accel/tcg/cpu-exec.c
sed -n '1038,1145p' accel/tcg/cpu-exec.c
sed -n '130,238p' target/i386/tcg/system/seg_helper.c
sed -n '9850,9898p' target/i386/cpu.c
rg -n "tick-block|hard-irq-defer|cpu=hard-irq|cpu=hard-irq-service|pic=irq-ack|pic=irq-line|pcrtc|NV_PMC_INTR_0|NV_PMC_INTR_EN_0|pfifo=stream-idle" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log
rg -n "tick-block|hard-irq-defer|cpu=hard-irq op=reset|cpu=hard-irq-service|pic=irq-ack|pic=irq-line" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log
sed -n '2688,2768p' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log
sed -n '1188,1240p' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log
rg -n "tick_block_irq_defer|xemu_xbe_boot_trace_defer_cpu_hard_irq_service|defer_cpu_hard|tick_block_pre|tick_block_post|XEMU_BOOT_TRACE_XBE_TICK_BLOCK" xemu-xbe.c xemu-xbe.h accel/tcg/cpu-exec.c scripts docs
sed -n '4480,4750p' xemu-xbe.c
sed -n '6600,6728p' xemu-xbe.c
sed -n '970,1045p' accel/tcg/cpu-exec.c
sed -n '1145,1235p' accel/tcg/cpu-exec.c
sed -n '60,90p' hw/core/cpu-common.c
sed -n '6728,6845p' xemu-xbe.c
sed -n '130,245p' hw/intc/i8259.c
sed -n '245,330p' hw/intc/i8259.c
sed -n '250,285p' system/cpus.c
rg -n "CPU_INTERRUPT_HARD\\)|CPU_INTERRUPT_HARD \\||CPU_INTERRUPT_HARD\\s*\\||CPU_INTERRUPT_HARD,|cpu_reset_interrupt\\([^\\n]*CPU_INTERRUPT_HARD|cpu_interrupt\\([^\\n]*CPU_INTERRUPT_HARD" hw/intc hw/i386 hw/xbox target/i386 system accel include
sed -n '1,130p' hw/intc/i8259.c
sed -n '285,380p' hw/intc/i8259.c
sed -n '40,75p' hw/i386/x86-cpu.c
sed -n '2748,2820p' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log
sed -n '2704,2724p' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log
sed -n '75,130p' hw/i386/x86-cpu.c
sed -n '170,290p' hw/xbox/xbox_pci.c
rg -n "irq=3|guest_irq=3|irq=0|guest_irq=0|irq-line|cpu=hard-irq context=browser-runtime seq=|cpu=hard-irq-service|pic=irq-ack" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log
rg -n "pic_irq_request|x86_pic_interrupt|pic_update_irq|qemu_irq_raise|qemu_irq_lower|pic_get_irq|imr=0x92|isr=0x08|irr_before=0x08|irr_after=0x08" hw/intc hw/i386 build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log
sed -n '2694,2708p' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log
rg -n "lpc=|irq-route|guest_irq=3|irq=3|pirq|PIRQ|cpu=hard-irq context=.*seq=|pic=irq-ack|hard-irq-service" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log
sed -n '10480,10540p' xemu-xbe.c
sed -n '5200,5368p' xemu-xbe.c
rg -n "xemu_xbe_irq_trace_gate_allows|irq_trace_gate_allows" xemu-xbe.c
sed -n '960,1005p' xemu-xbe.c
sed -n '6300,6368p' xemu-xbe.c
sed -n '6410,6505p' xemu-xbe.c
sed -n '6505,6595p' xemu-xbe.c
```

## Inputs / Artifacts

- Browser runtime artifact:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log`
- TCG main execution loop in `accel/tcg/cpu-exec.c`
- i386 hard IRQ delivery in `target/i386/tcg/system/seg_helper.c` and
  `target/i386/cpu.c`
- PIC/CPU IRQ bridge in `hw/intc/i8259.c` and `hw/i386/x86-cpu.c`
- Xbox PCI/LPC routing in `hw/xbox/xbox_pci.c`
- Trace hooks in `xemu-xbe.c`

## Loop-Guard Field

`cpu_hard_request_cleared_without_service_reason`

## Findings

The standard TCG path checks interrupts before the next TB in
`cpu_handle_interrupt()`. For x86, `x86_cpu_pending_interrupt()` only allows
`CPU_INTERRUPT_HARD` through when GIF is enabled, guest IF is set, and
`HF_INHIBIT_IRQ_MASK` is clear. If it proceeds, `x86_cpu_exec_interrupt()` calls
`cpu_reset_interrupt(CPU_INTERRUPT_HARD | CPU_INTERRUPT_VIRQ)`,
`cpu_get_pic_interrupt()`, `pic_read_irq()`, and then
`do_interrupt_x86_hardirq()`. Those calls should emit `cpu=hard-irq op=reset`,
`pic=irq-ack`, `cpu=hard-irq-service`, and later `cpu=iret` markers.

The xemu tick-block hard-IRQ defer path is not the cause for this artifact. The
defer code is quarantined with `active=false`, the log has no
`tick-block-irq-defer` marker, and the final-window transition is not consuming
the request through that experimental path.

The missing-service explanation is the level-driven PIC/CPU line behavior. In
`hw/i386/x86-cpu.c`, `pic_irq_request()` calls
`cpu_interrupt(CPU_INTERRUPT_HARD)` when the PIC output line is high, and
`cpu_reset_interrupt(CPU_INTERRUPT_HARD)` when that output line lowers. That
means a CPU hard-interrupt request can be cleared without `pic_read_irq()` if
the device/PIC output deasserts before x86 services the interrupt.

The browser log matches that pattern. At the final-window PCRTC raise, the
artifact records:

- `nv2a=irq-line ... line=assert reason=pcrtc`
- `pfifo=stream-idle-transition ... cpu_interrupt_request=0x00000002
  pending_interrupt=yes cpu_exit_request=yes`
- Then `pfifo=stream-idle-boundary ... eip=0x80045b15 ...
  cpu_interrupt_request=0x00000000 pending_interrupt=no`
- The guest immediately reads `NV_PMC_INTR_EN_0` and `NV_PMC_INTR_0`, seeing
  `NV_PMC_INTR_0=0x01000000`
- The guest later writes `NV_PMC_INTR_EN_0=0`, after which
  `nv2a=irq-line ... line=deassert reason=pcrtc ... pmc_enabled=0x00000000`
  and finally `nv2a=irq-source ... source=pcrtc op=intr-clear`

There is no PCRTC `pic=irq-ack`, `cpu=hard-irq-service`, or `cpu=iret` marker.
The only visible post-empty `cpu=hard-irq op=set` marker is later and belongs
to the PIT/IRQ0 path after the host timer pump, not to the final-window PCRTC
raise. The IRQ0 lines also show PIC priority state with `isr=0x08`, which means
an IRQ3/PIRQ-class interrupt was already in service or blocking lower-priority
IRQ0 behavior.

Because `XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1` is active and
`XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0`, some pre-empty route/set/reset markers for
the PCRTC/PIRQ3 path can be filtered out. That does not weaken the conclusion:
the stream-idle transition snapshot proves CPU hard request visibility, and
the later guest PMC polling/disable/clear sequence proves no vector service
occurred before the guest handled the pending state by polling.

## Decision

`cpu_hard_request_cleared_without_service_reason` is:
`level-pic-output-lowered-before-x86-vector-service`.

The PCRTC interrupt becomes a CPU hard-interrupt request, but it is not latched
as a delivered CPU vector. Before x86 calls `pic_read_irq()`, the line state
can drop and `pic_irq_request(..., level=0)` can clear `CPU_INTERRUPT_HARD`.
The guest then observes and clears the device interrupt through PMC polling
rather than through a hard-IRQ service path.

## Next Step

Run the required loop check. The next slice should decide whether to revise the
approach away from forcing PCRTC delivery and toward the actual causal miss:
the browser is still not reaching the native-like pre-service tick state before
the shared poll. If another code change is approved, it must name a field such
as `pcrtc_irq3_pic_ack_before_guest_pmc_poll` or reject PCRTC forcing as a
non-causal branch.

## Loop-check progress-method critique included

No. This static finding must be reviewed by the next loop-check entry.

## Progress-method critique summary

Pending loop-check review.
