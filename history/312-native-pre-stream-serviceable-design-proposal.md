# 312 - native pre-stream serviceable design proposal

## Purpose

Produce the design-only causal proposal requested by history/311 before any
new runtime, probe, or code change. The one field this explains is
`native_pre_stream_serviceable_state_browser_mapping`.

## Exact commands

```sh
sed -n '1,220p' goal.md
sed -n '1,220p' history/311-stable-ready-edge-strategy-note.md
git status --short
nl -ba hw/xbox/nv2a/nv2a.c | sed -n '250,380p'
nl -ba hw/xbox/nv2a/pcrtc.c | sed -n '70,150p'
nl -ba xemu-xbe.c | sed -n '1060,1160p'
nl -ba ui/xemu-headless.c | sed -n '640,835p'
nl -ba hw/xbox/nv2a/pcrtc.c | sed -n '1,90p'
nl -ba hw/xbox/nv2a/nv2a.c | sed -n '380,470p'
rg -n "pcrtc-vblank-gate|vblank-raise|nv2a_browser_pcrtc_vblank_should_raise|NV_PCRTC_INTR_0" hw/xbox/nv2a -S
rg -n "hard-irq-service|PIC|intno=0x30|cpu=hard-irq|vector=0x30" xemu-xbe.c accel/tcg/cpu-exec.c hw -S
nl -ba hw/xbox/nv2a/nv2a.c | sed -n '960,1230p'
nl -ba xemu-xbe.c | sed -n '6400,6565p'
nl -ba xemu-xbe.c | sed -n '5200,5360p'
rg -n "BOOT_MARK b6 (nv2a=irq-source|nv2a=pcrtc-vblank-gate|cpu=hard-irq-service|pic=ack|memory-watch)" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log
```

No emulator runtime was started.

## Inputs and artifacts

- Active goal and strategy:
  - `goal.md`
  - `history/311-stable-ready-edge-strategy-note.md`
- Native reference:
  - `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Stable browser CPU-flow baseline:
  - `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Static source ownership:
  - `hw/xbox/nv2a/nv2a.c`
  - `hw/xbox/nv2a/pcrtc.c`
  - `xemu-xbe.c`
  - `ui/xemu-headless.c`

## Loop-guard fields

- `native_pre_stream_serviceable_state_browser_mapping`
- `browser_pre_stream_vector_service_state`
- `pre_service_browser_first_watch_read_ticks`
- `post_service_watch_edge`
- `missing-xbe-executed-marker`

## Findings

The mapping should be classified as:

```text
native_pre_stream_serviceable_state_browser_mapping=
missing-browser-pcrtc-vblank-raise-before-pfifo-empty-plus-ready-edge-pfifo-gate
```

Native has a real pre-stream interrupt-serviceable path. `nv2a_vga_gfx_update`
raises PCRTC vblank, `nv2a_update_irq` publishes the NV2A/PCI IRQ state, the
guest later writes `NV_PCRTC_INTR_0` through `pcrtc_write`, and that publishes
the latest wait state as `pcrtc/intr-clear`. The native log then services
vector `0x30` before PFIFO stream-idle while the latest wait state remains
`pcrtc/intr-clear`; by the shared watched read, physical `0x0003a890` has
already reached 136 tick units.

The stable browser baseline suppresses PCRTC vblank in
`nv2a_vga_gfx_update()` through `XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=off`, so
the browser has no matching PCRTC pending bit and no real PCRTC vblank raise to
clear. The stable ready-edge timer pump is also PFIFO-empty gated, so it runs
only after the stream-idle boundary. Browser does service vector `0x30`, but
only later from the `pfifo-window/pusher-empty` state, and the first watched
read of physical `0x0003a890` remains at 0 ticks.

The negative deterministic-PCRTC branch is important evidence but not a path to
promote as-is. It proved timer work can be forced when the latest wait state is
`pcrtc/intr-clear`, but it lost the stable vector/IRET and watch-edge shape.
That means the next valid design should change interrupt availability and
ordering, not pump timers harder at an already malformed boundary.

## Design proposal

Keep the ready-edge host4 combined log as the baseline. The next code design
should be an opt-in browser deterministic serviceability mode that allows a
single real PCRTC vblank raise at a tightly verified pre-stream point, then lets
the guest clear it naturally through `pcrtc_write()`.

Candidate promotion gates:

- Dashboard has been observed and `dashboard=xbe-entry-probe status=ready`.
- PFIFO stream-idle has not been observed yet.
- PCRTC vblank is enabled and not already pending.
- The PFIFO wait snapshot is near the final window in the stable browser flow,
  such as `pfifo-window/puller-method-done` or adjacent final-window state,
  not an arbitrary early frame update.
- DMA state is at or immediately approaching the stable final window rather
  than old early command-stream activity.
- PGRAPH/PFIFO pending state is not made worse than the stable ready-edge host4
  baseline.

Promotion must require all current preservation gates before any tick movement
is considered meaningful: browser runtime evidence, B4 display capture,
dashboard read/load/entry-ready, section-map evidence, PFIFO stream-idle,
vector `0x30`, real IRET, and the `0x80030e84->0x80030f31` post-service watch
edge.

## Progress-method critique

The recent work has been too willing to test pump placements after proving the
same shape of failure. The useful invariant is now serviceability: native has a
pre-stream PCRTC-backed interrupt-service window, while the stable browser does
not. A runtime that merely changes timer count, broad vblank mode, PIT bridge,
or post-STI scheduling is low value unless it can first state how it preserves
or recreates that serviceable state.

The strict B6 checker should not be weakened. The proposal still treats
`dashboard=xbe-executed` as required evidence and treats memory-watch, timer,
PFIFO, and PCRTC markers as diagnostics only.

## Decision

Continue, but only after the required sub-agent loop check. The next technical
step should be a static patch plan for a default-off PCRTC vblank availability
gate that preserves the stable ready-edge host4 boundary. Do not start a
runtime yet.

## Next step

Run the bounded sub-agent loop check for this design proposal and require the
agent to include a `Progress-Method Critique` section in its report.
