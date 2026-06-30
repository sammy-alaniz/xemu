# Active Goal: B6 Dashboard-Loaded Verification

## Objective

Advance the completed Xbox browser boot work from B3/B4/B5 evidence to B6
dashboard-loaded verification. B6 is complete only when browser-runtime evidence
proves dashboard XBE read/load/entry-ready/execute, native reference frame
evidence exists, browser capture uses the Playwright-preferred path with Firefox
BiDi fallback, browser frames match native references, and the B6 checker passes
without treating non-empty scanout alone as dashboard completion.

## Loop Guard

Before starting a new run, probe, or code change, name the one new fact it can
produce. Do not run a command if its expected result is only one of the
already-known facts:

- B3/B4/B5 pass.
- Section-map evidence passes.
- Browser B6 fails at `missing-xbe-executed-marker`.
- Native execution/reference passes.
- Ready-edge host4 remains browser 1 tick versus native 136 ticks.
- A negative-control pump/vblank/precommit mode still fails B6.

A new run is justified only if it can change or explain one of these fields:

- `pre_service_browser_first_watch_read_ticks`
- `browser_shared_memory_poll_ticks`
- `browser_post_service_top_edge`
- `browser_xbe_executed`
- native/browser visual match after browser execution exists

If a proposed run uses a historical or negative-control mode, first state which
current field regressed or which new instrumentation makes the run answer a new
question. Otherwise use the current active diagnostic instead.

## Run History Requirement

After every experiment, run, or probe, create a write-up under `history/`.
Use a numbered filename:

```text
history/<next-number>-<short-run-title>.md
```

Examples:

- `history/1-ready-edge-host4-boundary.md`
- `history/2-pre-service-tick-producer-probe.md`

Numbering rules:

- Use the next integer after the highest numbered run file already in
  `history/`.
- Keep `history/0-template.md` as the template and do not count it as a run.
- Use lowercase hyphenated titles.
- Do not overwrite an existing history file.

Each run write-up must include:

- Purpose: the one new fact this run was supposed to produce.
- Command(s): exact command lines or script names, including important env vars.
- Inputs/artifacts: logs, combined logs, fixture assumptions, and baseline files.
- Expected field(s): which loop-guard field could change or be explained.
- Findings: pass/fail result and important marker/comparator lines.
- Decision: whether this is current, historical support, or negative evidence.
- Next step: the narrow follow-up implied by the result.

Do not start a second run before writing the history entry for the previous run,
unless the previous run failed before producing any useful artifact. In that
case, still write the failed-run entry if the failure changes the next action.

## Current Progress Metric

Primary metric:

- Move the browser first watched read of physical `0x0003a890` from 0 ticks
  toward native's 136 ticks.

Current expected baseline:

- Native first watched read: 136 ticks.
- Browser first watched read: 0 ticks.
- Browser shared post-service poll: 1 tick.
- Browser B6: fail, `missing-xbe-executed-marker`.
- Native execution/reference: pass.

A change is progress only if it improves or explains the primary metric while
preserving:

- B4 display capture.
- B5 runtime evidence.
- Dashboard read/load/entry-ready.
- Section-map pass.
- PFIFO stream-idle.
- Vector `0x30` service/IRET.
- Post-service `0x80030e84->0x80030f31` edge.

## Artifact Roles

| Artifact | Role | Status |
| --- | --- | --- |
| `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log` | Active browser B6 diagnostic | Current front-most |
| `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log` | Native execution/reference baseline | Current |
| `build-real-b3-matrix/browser-runtime-firefox-bidi-section-map-v2-combined.log` | B5-pass/read-proof browser baseline | Stable, not front-most |
| `build-real-b3-matrix/browser-memory-watch-write-0x3a890-v2-combined.log` | Stable browser write-watch comparison | Historical support |
| `build-real-b3-matrix/browser-memory-sample-0x3a890-full-baseline-v1-combined.log` | Previous cheap memory-sample diagnostic | Historical support |
| PCRTC pre-stream, normal-vblank, ready-edge-only, PFIFO pre-commit, and limit136 probes | Negative controls | Do not rerun unless a current field regresses or new instrumentation changes the question |

## Next Three Actions

1. Identify the producer/order for physical `0x0003a890` before the browser's
   first watched read.
2. Instrument timer deadline, virtual clock delta, main-loop dispatch, and
   CPU/yield ordering before `0x80014f32->0x80030e84`.
3. Test one scheduling change that moves the browser first watched read toward
   native's 136 ticks without regressing B4/B5/read/load/entry-ready,
   section-map, stream-idle, vector `0x30` service/IRET, or the post-service
   edge.

## Current Boundary

B3/B4/B5 are already evidenced. The `Artifact Roles` table above is the source
of truth for what is current, stable, historical, and negative-control evidence.
The expanded notes below preserve the evidence trail, but they should not
override the loop guard or next three actions.

The B5-pass browser baseline proves real assets, browser-runtime
`xboxdash.xbe` read, `dashboard=xbe-loaded`,
`dashboard=xbe-entry-probe status=ready`,
`dashboard=xbe-section-map phase=entry-ready`, executable entry section 3, B4
display capture, and B5 runtime evidence. It still correctly fails B6 at
`missing-xbe-executed-marker`.

The stable browser write-watch diagnostic is not a B5 replacement because it
remains a focused diagnostic run, but it preserves the full current browser
baseline while sampling the shared low-RAM word and applying the new write-only
watch setting.
The raw browser log is
`build-real-b3-matrix/browser-memory-watch-write-0x3a890-v2/browser-runtime.log`;
the combined log appends FATX/IDE read-complete proof. It uses the rebuilt wasm
from 2026-06-30 after widening the mem-access callback guards for
`CONFIG_XEMU_BROWSER_BOOT`. It confirms browser diagnostics apply
`xbe_memory_watch_access=write`, emits
`memory-watch-install result=pass access_filter=write`, and records browser
write callbacks at `eip=0x80030e84`. The browser runtime evidence passes, B4
display capture passes, and the strict B6 checker still correctly fails at
`missing-xbe-executed-marker`.

