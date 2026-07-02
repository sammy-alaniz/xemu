# 296 - Browser Pre-Stream Vector Service State Inspection

## Purpose

- One new fact this inspection was supposed to produce:
  classify `browser_pre_stream_vector_service_state` from source ownership and
  existing stable logs without starting another runtime or adding
  instrumentation.

## Command(s)

```sh
rg -n "pcrtc|PCRTC|intr-clear|pcrtc_pending|vblank|VBLANK|pending_interrupt|pmc_pending|NV_PCRTC|PCRTC" \
  hw/xbox hw/display ui include target i386-softmmu 2>/dev/null

rg -n "pit=irq-timer|hard-irq-service|pic=irq-ack|intno=0x30|cpu_loop|cpu_exec|interrupt_request|CPU_INTERRUPT_HARD|main-loop=timers|timer-pump|qemu_clock|qemu_mod_timer|timerlist|icount" \
  hw include accel system target ui stubs util browser scripts 2>/dev/null

rg -n "pfifo-window|pusher-empty|puller-method-done|wait-source|wait_source|dma_get|dma_put|pusher-enter|BOOT_MARK b6 pfifo|main_loop_timer_pump_ready|headless=timer|pfifo-ready-edge|stream-idle" \
  hw/xbox ui browser scripts 2>/dev/null

sed -n '150,430p' hw/xbox/nv2a/nv2a.c
sed -n '780,1110p' hw/xbox/nv2a/nv2a.c
sed -n '1,120p' hw/xbox/nv2a/pcrtc.c
rg -n "main_loop_timer_pump_ready|timer_pump|timer-opportunity|XEMU_BROWSER_BOOT_HEADLESS_TIMER|headless=timer|main-loop=timers|tcg_timer|pit-after|before_interrupt|before-interrupt" \
  hw ui browser scripts include target/i386 accel system 2>/dev/null

rg -n "main_loop_timer_pump_ready|main_loop_timer_pump_presleep|ready_edge|timer_opportunity|tcg_timer_pump_ready|observe_nv2a_wait_state|Nv2aWaitState|vblank-suppress|pfifo_empty_blocker|main-loop=timers" \
  . --glob '!build*' --glob '!subprojects' --glob '!*.log' --glob '!history/*.md'

nl -ba xemu-xbe.c | sed -n '620,735p'
nl -ba xemu-xbe.c | sed -n '930,1190p'
nl -ba xemu-xbe.c | sed -n '6860,7120p'
nl -ba ui/xemu-headless.c | sed -n '620,805p'
nl -ba ui/xemu-headless.c | sed -n '292,425p'
nl -ba ui/xemu-headless.c | sed -n '828,905p'
nl -ba hw/xbox/nv2a/nv2a.c | sed -n '1068,1106p'
nl -ba hw/xbox/nv2a/pfifo.c | sed -n '300,375p'
nl -ba hw/xbox/nv2a/pfifo.c | sed -n '680,820p'

rg -n "nv2a=irq-source.*source=pcrtc|nv2a=pcrtc-vblank-gate|pic=irq-ack.*intno=0x30|cpu=hard-irq-service.*intno=0x30|cpu=iret|main-loop=timers|headless=timer-opportunity" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

rg -n "nv2a=irq-source.*source=pcrtc|nv2a=pcrtc-vblank-gate|pic=irq-ack.*intno=0x30|cpu=hard-irq-service.*intno=0x30|cpu=iret|main-loop=timers|headless=timer-opportunity" \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

rg -n "XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE|pcrtc_vblank_mode|PcrtcVblank|PCRTC_VBLANK|vblank_mode" \
  browser scripts ui hw/xbox/nv2a . --glob '!build*' --glob '!history/*.md' --glob '!*.log'
```

## Inputs And Artifacts

- Native baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Stable browser baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Source files inspected:
  - `hw/xbox/nv2a/nv2a.c`
  - `hw/xbox/nv2a/pcrtc.c`
  - `hw/xbox/nv2a/pfifo.c`
  - `ui/xemu-headless.c`
  - `xemu-xbe.c`
  - `xemu-xbe.h`
