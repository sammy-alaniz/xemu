# Pre Stream Timer IRQ Gate Replacement Viability

## Purpose

- One new fact this run was supposed to produce: classify `pre_stream_timer_irq_gate_replacement_viability` from source and existing artifacts only.

## Command(s)

```sh
rg -n "irq_after_pfifo_empty_only|main_loop_timer_pump_ready|deterministic|qemu_clock_run_timers_with_attrs_limit|qemu_clock_run_all_timers|qemu_clock_run_timers|observe_main_loop_timers|ready_edge|pfifo-ready-edge|browser-ready-edge|PIT|pit=irq-timer|irq-timer" xemu-xbe.c ui/xemu-headless.c util/main-loop.c hw/timer/i8254_common.c hw/timer/i8254.c include/sysemu/runstate.h include/qemu/timer.h
sed -n '60,90p' history/64-deterministic-browser-m1-v1.md
sed -n '1,220p' history/66-deterministic-warmup1-browser-runtime.md
sed -n '1,180p' history/67-deterministic-warmup-loop-check.md
sed -n '930,985p' xemu-xbe.c
sed -n '1140,1185p' xemu-xbe.c
sed -n '1240,1290p' xemu-xbe.c
sed -n '2540,2620p' xemu-xbe.c
sed -n '6180,6248p' xemu-xbe.c
sed -n '6320,6445p' xemu-xbe.c
sed -n '6640,6810p' xemu-xbe.c
sed -n '690,725p' util/main-loop.c
rg -n "main_loop_timer_pump_ready_edge|ready-edge-qemu-pump|ready_edge_all_timers|browser-ready-edge-qemu-pump|qemu_clock_run_all_timers|qemu_clock_run_timers_with_attrs_limit" xemu-xbe.c ui/xemu-headless.c hw/xbox/nv2a/pfifo.c hw/xbox/nv2a/pgraph.c hw/xbox/nv2a/pcrtc.c util/main-loop.c
sed -n '540,665p' hw/xbox/nv2a/pfifo.c
rg -n "pfifo_boot_trace_ready_edge_timer_pump|stream-idle-transition|stream_idle_transition|pusher-empty" hw/xbox/nv2a/pfifo.c
sed -n '667,735p' hw/xbox/nv2a/pfifo.c
sed -n '1360,1390p' hw/xbox/nv2a/pfifo.c
sed -n '1,220p' history/64-deterministic-browser-m1-v1.md
sed -n '1,220p' history/65-deterministic-m1-loop-check.md
sed -n '1,220p' history/70-post-service-edge-decision-static-compare.md
sed -n '1,220p' history/82-edge-decision-readyedge-runtime.md
sed -n '1,220p' history/83-edge-decision-progress-method-loop-check.md
rg -n "QEMU_TIMER_ATTR_XEMU_TCG_PUMP|timer_mod|timer_new|irq_timer|XEMU_TCG_PUMP" hw/timer util include xemu-xbe.c
sed -n '250,320p' hw/timer/i8254.c
sed -n '320,370p' hw/timer/i8254.c
sed -n '221,270p' include/qemu/timer.h
sed -n '55,80p' include/qemu/timer.h
sed -n '560,725p' util/qemu-timer.c
sed -n '10385,10465p' xemu-xbe.c
rg -n "irq_trace_gate_allows|irq_watch_matches|observe_pic_irq_ack|observe_cpu_hard_irq|observe_pit_irq_timer|XEMU_BOOT_TRACE_XBE_IRQ_WATCH" xemu-xbe.c hw/intc hw/i386 hw/timer
sed -n '968,980p' xemu-xbe.c
sed -n '5160,5320p' xemu-xbe.c
sed -n '5320,5390p' xemu-xbe.c
sed -n '220,245p' hw/intc/i8259.c
rg -n "main-loop=timers context=browser-runtime source=main-loop-wait|source=browser-deterministic-pump|source=browser-ready-edge-qemu-pump|source=browser-headless-host-pump-bounded|pfifo=stream-idle-transition|pfifo=stream-idle-boundary" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
rg -n "source=main-loop-wait" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: static-only inspection, no new runtime artifact
- Fixture assumptions: current browser baseline has no pre-stream vector `0x30` service and uses `XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump` plus `XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1`.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `pre_stream_timer_irq_gate_replacement_viability`

## Findings

- Result: `pre_stream_timer_irq_gate_replacement_viability=viable-only-as-pit-attributed-bridge; existing-raw-pump-paths-not-viable`.
- Exact current gate:
  - `xemu_xbe_boot_trace_main_loop_timer_pump_ready()` returns PFIFO-empty readiness for ready-edge browser modes.
  - `pfifo_boot_trace_ready_edge_timer_pump()` only runs at the PFIFO stream-idle edge after DMA GET catches DMA PUT.
  - `ui/xemu-headless.c` returns before running timers when the browser headless pump is not ready, except for deterministic warmup.
  - `xemu_xbe_boot_trace_observe_main_loop_timers()` also suppresses regular non-browser diagnostic observations when the same readiness path is closed.
- The stable browser artifact has no `source=main-loop-wait` timer markers. Its first timer progress is `source=browser-ready-edge-qemu-pump` at the stream-idle transition, then bounded host-pump markers after stream-idle. That means the current browser path has no obvious regular main-loop timer source to simply ungate pre-stream.
- Existing raw alternatives are negative:
  - Deterministic browser v1 moved `pre_service_browser_first_watch_read_ticks` from 0 to 2 but regressed the useful post-service edge.
  - Warmup1 lost the focused watched read and fell to the older `0x8001b02f->0x8001b030` path.
  - History 67 killed raw warmup-count tuning as the main control knob.
  - Historical precommit, vblank, pre-TB, before-interrupt, and scheduler paths remain rejected or quarantined.
- There is one narrow source primitive that is materially different from broad pump/vblank/precommit/scheduler work:
  - The PIT channel creates its IRQ timer with `QEMU_TIMER_ATTR_XEMU_TCG_PUMP`.
  - `qemu_clock_run_timers_with_attrs_limit()` can run only expired timers with that attribute and a bounded count.
  - A PIT-attributed run would avoid `qemu_clock_run_all_timers()` and avoid unrelated NV2A/PCRTC/vblank timers.
- A fully non-host bridge does not appear viable in the current browser runtime without larger architecture work, because the stable browser artifact does not show a regular pre-stream `main-loop-wait` timer lane. The practical viable shape is a new, explicitly named PIT-only browser bridge, not another reuse of the broad host pump:
  - entry-ready only,
  - before first watched read / before PFIFO stream-idle,
  - virtual timer must be expired,
  - run only `QEMU_TIMER_ATTR_XEMU_TCG_PUMP` timers with a small bounded step,
  - do not run all timers,
  - do not run PCRTC/vblank/NV2A timers,
  - do not revive TCG before-interrupt/pre-TB scheduler ownership,
  - stop and fail preservation if B4/B5/read/load/entry-ready/section-map/stream-idle/vector `0x30` service/IRET/post-service edge regresses.
- The trace gate and actual delivery gate are separate:
  - `irq_after_pfifo_empty_only` filters many IRQ markers before PFIFO-empty and can allow selected watched IRQ line markers through `XEMU_BOOT_TRACE_XBE_IRQ_WATCH`.
  - But the watched word remaining at 0 before the browser first read proves this is not just marker filtering; actual timer/IRQ-driven guest tick accumulation is missing.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run.

## Decision

- Status: current
- Why: a next code slice is plausible only if it is PIT-attributed and preservation-gated. Reusing raw deterministic warmup count, ready-edge all-timers, normal vblank, PFIFO precommit, or pre-TB/before-interrupt scheduling would be looping.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/235-pre-stream-gate-replacement-loop-check.md` approved this static design inspection only, and required naming the exact gate, why the candidate differs from rejected modes, and the preservation invariant before any runtime/code work.

## Next Step

- Narrow follow-up: run the required loop check with progress-method critique. If approved, the next code field should be `pit_attributed_pre_stream_bridge_preserves_post_service_edge`: implement the smallest opt-in PIT-only browser bridge with a source tag and immediate preservation gates, not a broad timer pump or scheduler revival.