This newest diagnostic proves browser-runtime dashboard read/load/entry-ready
plus section-map evidence, B4 display capture, PFIFO stream-idle, bounded
browser main-loop timer progress, no browser TCG timer progress, PIC ack, vector
`0x30` hard-IRQ service, and IRET. Its cheap samples of physical `0x0003a890`
stay at `0x00000000` through all 4 bounded browser host timer-progress events.
The first browser write callback for physical `0x0003a890` happens after the
preferred IRET return at `eip=0x80030e84`, with pre-access value `0x00000000`;
the next watched write sees `0x00002710`. Native reaches the analogous block
with the word already at the 136-tick range.
The current boundary helper reports the browser reaches the same
`0x80030e84->0x80030f31` post-service block as native, but it reaches it at 0
ticks while native reaches it at 136 ticks; the block itself still increments by
one tick on both sides.

The front-most browser diagnostic is the ready-edge plus host-fallback probe.
It is not B6 and it is not a final architecture; it is the newest focused
experiment against the pump-placement hypothesis. The raw browser log is
`build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1/browser-runtime.log`;
the combined log appends FATX/IDE read-complete proof. It uses
`XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump` and
keeps `XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4` for the bounded
host fallback. It proves the new one-shot
`main-loop=timers source=browser-ready-edge-qemu-pump` marker fires at the
PFIFO stream-idle transition before the boundary marker, then the bounded
host-fallback path preserves the useful `0x80030e84->0x80030f31` post-service
edge. The strict B6 checker still correctly fails at
`missing-xbe-executed-marker`. The useful improvement is narrow: the shared
post-service poll moves from browser 0 ticks in v2 to browser 1 tick here, but
native is still at 136 ticks, so the browser remains 135 tick units behind and
still does not execute dashboard XBE code.

The PCRTC pre-stream host-pump probe
`build-real-b3-matrix/browser-memory-watch-write-0x3a890-pcrtc-prestream-host4-v2-combined.log`
is negative evidence and must not replace the ready-edge plus host-fallback
baseline. The experiment added the opt-in
`XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pcrtc-before-stream-idle-then-after-pfifo-empty`
and publishes suppressed PCRTC vblank gates as diagnostic wait state
`source=pcrtc op=vblank-suppress`. It successfully moves the 4 bounded browser
host timer-progress events before PFIFO stream-idle, but that is too early: the
strict B6 checker still fails at `missing-xbe-executed-marker`, IRET comparison
fails because the browser never reaches the useful hard-IRQ service/IRET pair,
there is no browser shared post-service poll, the watched `0x0003a890` word
stays at 0 ticks, and `scripts/xbox-b6-current-boundary.sh` reports
`headless_pump_divergence=pump-before-stream-idle-transition`,
`post_idle_timer_divergence=browser-missing-main-loop-timer-progress`, and
`next=restore-browser-main-loop-timer-progress`. Keep this as placement
evidence only; do not continue broad PCRTC-prestream pumping unless the goal is
specifically to test a narrower non-regressing pre-stream gate.

The ready-edge plus host-fallback normal-vblank control
`build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-normal-vblank-v1-combined.log`
is negative evidence. It keeps the ready-edge QEMU-thread pump and bounded host
fallback but sets `XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=normal`. The browser
runtime itself passes, B4 display capture passes, dashboard read/load/entry-ready
and section-map evidence remain present, and the strict B6 checker still fails
at `missing-xbe-executed-marker`. The current boundary helper reports the
normal-vblank control still has `browser_xbe_executed=no`, changes the
transition split to noisier CPU/IRQ state
(`pfifo_transition_divergence=transition-pending-irq-mismatch`), keeps the
shared watched word far behind native
(`browser_main_loop_timer_max_memory_watch_ticks=1`), and does not improve the
post-service watch-edge delta. Do not promote normal PCRTC vblank as the active
baseline unless a future run also proves strict browser-runtime
`dashboard=xbe-executed`.

The ready-edge-only probe
`build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-v1-combined.log`
is negative evidence. It proves the new ready-edge pump can fire before the
stream-idle boundary, but without the bounded host fallback it regresses to the
older `0x8001b02f->0x8001b030` loop and reports
`next=restore-browser-main-loop-timer-progress`. Keep it as placement evidence,
not as the promoted diagnostic.

The previous browser memory-sample diagnostic preserves the same full focused
baseline while sampling the shared low-RAM word without the heavier browser TLB
callback watch.
The raw browser log is
`build-real-b3-matrix/browser-memory-sample-0x3a890-full-baseline-v1/browser-runtime.log`;
the combined log appends FATX/IDE read-complete proof. It uses the same full
diagnostic environment as the earlier focused baseline, including PCRTC vblank
off, bounded pre-transition plus after-PFIFO-empty browser headless host pumping,
TCG timer pumping disabled, IRQ-after-PFIFO-empty-only tracing, and expanded
kernel-loop/PIC/hard-IRQ/IRET/PIT/main-loop timer budgets. Missing those knobs
caused false regressions in control runs that looked like lost stream-idle or
main-loop timer progress.

This run proves browser-runtime dashboard read/load/entry-ready plus section-map
evidence, B4 display capture, PFIFO stream-idle, 8
`headless=timer-pump-step` markers, 4
`main-loop=timers source=browser-headless-host-pump-bounded` progress events,
no browser TCG timer progress, PIC ack, vector `0x30` hard-IRQ service, and IRET.
It still correctly fails B6 at `missing-xbe-executed-marker`. Its cheap samples
of physical `0x0003a890` show the browser value changing from `0x00000000` to
`0x00002710`, but the strict comparator still reports a shared post-service
mismatch against native.

The previous browser diagnostic is not a B5 replacement because the raw runtime
smoke still ends with `BROWSER_RUNTIME_SMOKE result=fail reason=runtime-timeout`,
but it moves the active CPU-flow boundary forward. It uses
`XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-before-transition-activity-then-after-pfifo-empty`,
has TCG timer pumping disabled, caps host-pump timer-progress callbacks at the
native-observed count of 4 with
`XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4`, is combined with
FATX/IDE read-complete proof, and now proves:

- browser-runtime dashboard read/load/entry-ready plus section-map evidence;
- PFIFO stream-idle after pusher-empty;
- 8 `headless=timer-pump-step` markers, before/after the 4 bounded host pumps;
- `main-loop=timers source=browser-headless-host-pump-bounded`;
- `browser_main_loop_timer_progress_events=4`, matching the promoted native
  reference count;
