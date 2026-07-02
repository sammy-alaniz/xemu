# 331. PCRTC IRQ Pending No Vector Loop Check

## Purpose

Run the required bounded sub-agent loop check after
`history/330-pcrtc-irq-pending-no-vector-static.md`, including the requested
progress-method critique.

## Exact Commands

No shell command. Spawned a bounded read-only sub-agent checkpoint.

## Inputs / Artifacts

- `history/330-pcrtc-irq-pending-no-vector-static.md`
- Current B6/main-menu goal and loop-control rules from `goal.md` /
  `AGENTS.md`
- Browser runtime artifact:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log`

## Loop-Guard Field

`cpu_hard_request_cleared_without_service_reason`

## Findings

The sub-agent judged `history/330` as genuinely new progress. It proves the
PCRTC interrupt is no longer stuck inside NV2A and is not blocked by the prior
BQL issue, because the browser artifact reaches visible `CPU_INTERRUPT_HARD`.
The remaining boundary is narrower: the CPU hard-interrupt request exists, then
disappears or is bypassed before PIC ack, CPU hard-IRQ service, or IRET.

The sub-agent recommended the next action be code inspection, not another
runtime. The focused inspection should follow the i386/QEMU hard-interrupt
delivery path from `CPU_INTERRUPT_HARD` pending to PIC vector fetch/service and
look for where the request can be cleared or ignored without a `pic=irq-ack` or
`cpu=hard-irq-service` marker.

## Decision

Continue, but do not run another timing/runtime variant yet.

## Next Step

Inspect the interrupt-delivery path and explain:
`cpu_hard_request_cleared_without_service_reason`.

## Loop-check progress-method critique included

Yes.

## Progress-method critique summary

The sub-agent said the method is still converging because the sequence has
narrowed from BQL abort, to IRQ assert, to CPU hard request, to no vector
service. It recommended continuing static code/log ordering checks and
single-field probes tied to dashboard execution. It also recommended stopping
runtime variants around pump, vblank, PIT, precommit, and final-window timing
unless the next field specifically requires one. The causal metric remains
valid only if it stays on interrupt delivery, tick accumulation, and strict
mapped XBE execution; raw timer counts and detector-proof markers must remain
diagnostic only.