- Fixture assumptions:
  stable browser baseline uses `XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=off`.

## Expected Field(s)

- Loop-guard field(s) this inspection could change or explain:
  `browser_pre_stream_vector_service_state`

## Findings

- Result:
  `browser_pre_stream_vector_service_state=blocked-by-pcrtc-vblank-suppression-and-pfifo-empty-gated-timer-readiness`
- Important marker/comparator lines:
  - Browser log line 991 and later sampled lines show
    `nv2a=pcrtc-vblank-gate mode=off action=suppress
    reason=diagnostic-off`, with `pcrtc_pending=0x00000000` and
    `pcrtc_enabled=0x00000001`.
  - Browser line 2491 runs `main-loop=timers
    source=browser-ready-edge-qemu-pump` with wait state
    `pfifo-window/pusher-puller-done`, `pcrtc_pending=0`, and watched word
    `0x00000000`.
  - Browser lines 2499-2501 service vector `0x30` only after PFIFO stream-idle,
    with wait state `pfifo-window/pusher-empty`, not `pcrtc/intr-clear`.
  - Native lines 874 and 881 show the relevant PCRTC sequence:
    `pcrtc/vblank-raise` makes `pmc_pending=0x01000000`, then
    `pcrtc/intr-clear` clears it.
  - Native lines 994-1042 show `main-loop=timers`, PIC ack, and vector `0x30`
    service while the latest wait state remains `pcrtc/intr-clear`, before
    stream-idle.
- Source ownership:
  - `hw/xbox/nv2a/nv2a.c:nv2a_vga_gfx_update()` raises PCRTC vblank by setting
    `d->pcrtc.pending_interrupts |= NV_PCRTC_INTR_0_VBLANK`, but browser builds
    first pass through `nv2a_browser_pcrtc_vblank_should_raise()`.
  - `hw/xbox/nv2a/pcrtc.c:pcrtc_write()` publishes `pcrtc/intr-clear` only when
    the guest writes `NV_PCRTC_INTR_0`.
  - `xemu-xbe.c:xemu_xbe_boot_trace_main_loop_timer_pump_ready()` currently
    treats ready-edge modes as PFIFO-empty gated, while the older
    `pcrtc-before-stream-idle-then-after-pfifo-empty` mode broadly accepts any
    PCRTC wait.
  - `ui/xemu-headless.c:xemu_headless_pump_browser_timers()` already has a
    deterministic warmup path, but it is too broad: it can pump on entry-ready
    plus expired virtual timers without requiring the native PCRTC raise/clear
    shape.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; no runtime was started.

## Decision

- Status: current
- Why:
  The missing browser pre-stream service state is not an unknown CPU mystery.
  The active browser baseline suppresses PCRTC vblank raises, so the guest has
  no equivalent pre-stream PCRTC interrupt to clear before PFIFO stream-idle.
  Existing timer readiness then waits for PFIFO-empty-style state or uses a
  broad deterministic warmup, neither of which is the native
  `pcrtc/vblank-raise -> pcrtc/intr-clear -> vector 0x30 service` sequence.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  The previous loop check allowed read-only design/code inspection centered on
  `browser_pre_stream_vector_service_state`.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary:
  Stay design-first and do not rerun old pump/vblank/PIT/scheduler branches or
  revalidate `missing-xbe-executed-marker`.
- If yes, process adjustment for next 2-3 turns:
  The next design/code change, if approved by loop check, should be a narrow
  deterministic PCRTC service gate, not normal-vblank promotion and not a
  generic timer pump.

## Next Step

- Narrow follow-up:
  Run the required bounded loop check. Candidate next action is a design-only
  patch plan for a gated deterministic PCRTC pre-stream service mode that
  preserves the stable ready-edge host4 boundary and only then allows a single
  runtime.