- `browser_tcg_timer_progress_events=0`;
- PIC ack, vector `0x30` hard-IRQ service, and IRET in the browser;
- a preferred browser IRET return path through `0x80030e84->0x80030f31`, while
  the strict `dashboard=xbe-executed` marker is still absent.

It still correctly fails B6 at `missing-xbe-executed-marker`.

Native execution/reference risk is now resolved for the headless baseline. The
normal native headless path was missing the browser-headless-style
`graphic_hw_update` pump. With the opt-in
`XEMU_HEADLESS_BOOT_GRAPHIC_UPDATE=1` probe, the native run
`build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log` emits:

- `BOOT_MARK b6 dashboard=xbe-executed context=native-headless ... phys_match=yes section_index=3 section_flags=0x00000006`
- `NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=native-framebuffer hash=2aa899fb497643b12c4bae3a089d3dc98b2077ea18a075fbf38f10e266841b78 width=640 height=480 dashboard=xbe-executed`

The focused native actual-execution checker now reports
`NATIVE_ACTUAL_XBE_EXECUTION result=pass reason=strict-dashboard-executed` for
that artifact, with `direct_entry_pc=yes`. The native reference checker reports
`NATIVE_REFERENCE_EVIDENCE result=pass` with the hash above.

The focused native handoff checker now summarizes the promoted native artifact:
`scripts/xbox-native-headless-handoff-check.py
build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log` reports
`NATIVE_HEADLESS_HANDOFF result=pass
terminal_state=dashboard-executed-with-native-reference
actual_xbe_executed=yes native_reference=pass`. Current key fields:
`latest_stream_idle_eip=0x80045c92`,
`latest_stream_idle_cpu_interrupt_request=0x00000000`,
`after_idle_top_edge=0x80030e84->0x80030f31`, and
`after_idle_cpu_interrupt_nonzero=6`. This satisfies the native side of the B6
contract, but not browser B6.

The sharp current split is still browser-side. `scripts/xbox-b6-current-boundary.sh`
now defaults to the promoted native artifact and the ready-edge plus host-fallback
browser diagnostic when present. It reports `native_xbe_executed=yes`,
`native_handoff_native_reference=pass`, `browser_xbe_executed=no`,
`b6_reason=missing-xbe-executed-marker`,
`browser_main_loop_timer_progress_events=4`,
`browser_tcg_timer_progress_events=0`, `post_idle_timer_divergence=none`,
`loop_divergence=memory-poll-mismatch`,
`post_service_memory_poll_divergence=shared-memory-poll-value-mismatch`,
`shared_memory_poll_addr=0x8003a890`,
`native_shared_memory_poll_value=0x0014c080`,
`browser_shared_memory_poll_value=0x00002710`,
`shared_memory_poll_tick_unit=0x00002710`,
`native_shared_memory_poll_ticks=136`,
`browser_shared_memory_poll_ticks=1`,
`shared_memory_poll_tick_delta=135`,
`shared_memory_poll_tick_relation=browser-behind`,
`browser_main_loop_timer_memory_watch_samples=5`,
`browser_main_loop_timer_max_memory_watch_value=0x00002710`,
`browser_main_loop_timer_max_memory_watch_ticks=1`,
`browser_post_service_top_edge=0x80030e84->0x80030f31`,
`post_service_watch_edge=pass`,
`watch_edge_block_delta_match=yes`,
`memory_watch_timeline=pass`,
`memory_watch_timeline_divergence=browser-shared-poll-before-watch-catchup`,
`memory_watch_timeline_shared_delta=154`,
`pre_service_tick_gap=pass`,
`pre_service_tick_gap_divergence=browser-first-watch-read-before-catchup`,
`pre_service_first_watch_read_tick_delta=136`,
`pre_service_native_first_watch_read_ticks=136`,
`pre_service_browser_first_watch_read_ticks=0`,
`pre_service_native_first_watch_read_edge=0x80014f5f->0x80030e84`,
`pre_service_browser_first_watch_read_edge=0x80014f32->0x80030e84`,
`pre_service_browser_first_timer_source=browser-ready-edge-qemu-pump`,
`pre_service_browser_first_timer_watch_ticks=0`,
`pre_service_browser_first_watch_read_before_write=yes`,
`pre_service_browser_first_watch_write_delta_from_read=6`,
`pre_service_browser_first_service_eip=0x8001b030`,
`native_watch_install=pass`,
`browser_watch_install=pass`,
`native_watch_write_events=8`,
`browser_watch_write_events=3`,
`native_first_watch_write_ticks=85`,
`browser_first_watch_write_ticks=0`,
`browser_last_watch_write_value=0x00004e20`,
`headless_pump=pass`,
`headless_pump_divergence=pump-before-stream-idle-boundary`,
`headless_pump_timer_before_boundary=yes`,
`headless_pump_timer_after_boundary=no`,
`post_idle_flow_divergence=missing-interrupt-service`,
`pfifo_transition_divergence=post-transition-hard-irq-set-mismatch`, and
`next=converge-browser-post-service-flow`.

In ELI5 terms: the browser now rings one timer doorbell at the PFIFO ready edge,
then still rings the bounded host-side doorbell four more times and reaches the
same important post-service block as native. That is closer than v2 because the
shared watched word is no longer zero at the shared poll. It is still not close
enough: native reaches that poll with 136 tick units, while browser reaches it
with only 1. The browser is still too early or under-advanced when it enters the
post-service path, and it still never emits a strict browser-runtime
`dashboard=xbe-executed` marker. Do not go back to native detector-proof work,
B3/B4/B5, storage, PFIFO/PGRAPH command progress, or broad timer pumping unless
fresh evidence regresses this boundary.

Fresh pre-service tick-gap comparator, 2026-06-30:
`scripts/xbox-pre-service-tick-gap-compare.py` compares the first watched
`0x0003a890` read after PFIFO stream-idle against the first watched write and
timer/service markers. Against the promoted native baseline and the current
ready-edge plus host-fallback browser diagnostic, it reports
`PRE_SERVICE_TICK_GAP_COMPARE result=pass
divergence=browser-first-watch-read-before-catchup`.
Native's first watched read after stream-idle is already 136 tick units, while
browser's first watched read is 0. Browser's ready-edge QEMU-thread timer sample
also reads 0, and the first watched write happens 6 log lines after that first
read. This sharpens the causal target: browser is behind before the shared
post-service read and before the `0x80030e84->0x80030f31` write block. The next
engineering target is browser scheduling/tick accumulation before the
`0x80014f32->0x80030e84` watched-read edge, not the one-tick write arithmetic
inside `0x80030e84`.

Fresh write-filter browser probe, 2026-06-30:
`build-real-b3-matrix/browser-memory-watch-write-0x3a890-v2-combined.log` is the
stable write-watch browser diagnostic. It ran after rebuilding both native and wasm
targets and after broadening the mem-access callback declarations, TLB hooks,
and physmem callbacks to `XBOX || CONFIG_XEMU_BROWSER_BOOT`. It passes browser
runtime evidence and B4 display capture, applies
`trace_xbe_memory_watch_access=write`, emits
`memory-watch-install ... access_filter=write`, preserves dashboard
read/load/entry-ready and section-map evidence, and still correctly fails B6 at
`missing-xbe-executed-marker`. `scripts/xbox-memory-watch-timeline-compare.py`
reports `browser_watch_install=pass`, `browser_watch_access_events=2`,
`browser_watch_write_events=2`, `browser_first_watch_write_eip=0x80030e84`,
`browser_first_watch_write_value=0x00000000`,
`browser_last_watch_write_value=0x00002710`,
`browser_timer_watch_samples=4`, `browser_max_timer_watch_value=0x00000000`,
and `browser_first_shared_poll_value=0x00000000`. Native write-filter proof in
`build-real-b3-matrix/native-memory-watch-write-0x3a890-v2/boot-smoke.log`
confirms native writes also hit `eip=0x80030e84`, but much later in tick terms:
the native first watched write is already 85 ticks and the first focused shared
poll is 154 ticks in the write-filter run. The current causal question is now
why browser reaches the shared post-service poll before the watched word has
accumulated native-like ticks, not whether browser can install the watch.
`scripts/xbox-headless-pump-placement-compare.py` reports
`divergence=host-ready-before-boundary-pump-after-boundary`,
`host_ready_before_boundary=yes`, `timer_before_boundary=no`,
`timer_after_boundary=yes`, `first_timer_watch_zero=yes`, and
`first_memory_write_zero=yes`. The next engineering experiment should move or
mirror the bounded timer progress at the QEMU-thread ready edge; the ready-edge
plus host-fallback probe below is the result of that experiment.

Fresh ready-edge plus host-fallback probe, 2026-06-30:
`build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
is the current front-most browser diagnostic. It uses the new
`pfifo-ready-edge-qemu-pump` mode and preserves the bounded host-fallback pump
count of 4. The ready-edge marker fires before the stream-idle boundary with
`timer_progress=yes`, and the host fallback keeps the useful
`0x80030e84->0x80030f31` post-service edge. The strict B6 checker still fails
at `missing-xbe-executed-marker`. Compared with v2, the shared post-service
poll improves from browser 0 ticks to browser 1 tick, while native remains at
136 ticks. The current next step is no longer pump placement; it is to converge
pre-service tick accumulation before the first watched read, then preserve the
post-service flow so the shared poll does not run 135 tick units behind native.

Fresh PCRTC pre-stream host-pump probe, 2026-06-30:
`build-real-b3-matrix/browser-memory-watch-write-0x3a890-pcrtc-prestream-host4-v2-combined.log`
is negative evidence. It uses
`XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pcrtc-before-stream-idle-then-after-pfifo-empty`
after wiring suppressed PCRTC vblank gates into the diagnostic wait snapshot as
`source=pcrtc op=vblank-suppress`. The browser runtime, B4 display capture,
dashboard read/load/entry-ready, and section-map evidence still pass, but B6
still fails at `missing-xbe-executed-marker`. The host pump now runs before the
PFIFO stream-idle transition (`timer_before_boundary=yes`), but the watched word
remains 0, the run loses the useful browser hard-IRQ service/IRET and shared
post-service poll evidence, and the boundary helper reports
`next=restore-browser-main-loop-timer-progress`. This proves broad PCRTC
pre-stream host pumping is not the promoted path.

Fresh ready-edge-only probe, 2026-06-30:
`build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-v1-combined.log`
is negative evidence. It proves the one-shot ready-edge pump can run before
the PFIFO stream-idle boundary, but without the bounded host fallback it loses
the useful main-loop timer progress and reports
`next=restore-browser-main-loop-timer-progress`.

Fresh PFIFO pre-commit probe, 2026-06-30:
`build-real-b3-matrix/browser-memory-watch-write-0x3a890-precommit-v1-combined.log`
is negative evidence, not a replacement baseline. It reruns the current
write-watch/section-map browser diagnostics with
`XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-at-pfifo-transition-pre-commit-defer-to-idle`,
`XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=1`, and
`XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=0`. It passes browser
runtime evidence, B4 display capture, dashboard read/load/entry-ready, and
section-map evidence, but the strict B6 checker still fails at
`missing-xbe-executed-marker`. It proves that the existing PFIFO pre-commit PIT
pump can run before stream-idle, but that is the wrong direction for the current
boundary: `scripts/xbox-b6-current-boundary.sh --browser-log
build-real-b3-matrix/browser-memory-watch-write-0x3a890-precommit-v1-combined.log`
reports `headless_pump=fail`, `headless_pump_divergence=missing-progress-pump`,
`post_idle_timer_divergence=browser-missing-main-loop-timer-progress`,
`pfifo_transition_divergence=transition-pending-irq-mismatch`,
`browser_post_service_top_edge=0x8001b02f->0x8001b030`, and
`next=restore-browser-main-loop-timer-progress`. The post-service watch-edge
comparator still reports the same 136-tick browser-behind mismatch at the
`0x80030e84->0x80030f31` block. In plain terms: the PFIFO pre-commit pump
delivers the PIT interrupt early but loses the useful bounded main-loop timer
progress and returns to the older `0x8001b030` loop. Do not promote PFIFO
pre-commit pumping as the next architecture; keep the v2 host-pump diagnostic as
the active browser baseline and focus on making browser timer/main-loop
scheduling converge with native at the ready edge without regressing the
post-service edge.

Fresh host-pump count probe, 2026-06-30:
`build-real-b3-matrix/browser-memory-sample-0x3a890-limit136-v1-combined.log`
raises `XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT` from 4 to 136.
It is negative evidence, not a new baseline. The strict B6 checker still fails
at `missing-xbe-executed-marker`; no browser-runtime `dashboard=xbe-executed`
appears. The focused boundary helper reports
`browser_main_loop_timer_progress_events=136`,
`post_idle_timer_divergence=main-loop-timer-progress-count-mismatch`,
`shared_memory_poll_addr=0x8003a890`,
`browser_shared_memory_poll_value=0x00000000`,
`native_shared_memory_poll_ticks=136`,
`browser_shared_memory_poll_ticks=0`, and
`shared_memory_poll_tick_delta=136`. The new timer-watch fields show the later
browser `main-loop=timers` samples do advance the watched word, but only to
`browser_main_loop_timer_max_memory_watch_value=0x0009eb10` =
`browser_main_loop_timer_max_memory_watch_ticks=65` after 136 host-pump
progress events. In plain terms: pumping more timer callbacks moves the counter
later, but it does not make browser CPU flow converge or reach the dashboard.
The next experiment should isolate timer/interrupt ordering and the code path
that updates physical `0x0003a890` relative to the shared post-service poll,
not simply increase the host-pump count again.

Fresh normal-vblank probe, 2026-06-30:
`build-real-b3-matrix/browser-memory-sample-0x3a890-normal-vblank-full-v1-combined.log`
is older negative evidence, not a replacement baseline. It turns
`XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE` back to `normal` while keeping the current
full memory-sample knobs. It passes browser runtime evidence, B4 display
capture, dashboard read/load/entry-ready, and stream-idle, but the strict B6
checker still fails at `missing-xbe-executed-marker`. The focused boundary
helper reports `iret=fail reason=browser-missing-iret-pair`,
`post_idle_flow_divergence=missing-interrupt-service`, a first browser service
on vector `0x33`, and the shared `0x8003a890` poll still reads
`0x00000000` / 0 ticks while native reads `0x0014c080` / 136 ticks. In plain
terms: normal PCRTC vblank does not advance the watched word to the native range
and makes the post-service interrupt/IRET path noisier. Keep the pcrtc-vblank
off full baseline as the controlled browser diagnostic unless new evidence
shows a real browser-runtime `dashboard=xbe-executed`. The newer ready-edge
normal-vblank control reaches the same conclusion under the current ready-edge
plus host-fallback setup: B4/B5/read/load/entry-ready still pass, B6 still fails,
and the transition state is noisier rather than closer.

New focused ordering comparator:
`scripts/xbox-memory-watch-timeline-compare.py` compares native memory-watch
callback events against browser main-loop timer samples and shared
`0x8003a890` kernel-loop polls. The current native watch artifact
`build-real-b3-matrix/native-memory-watch-write-0x3a890-v2/boot-smoke.log`
installs the write-only watch successfully, emits 8 write callbacks, and shows
the first watched write at `eip=0x80030e84` with value `0x000cf850` / 85 ticks.
The first focused native shared poll after stream-idle reads `0x00177fa0` / 154
ticks at the `0x80030e84->0x80030f31` edge. Against the current browser v2
write-watch diagnostic, the comparator reports
`divergence=browser-shared-poll-before-watch-catchup`,
`shared_poll_tick_delta=154`,
`browser_timer_max_relation=browser-under-native-shared-poll`,
`browser_first_shared_poll_value=0x00000000`, and
`browser_max_timer_watch_ticks=0`. Against the limit136 negative probe, the
same comparator still reports the same divergence and relation, with
`browser_max_timer_watch_ticks=65`. This makes the front-most question sharper:
why does browser reach the same post-stream-idle poll before the watched
elapsed/tick word has been advanced to the native range?

New focused edge comparator:
`scripts/xbox-post-service-watch-edge-compare.py` compares the watched
`0x8003a890` value immediately before and after the post-service
`0x80030e84 -> 0x80030f31` block. Against the current pcrtc-vblank-off browser
full baseline, it reports
`divergence=pre-block-watch-value-mismatch`, `pre_tick_delta=136`,
`post_tick_delta=136`, and `block_delta_match=yes`. Native enters the block at
136 ticks and leaves at 137; browser enters at 0 and leaves at 1. The useful
conclusion is that this block increments the watched word by the same one tick
on both sides. The browser is already behind before reaching it, so the next
causal target is pre-block timer/tick accumulation and scheduling before the
shared post-service edge, not the arithmetic/update inside the
`0x80030e84` block.

Current code tags `main-loop=timers` with `source=main-loop-wait` for the
regular QEMU main-loop path and `source=browser-headless-host-pump-bounded` for
the browser headless host-side bounded timer pass. The browser host pump is
gated by `xemu_xbe_boot_trace_main_loop_timer_pump_ready()`, can run one expired
virtual timer callback per poll at the pre-transition activity point and again
after PFIFO pusher-empty in the combined mode, and can be capped for diagnostics
with `XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT` through
`/xemu-fixtures/browser_headless_timer_pump_progress_limit.txt`; this is still a
diagnostic bridge toward native-equivalent scheduling, not final B6 proof.

New diagnostic-only memory-watch access filter:
`XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS` now accepts `off`, `all`, `read`, or
`write`; browser runs receive the same setting through
`/xemu-fixtures/xbe_memory_watch_access.txt`. Markers include
`access_filter=...`. Keep the default unset/off for cheap browser
`main-loop=timers` sampling. Use `write` only for the next focused provenance
run when we need callback evidence for who writes physical `0x0003a890` before
the shared post-service poll; it is still diagnostic-only and must not satisfy
B6 without browser-runtime `dashboard=xbe-executed` and native-frame visual
match evidence.

Important implementation status: native builds use `-DXBOX=1`, so
`ACCESS=write` installs real mem-access callbacks there. Browser builds define
`CONFIG_XEMU_BROWSER_BOOT`; the callback typedefs/API, TLB watchpoint hooks,
physmem callback checks, and `xemu-xbe.c` memory-watch installer are now
broadened for `XBOX || CONFIG_XEMU_BROWSER_BOOT`. The v2 browser write-watch
run proves callback installation works in browser; keep it diagnostic-only.

The previous after-PFIFO-only bounded diagnostic
`browser-runtime-firefox-bidi-headless-gate-bounded-no-tcg-limit4-v1-combined.log`
is now superseded by the combined pre-transition plus after-empty diagnostic. It
is still useful because it removed the timer-progress count mismatch and proved
browser-runtime read/load, entry-ready, section-map, PFIFO stream-idle, PIC ack,
vector `0x30` service, and IRET evidence, but it should not be the first default
when the newer combined artifact is present.

The earlier pre-transition-only host-pump probe is negative evidence, not a
promoted baseline.
`browser-runtime-firefox-bidi-headless-pretransition-activity-filtered-fastpoll-nosideeffect-limit4-v1-combined.log`
uses `XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-before-transition-activity`,
fast 2 ms post-entry host polling, TCG timer pumping disabled, and the cleaned
sleep-interval path that no longer calls the side-effecting pump-readiness
function before sleeping. It reaches browser-runtime read/load/entry-ready,
section-map, and PFIFO stream-idle, then times out. The B6 checker still fails
at `missing-xbe-executed-marker`, and the boundary helper reports
`browser_main_loop_timer_progress_events=0`,
`post_idle_timer_divergence=browser-missing-main-loop-timer-progress`, and
`next=restore-browser-main-loop-timer-progress` for that artifact. There are no
confirmed `headless=timer-pump-step` or `main-loop=timers` progress markers in
the run. Treat this as proof that gate/readiness logging alone is not enough;
the next pre-transition experiment must cause an actual bounded timer pump at
the gated point, or it should stay on the combined pre-transition plus
after-empty focused baseline.

The intermediate double-pump artifact
`build-real-b3-matrix/browser-runtime-firefox-bidi-headless-pretransition-activity-filtered-doublepump-limit4-v1-combined.log`
proved the pre-sleep pump point can fire, but produced only one browser
main-loop timer-progress event and still failed B6. Keep it as implementation
evidence for the pump point, not as a baseline.

The broad earlier-pump variant
`build-real-b3-matrix/browser-runtime-firefox-bidi-headless-pump-limit4-anywhere-v1-combined.log`
is diagnostic-only and should not replace the current boundary. It allows the
same 4 capped host timer-progress callbacks before PFIFO pusher-empty. That run
proves earlier host timer delivery can reach native-like IRQ/IRET frames such as
`0x80014720`, but it regresses the command-stream boundary:
`pfifo_transition=fail`, `post_idle_flow_divergence=command-stream-not-idle`,
and the B6 checker still fails at `missing-xbe-executed-marker`.

Historical native negative controls: without the graphic-update pump,
`build-real-b3-matrix/native-xbe-detector-proof-v1/boot-smoke.log` proves only
`dashboard=xbe-executed-detector-proof result=pass` and times out after
stream-idle without actual dashboard execution. This marker remains
diagnostic-only and must not satisfy B6.

Short-animation negative test: `XEMU_SMOKE_SKIP_BOOT_ANIM=1` now makes
`scripts/xbox-boot-smoke.sh` write `skip_boot_anim = true`, and the targeted
native run
`build-real-b3-matrix/native-skip-boot-anim-xbe-detector-proof-v1/boot-smoke.log`
does launch QEMU with `short-animation=on`. It still reports
`NATIVE_ACTUAL_XBE_EXECUTION result=fail
reason=no-strict-dashboard-executed-marker`, with zero phys-match execution
probes and no direct entry execution path. Do not repeat this run as the next
step unless the native/headless code changes. The handoff checker comparison
also reports both default and short-animation native logs ending in the same
`native-headless-timeout-after-stream-idle` terminal state with
`either_actual_xbe_executed=no`.

## Success Contract

B6 must require all of these:

- `BOOT_MARK b6 dashboard=xbe-read context=browser-runtime ...`
- `BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime ... source=virtual-header ...`
- `BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime status=ready entry_code_read=yes phys_match=yes ...`
- `BOOT_MARK b6 dashboard=xbe-executed context=browser-runtime ... phys_match=yes section_index=... section_flags=0x...`
- `NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless ... dashboard=xbe-executed ...`
- `BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes ...`

Do not weaken this contract. Entry-ready evidence, section-map evidence,
non-empty B4 display, high-alias diagnostics, interrupt parity, or native-only
dashboard evidence must not satisfy B6 by themselves.

## Critique Of Current Path

The path to B6 is much better than the earlier broad diagnostic phase, but the
current risk is wasting cycles on another pump-placement variant instead of
proving the exact browser scheduling gap.

The strong part is the evidence discipline. B3/B4/B5 are no longer the problem,
the strict B6 contract is sound, and the checker correctly refuses B4-only,
section-map-only, entry-ready-only, native-only execution, or visual-only
evidence. Browser artifacts still fail exactly where they should:
`missing-xbe-executed-marker`.

Native execution risk is now resolved. `native-headless-graphic-update-v2`
proves strict dashboard execution and native reference capture, so the remaining
blocker is browser-side post-idle/post-service CPU flow.

The sharpest current evidence is the tick/poll split around physical
`0x0003a890`. Native reaches the shared post-service poll with 136 tick units;
the current ready-edge browser reaches the same useful post-service edge with 1
tick. Both sides execute the watched `0x80030e84` block and increment by one
tick, so the arithmetic inside that block looks aligned. The browser is already
behind before its first watched read at `0x80014f32->0x80030e84`, where it reads
0 ticks. That makes the next target pre-service tick accumulation before the
first watched read, not another broad "make timers run more" pass.

The main risk is broadening instead of narrowing. We already have many logs that
prove the same pattern: `xboxdash.xbe` is read, loaded, and entry-ready, but CPU
execution remains in protected-mode kernel/high-alias paths whose physical pages
do not match the loaded dashboard XBE. More generic long browser runs, raw
host-pump count increases, normal-vblank reruns, PCRTC pre-stream pumping, or
PFIFO pre-commit pumps can repeat that fact without explaining causality. Treat
those modes as probes, not as the final architecture.

Do not overfit to `0x0003a890` as the whole bug. It is the strongest current
diagnostic because it cleanly shows browser time/tick state is late before the
first watched read. The next useful work is to identify that word's producer and
the timer/main-loop state before the first browser read, then validate whether a
change moves the first browser read toward native's 136-tick value without
regressing B4/B5, section-map, stream-idle, vector `0x30` service/IRET, or the
post-service watch edge.

## Recommended Path

1. Preserve the artifact roles: use
   `browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
   as the active browser B6 diagnostic,
   `native-headless-graphic-update-v2/boot-smoke.log` as the native
   execution/reference baseline,
   `browser-runtime-firefox-bidi-section-map-v2-combined.log`
   as the B5-pass/read-proof browser baseline,
   `browser-memory-watch-write-0x3a890-v2-combined.log`
   as the stable write-watch browser diagnostic, and
   `browser-memory-sample-0x3a890-full-baseline-v1-combined.log`
   as the previous focused diagnostic. Keep
   `native-post-iret-flow-v1/boot-smoke.log` as the historical IRET comparator
   reference when comparing against older browser artifacts.
2. Add or use a compact comparator for the exact current window:
   final PFIFO commit -> hard IRQ set/reset -> PIC ack -> vector `0x30`
   service -> IRET -> first watched `0x0003a890` read/write events -> next N
   translated-block edges. The comparator should foreground the pre-first-read
   state, not only the post-service block.
3. Native detector acceptance, actual native dashboard execution, and native
   framebuffer reference are proven by
   `native-headless-graphic-update-v2/boot-smoke.log`; keep
   `XEMU_HEADLESS_BOOT_GRAPHIC_UPDATE=1` for native headless reference runs.
4. Converge browser pre-service tick accumulation and post-service CPU flow
   after the ready-edge plus host-fallback probe: final PFIFO commit -> bounded
   main-loop timer progress -> PIC ack -> vector `0x30` service -> IRET ->
   first watched `0x0003a890` read -> shared post-service poll -> next
   translated-block edges. The latest ready-edge run keeps the useful
   `0x80030e84->0x80030f31` edge and improves the shared poll from browser 0
   ticks to browser 1 tick, while native is still at 136 ticks. The next target
   is why browser arrives at the first watched read and shared post-service poll
   before the watched word has accumulated the native value. Start from the
   first browser watched read at `0x80014f32->0x80030e84`, where browser has 0
   ticks while native's comparable first watched read has 136 ticks. The
   limit136 negative probe shows that forcing 136 browser host-pump progress
   callbacks still leaves the shared poll at 0 units and only reaches 65 units
   later in `main-loop=timers` samples, so raw callback count is not the causal
   fix. New code adds the diagnostic-only
   `BOOT_MARK b6 memory-watch ...` marker, enabled with
   `XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS=0x0003a890` and capped with
   `XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT`; browser runs can receive the same
   settings through `/xemu-fixtures/xbe_memory_watch_phys.txt` and
   `/xemu-fixtures/xbe_memory_watch_limit.txt`. The v2 browser write-only watch
   confirms callback attribution now works in browser-runtime without losing the
   focused B4/B5 evidence. It shows the first browser watched write at
   `eip=0x80030e84` still sees zero ticks. The new headless pump-placement
   comparator showed the host loop observed pump readiness before the PFIFO
   stream-idle boundary, but actual v2 timer progress occurred after that
   boundary. The ready-edge plus host-fallback probe moves one timer pass to
   the PFIFO ready edge and improves the shared poll from browser 0 ticks to
   browser 1 tick, but native is still at 136 ticks. Treat this as progress and
   not as completion; the next causal target is pre-service tick accumulation
   before the first watched read, plus the timer/main-loop scheduling state that
   feeds it, not more pump-placement proof.
   The marker is diagnostic-only and must not satisfy B6. The earlier-pump run
   shows that moving timer delivery too broadly can reach native-like IRQ frames
   but regresses command-stream idle. The pre-transition-only fast-poll run shows
   that a readiness/gate marker without `headless=timer-pump-step` and
   `main-loop=timers` progress is a false lead. The fresh PFIFO pre-commit run
   also regresses the current boundary: it fires the PIT path early, but removes
   browser main-loop timer progress and falls back to the `0x8001b02f->0x8001b030`
   loop. Treat browser-only TCG timer pumps, broad host timer pumping, and PFIFO
   pre-commit pumps as probes, not the final architecture.
5. Keep `XEMU_BROWSER_DASHBOARD_CAPTURE_REQUIRE_EXECUTED=1`. Native reference
   capture can be hardened separately, but final browser-vs-native frame
   comparison should wait until true browser-runtime `dashboard=xbe-executed`
   exists.

## Commands To Start From

Use the first four command groups for normal continuation. Commands after the
supporting/regression divider are for focused sub-comparisons, evidence-contract
changes, explicit comparison against old artifacts, or regressions.

Preferred focused boundary summary:

```sh
scripts/xbox-b6-current-boundary.sh
```

Latest browser B6 checker:

```sh
scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

Latest section-map sanity check:

```sh
scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

Current pre-service tick-gap comparison:

```sh
scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

Current native execution/reference sanity check:

```sh
scripts/xbox-native-actual-xbe-execution-check.py \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log
scripts/xbox-native-reference-evidence-check.sh \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log
```

Supporting and regression-only commands:

Native detector proof artifact:

```sh
rg 'dashboard=xbe-executed-detector-proof' build-real-b3-matrix/native-xbe-detector-proof-v1/boot-smoke.log
```

Native headless handoff boundary:

```sh
scripts/xbox-native-headless-handoff-check.py \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log
```

Native graphic-update vs old no-update handoff comparison:

```sh
scripts/xbox-native-headless-handoff-check.py \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --compare-log build-real-b3-matrix/native-xbe-detector-proof-v1/boot-smoke.log \
  --compare-label no-graphic-update
```

Short-animation negative artifact:

```sh
scripts/xbox-native-actual-xbe-execution-check.py \
  build-real-b3-matrix/native-skip-boot-anim-xbe-detector-proof-v1/boot-smoke.log
```

Formal B6 gate for the B5-pass baseline:

```sh
scripts/xbox-dashboard-loaded-evidence-check.sh build-real-b3-matrix/browser-runtime-firefox-bidi-section-map-v2-combined.log
```

Section-map quality gate for the B5-pass baseline:

```sh
scripts/xbox-dashboard-section-map-evidence-check.sh build-real-b3-matrix/browser-runtime-firefox-bidi-section-map-v2-combined.log
```

Current native/browser IRET frame comparison against the promoted native
execution/reference baseline:

```sh
scripts/xbox-iret-frame-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

Current post-command loop comparison:

```sh
scripts/xbox-post-command-loop-clusters.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

Current post-service memory-poll comparison:

```sh
scripts/xbox-post-service-memory-poll-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

Current memory-watch timeline comparison:

```sh
scripts/xbox-memory-watch-timeline-compare.py \
  --native-log build-real-b3-matrix/native-memory-watch-write-0x3a890-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

Current browser headless pump-placement comparison:

```sh
scripts/xbox-headless-pump-placement-compare.py \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

Current post-service watch-edge comparison:

```sh
scripts/xbox-post-service-watch-edge-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

Latest negative limit136 host-pump comparison:

```sh
scripts/xbox-b6-current-boundary.sh \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-sample-0x3a890-limit136-v1-combined.log
```

Latest negative ready-edge normal-vblank comparison:

```sh
scripts/xbox-b6-current-boundary.sh \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-normal-vblank-v1-combined.log
```

Older negative normal-vblank comparison:

```sh
scripts/xbox-b6-current-boundary.sh \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-sample-0x3a890-normal-vblank-full-v1-combined.log
```

Completed focused memory-watch native run:

```sh
scripts/xbox-native-actual-xbe-execution-check.py \
  build-real-b3-matrix/native-memory-watch-write-0x3a890-v2/boot-smoke.log
```

Comparable browser memory-sample rerun:

```sh
XEMU_REAL_B3_OUT_DIR=build-real-b3-matrix/browser-memory-sample-0x3a890-full-baseline-v1 \
XEMU_REAL_B3_SKIP_NATIVE_WASM=1 \
XEMU_REAL_B3_SKIP_BROWSER_BLOCK=1 \
XEMU_REAL_B3_BROWSER_RUNTIME_DRIVER=firefox-bidi \
XEMU_REAL_B3_BROWSER_RUNTIME_MS=150000 \
XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=off \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT=32 \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT=32 \
XEMU_BOOT_TRACE_XBE_PIC_IRQ_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT=256 \
XEMU_BOOT_TRACE_XBE_IRET_LIMIT=256 \
XEMU_BOOT_TRACE_XBE_PIT_IRQ_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_MAIN_LOOP_TIMER_LIMIT=128 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-before-transition-activity-then-after-pfifo-empty \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS=0x0003a890 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT=64 \
scripts/xbox-real-b3-matrix.sh
```

Optional focused browser write-provenance rerun, only after the cheap
memory-sample comparison needs callback attribution:

```sh
XEMU_REAL_B3_OUT_DIR=build-real-b3-matrix/browser-memory-watch-write-0x3a890-v2 \
XEMU_REAL_B3_SKIP_NATIVE_WASM=1 \
XEMU_REAL_B3_SKIP_BROWSER_BLOCK=1 \
XEMU_REAL_B3_BROWSER_RUNTIME_DRIVER=firefox-bidi \
XEMU_REAL_B3_BROWSER_RUNTIME_MS=150000 \
XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=off \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT=32 \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT=32 \
XEMU_BOOT_TRACE_XBE_PIC_IRQ_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT=256 \
XEMU_BOOT_TRACE_XBE_IRET_LIMIT=256 \
XEMU_BOOT_TRACE_XBE_PIT_IRQ_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_MAIN_LOOP_TIMER_LIMIT=128 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-before-transition-activity-then-after-pfifo-empty \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS=0x0003a890 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT=64 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS=write \
scripts/xbox-real-b3-matrix.sh
```

Current ready-edge plus host-fallback browser rerun:

```sh
XEMU_REAL_B3_OUT_DIR=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1 \
XEMU_REAL_B3_SKIP_NATIVE_WASM=1 \
XEMU_REAL_B3_SKIP_BROWSER_BLOCK=1 \
XEMU_REAL_B3_BROWSER_RUNTIME_DRIVER=firefox-bidi \
XEMU_REAL_B3_BROWSER_RUNTIME_MS=150000 \
XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=off \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT=32 \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT=32 \
XEMU_BOOT_TRACE_XBE_PIC_IRQ_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT=256 \
XEMU_BOOT_TRACE_XBE_IRET_LIMIT=256 \
XEMU_BOOT_TRACE_XBE_PIT_IRQ_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_MAIN_LOOP_TIMER_LIMIT=128 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS=0x0003a890 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT=64 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS=write \
scripts/xbox-real-b3-matrix.sh
```

Optional native callback memory-watch rerun:

```sh
XEMU_SMOKE_OUT_DIR=build-real-b3-matrix/native-memory-watch-write-0x3a890-v2 \
XEMU_SMOKE_MS=120000 \
XEMU_HEADLESS_BOOT_GRAPHIC_UPDATE=1 \
XEMU_BOOT_TRACE=1 \
XEMU_BOOT_TRACE_CONTEXT=native-headless \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS=0x0003a890 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT=64 \
scripts/xbox-boot-smoke.sh docker-headless
```

Do not use all-access browser callback memory-watch as the default next run. The
write-only v2 browser callback watch is the current focused callback evidence;
all-access browser callback-watch attempts were too perturbing/slow.

Combine the browser write-watch log with FATX read proof:

```sh
scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd "$XEMU_HDD" \
  --log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  --require-context browser-runtime
```

Current post-idle interrupt-flow comparison:

```sh
scripts/xbox-post-idle-interrupt-flow-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

Latest negative pre-transition host-pump comparison:

```sh
scripts/xbox-b6-current-boundary.sh \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-runtime-firefox-bidi-headless-pretransition-activity-filtered-fastpoll-nosideeffect-limit4-v1-combined.log
```

## Guardrails

- Do not chase browser display polish before `dashboard=xbe-executed`.
- Do not treat browser-only timer pump behavior as the final fix unless it
  converges with native scheduling semantics.
- Do not let `scripts/xbox-boot-next-step.sh` be the only guide when it points
  back to the known-failing B6 checker; use the current diagnostic boundary and
  `scripts/xbox-b6-current-boundary.sh` before starting another run.
- Keep proprietary Xbox assets local and untracked.
