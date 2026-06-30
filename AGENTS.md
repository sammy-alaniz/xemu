# Repository Agent Notes

## Xbox Browser Boot Work

Primary references: `xbox-browser-boot-plan.md` and `goal.md`. Use
`goal.md` for the current B6 dashboard-loaded objective, critique, active
baseline, and next diagnostic commands. If `AGENTS.md` is committed or shared,
`goal.md` must be included with it.

When working on the browser/WebAssembly Xbox boot effort, use the plan's boot ladder and phase ordering. Do not skip directly to graphics, audio, networking, or a polished browser UI before the headless boot path is proven.

Boot milestones:

- B0: process starts and constructs an Xbox machine.
- B1: firmware memory loads and CPU execution begins.
- B2: core Xbox devices initialize or show register activity.
- B3: storage boot path is active through real HDD/block reads.
- B4: boot animation or dashboard reaches a visible display path.
- B5: browser host is usable for config, persistence, start/stop, and logs.
- B6: dashboard XBE is loaded/executed and visible browser frames match a native reference closely enough to treat the dashboard as loaded.

Current long-term goal:

- B3/B4/B5 are complete evidence gates for the browser boot work. The active follow-up is B6 dashboard-loaded verification.
- B6 is not complete until browser-runtime evidence proves dashboard XBE read/load/execute and browser frames match native reference frames. Native-only dashboard evidence and B4 non-empty display frames are useful diagnostics, but they do not satisfy B6.
- Keep the active objective focused on B6: reliable dashboard/XBE markers, native reference frame capture, Playwright-preferred browser capture, Firefox BiDi fallback, browser-vs-native comparison, and an auditable B6 checker.
- Read `goal.md` before starting new B6 work. The current critique is that the
  path is directionally right but too diagnostic-heavy around the same boundary.
  B3/B4/B5 are no longer the problem, the strict B6 checker is sound, and
  native execution/reference capture are solved by
  `native-headless-graphic-update-v2`. The remaining blocker is browser-side
  post-idle/post-service CPU flow, narrowed to pre-service tick accumulation:
  native reaches the shared `0x0003a890` poll with 136 tick units, the current
  ready-edge browser reaches the same useful edge with 1 tick, and browser is
  already behind before its first watched read at
  `0x80014f32->0x80030e84`.
- Loop-control rule: before starting a new run, probe, or code change, state the
  one new field it can change or explain. Do not rerun known-good B3/B4/B5,
  section-map, native-reference, or known-negative pump/vblank/precommit probes
  just to re-confirm `missing-xbe-executed-marker`.
- After every experiment, run, or probe, write a numbered markdown summary in
  `history/` using `history/<next-number>-<short-run-title>.md`. Include the
  purpose, exact command(s), inputs/artifacts, loop-guard field(s), findings,
  decision, and next step. Keep `history/0-template.md` as the template and do
  not count it as a run. Do not start another run before writing the previous
  history entry unless the run produced no useful artifact; if the failure
  changes the next action, write the failed-run entry too.
- Treat `build-real-b3-matrix/browser-runtime-firefox-bidi-section-map-v2-combined.log`
  as the stable B5-pass/read-proof browser baseline, not the front-most B6 CPU
  diagnostic. Treat
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
  as the active browser B6 diagnostic. Treat
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log` as the
  native execution/reference baseline.
- The primary progress metric is moving
  `pre_service_browser_first_watch_read_ticks` from 0 toward native's 136 while
  preserving B4/B5, dashboard read/load/entry-ready, section-map, stream-idle,
  vector `0x30` service/IRET, and the `0x80030e84->0x80030f31` post-service
  edge.
- The stable browser write-watch diagnostic is
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-v2-combined.log`.
  It preserves the full focused baseline with rebuilt wasm and
  `XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS=write`, reaches B4 display capture,
  PFIFO stream-idle, 4 `main-loop=timers
  source=browser-headless-host-pump-bounded` progress events, no browser TCG
  timer progress, PIC ack, vector `0x30` service, and IRET; the B6 checker
  still correctly fails at `missing-xbe-executed-marker`. Browser callback
  installation now works after broadening the mem-access callback path for
  `CONFIG_XEMU_BROWSER_BOOT`: the log has `memory-watch-install result=pass`
  and two write callbacks at `eip=0x80030e84`, with values
  `0x00000000` then `0x00002710`.
- The current front-most browser diagnostic is
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`.
  It uses the new diagnostic-only
  `XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump` with
  the bounded host fallback still capped at 4 progress events. The one-shot
  `main-loop=timers source=browser-ready-edge-qemu-pump` marker fires before
  the PFIFO stream-idle boundary, and the host fallback keeps the useful
  `0x80030e84->0x80030f31` post-service edge. The strict B6 checker still
  correctly fails at `missing-xbe-executed-marker`; the shared poll improves
  from browser 0 ticks in v2 to browser 1 tick here, while native remains at
  136 ticks. The next target is the producer/timer/main-loop state before the
  first browser watched read at `0x80014f32->0x80030e84`, not more
  pump-placement proof.
- The PCRTC pre-stream host-pump probe
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-pcrtc-prestream-host4-v2-combined.log`
  is negative evidence and must not replace the ready-edge plus host-fallback
  baseline. It adds the diagnostic-only
  `XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pcrtc-before-stream-idle-then-after-pfifo-empty`
  and publishes suppressed PCRTC vblank gates as wait state
  `source=pcrtc op=vblank-suppress`. This proves the browser host pump can run
  before PFIFO stream-idle, but it is too early: the watched word remains at 0
  ticks, the useful browser hard-IRQ service/IRET and shared post-service poll
  disappear, and the current boundary helper reports
  `headless_pump_divergence=pump-before-stream-idle-transition`,
  `post_idle_timer_divergence=browser-missing-main-loop-timer-progress`, and
  `next=restore-browser-main-loop-timer-progress`. Treat it as placement
  evidence only.
- The ready-edge plus host-fallback normal-vblank control
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-normal-vblank-v1-combined.log`
  is negative evidence. It keeps the ready-edge QEMU-thread pump and bounded
  host fallback with `XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=normal`; browser
  runtime, B4 display capture, dashboard read/load/entry-ready, and section-map
  evidence still pass, but strict B6 still fails at
  `missing-xbe-executed-marker`. The boundary shifts to noisier CPU/IRQ state
  (`pfifo_transition_divergence=transition-pending-irq-mismatch`) and the
  watched word remains far behind native. Do not promote normal PCRTC vblank as
  the active browser baseline without fresh strict browser-runtime
  `dashboard=xbe-executed` evidence.
- The ready-edge-only probe
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-v1-combined.log`
  is negative evidence: it proves the ready-edge pump can fire before the PFIFO
  stream-idle boundary, but without bounded host fallback it regresses to the
  older `0x8001b02f->0x8001b030` loop and reports
  `next=restore-browser-main-loop-timer-progress`.
- The previous cheap memory-sample browser diagnostic is
  `build-real-b3-matrix/browser-memory-sample-0x3a890-full-baseline-v1-combined.log`.
  It preserves the full focused baseline while adding cheap main-loop memory
  samples for physical `0x0003a890`. It reaches B4 display capture, PFIFO
  stream-idle, 8 `headless=timer-pump-step` markers, 4
  `main-loop=timers source=browser-headless-host-pump-bounded` progress events,
  no browser TCG timer progress, PIC ack, vector `0x30` service, and IRET; the
  B6 checker still correctly fails at `missing-xbe-executed-marker`.
- The older host-pump browser diagnostic is
  `build-real-b3-matrix/browser-runtime-firefox-bidi-headless-pretransition-then-empty-filtered-limit4-v1-combined.log`.
  It combines the pre-transition activity pump with after-PFIFO-empty pumping,
  preserves read/load/entry-ready and section-map evidence, matches the promoted
  native count with 4 browser main-loop timer-progress events, keeps browser TCG
  timer progress at 0, and still fails B6 correctly at
  `missing-xbe-executed-marker`.
- Start the current B6 slice with `scripts/xbox-b6-current-boundary.sh`. It runs
  the strict B6 evidence gate plus the focused section-map, native actual
  execution, native headless handoff, IRET, post-command-loop, post-idle-flow,
  and PFIFO-transition comparators against the frozen baseline logs without
  starting emulation.
- The next causal slice is final PFIFO commit -> hard IRQ set/reset -> PIC ack
  -> vector `0x30` service -> IRET -> first watched `0x0003a890` read/write
  events -> next N translated-block edges. Foreground the pre-first-read timer
  and main-loop state. Do not restart broad B3/B4/B5, storage, display, or
  generic timer-pump exploration unless fresh evidence regresses the current
  boundary.
- The current focused boundary summary reports
  `post_idle_timer_divergence=none`,
  `loop_divergence=memory-poll-mismatch`,
  `post_service_memory_poll_divergence=shared-memory-poll-value-mismatch`,
  `shared_memory_poll_addr=0x8003a890`,
  `post_idle_flow_divergence=missing-interrupt-service`,
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
  `native_watch_install=pass`, `browser_watch_install=pass`,
  `native_watch_write_events=8`, `browser_watch_write_events=3`,
  `native_first_watch_write_ticks=85`,
  `browser_first_watch_write_ticks=0`,
  `browser_last_watch_write_value=0x00004e20`,
  `headless_pump=pass`,
  `headless_pump_divergence=pump-before-stream-idle-boundary`,
  `headless_pump_timer_before_boundary=yes`,
  `headless_pump_timer_after_boundary=no`,
  `headless_pump_first_timer_watch_zero=yes`,
  `headless_pump_first_memory_write_zero=yes`,
  `native_main_loop_timer_progress_events=4`,
  `browser_main_loop_timer_progress_events=4`,
  `native_tcg_timer_progress_events=0`, `browser_tcg_timer_progress_events=0`,
  `pfifo_transition_divergence=post-transition-hard-irq-set-mismatch`,
  and `next=converge-browser-post-service-flow`. Treat browser post-service
  CPU-flow convergence, not timer-progress count restoration, as the front-most
  browser-side target. The sharpest sub-target is now before the first watched
  read at `0x80014f32->0x80030e84`: native has already accumulated 136 tick
  units, while browser has 0, and the first browser watched write happens after
  that read. Instrument the producer and reads of physical `0x0003a890`, plus
  timer deadlines, virtual clock deltas, main-loop timer dispatch, and CPU/yield
  ordering before that first browser read. Only promote changes that move the
  first browser read toward native's 136-tick value without regressing B4/B5,
  section-map, stream-idle, vector `0x30` service/IRET, or the post-service
  watch edge.
- Current pre-service tick-gap comparator:
  `scripts/xbox-pre-service-tick-gap-compare.py --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`.
  The expected current result is
  `PRE_SERVICE_TICK_GAP_COMPARE result=pass
  divergence=browser-first-watch-read-before-catchup`. It proves the browser is
  already behind before the shared post-service read and before the
  `0x80030e84->0x80030f31` one-tick write block. Use it before adding another
  pump-placement, normal-vblank, or post-service arithmetic probe.
- Stable write-filter browser evidence, 2026-06-30: the diagnostic
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-v2-combined.log`
  passes B5/B4, applies `trace_xbe_memory_watch_access=write`, preserves
  dashboard read/load/entry-ready and section-map evidence, and still fails B6
  at `missing-xbe-executed-marker`. The comparator reports
  `browser_watch_install=pass`, `browser_watch_access_events=2`,
  `browser_watch_write_events=2`,
  `browser_first_watch_write_eip=0x80030e84`,
  `browser_first_watch_write_value=0x00000000`,
  `browser_last_watch_write_value=0x00002710`,
  `browser_timer_watch_samples=4`, `browser_max_timer_watch_value=0x00000000`,
  and `browser_first_shared_poll_value=0x00000000`. Native proof in
  `build-real-b3-matrix/native-memory-watch-write-0x3a890-v2/boot-smoke.log`
  confirms the access filter works in native: `memory-watch-install ...
  access_filter=write` plus write-only callbacks at `eip=0x80030e84`. The next
  question is no longer callback installation; it is why browser reaches the
  shared post-service poll before physical `0x0003a890` accumulates native-like
  ticks. `scripts/xbox-headless-pump-placement-compare.py` now proves the host
  loop sees pump readiness before the PFIFO stream-idle boundary, but actual
  timer progress happens after that boundary and still samples the watched word
  as zero. The ready-edge plus host-fallback probe above is the result of that
  experiment; it improves the shared poll from 0 ticks to 1 tick, but still
  leaves browser 135 tick units behind native. The current next step is
  post-service CPU-flow and pre-poll tick accumulation, not another
  pump-placement run.
- Fresh PFIFO pre-commit negative evidence, 2026-06-30:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-precommit-v1-combined.log`
  reruns the current write-watch/section-map browser diagnostics with
  `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-at-pfifo-transition-pre-commit-defer-to-idle`,
  `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=1`, and browser headless host
  pump progress disabled. It passes browser runtime evidence, B4 display
  capture, dashboard read/load/entry-ready, and section-map evidence, but still
  fails B6 at `missing-xbe-executed-marker`. The boundary helper reports
  `headless_pump=fail`, `headless_pump_divergence=missing-progress-pump`,
  `post_idle_timer_divergence=browser-missing-main-loop-timer-progress`,
  `pfifo_transition_divergence=transition-pending-irq-mismatch`,
  `browser_post_service_top_edge=0x8001b02f->0x8001b030`, and
  `next=restore-browser-main-loop-timer-progress`. Do not promote PFIFO
  pre-commit pumping; it fires the PIT path early but regresses the useful v2
  host-pump boundary.
- Fresh negative evidence, 2026-06-30: do not simply raise the browser host-pump
  progress cap again. The diagnostic
  `build-real-b3-matrix/browser-memory-sample-0x3a890-limit136-v1-combined.log`
  raises `XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT` to 136 and
  emits `browser_main_loop_timer_progress_events=136`, but still fails B6 at
  `missing-xbe-executed-marker`. At the shared post-service poll, browser reads
  `0x00000000` at `0x8003a890` while native reads `0x0014c080`; the boundary
  helper reports `browser_shared_memory_poll_ticks=0` and
  `shared_memory_poll_tick_delta=136`. Later browser `main-loop=timers` samples
  only reach `browser_main_loop_timer_max_memory_watch_value=0x0009eb10` /
  `browser_main_loop_timer_max_memory_watch_ticks=65`. This proves raw pump
  count is not sufficient; the next slice is timer/interrupt ordering and the
  code path that updates physical `0x0003a890` before the shared poll.
- Older negative normal-vblank evidence, 2026-06-30: do not simply turn PCRTC
  vblank back on as the next default. The diagnostic
  `build-real-b3-matrix/browser-memory-sample-0x3a890-normal-vblank-full-v1-combined.log`
  uses the current full memory-sample knobs with
  `XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=normal`. It passes browser runtime
  evidence, B4 display capture, dashboard read/load/entry-ready, and
  stream-idle, but still fails B6 at `missing-xbe-executed-marker`. The boundary
  helper reports `iret=fail reason=browser-missing-iret-pair`, first browser
  service on vector `0x33`, and the shared `0x8003a890` poll at
  `0x00000000` / 0 ticks while native reads `0x0014c080` / 136 ticks. Keep the
  pcrtc-vblank-off full baseline as the controlled browser diagnostic unless
  fresh evidence shows real browser-runtime dashboard execution. The newer
  ready-edge normal-vblank control named above confirms the same direction under
  the current ready-edge plus host-fallback setup: B4/B5/read/load/entry-ready
  still pass, B6 still fails, and the transition state is noisier rather than
  closer.
- Stable write-watch ordering comparator:
  `scripts/xbox-memory-watch-timeline-compare.py --native-log build-real-b3-matrix/native-memory-watch-write-0x3a890-v2/boot-smoke.log --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-v2-combined.log`.
  The stable v2 expected result is
  `MEMORY_WATCH_TIMELINE_COMPARE result=pass
  divergence=browser-shared-poll-before-watch-catchup`. It shows the native
  watch installs successfully, emits 64 access callbacks with 25 writes, and the
  first watched write occurs at `eip=0x80030e84` with value `0x000c8320` / 82
  ticks. The first focused native post-stream-idle shared poll already reads
  `0x00138800` / 128 ticks at `0x80014f32->0x80030e84`, while the current
  browser full-baseline first focused shared poll reads `0x00000000` and its
  max timer-watch sample is only 1 tick. Against the limit136 probe, browser
  max timer-watch sample reaches 65 ticks but still remains under the native
  focused shared poll and no `dashboard=xbe-executed` appears.
- New focused edge comparator:
  `scripts/xbox-post-service-watch-edge-compare.py --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log --browser-log build-real-b3-matrix/browser-memory-sample-0x3a890-full-baseline-v1/browser-runtime.log`.
  The current expected result is
  `POST_SERVICE_WATCH_EDGE_COMPARE result=pass
  divergence=pre-block-watch-value-mismatch ... block_delta_match=yes`. Native
  enters the `0x80030e84 -> 0x80030f31` block at 136 ticks and leaves at 137;
  browser enters at 0 and leaves at 1. This proves that block's own watched-word
  delta is equivalent, while browser is already behind before it reaches the
  block. Treat pre-block timer/tick accumulation and scheduling as the next
  causal target.
- The next focused causal probe is the diagnostic-only low-RAM memory watch for
  the shared poll word. Native callback watch evidence is useful, but browser
  callback-watch runs were too perturbing/slow, so prefer cheap browser
  main-loop memory sampling first. Enable the watch/sample target with
  `XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS=0x0003a890` and cap it with
  `XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT` (for example `64`). Browser runs
  receive these through `xbe_memory_watch_phys.txt` and
  `xbe_memory_watch_limit.txt` in `/xemu-fixtures`. Intrusive callback watches
  are now filtered by `XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS=all|read|write`
  or `/xemu-fixtures/xbe_memory_watch_access.txt`; leave it unset/off for cheap
  sampling. Native `ACCESS=write` emits real callback markers. Browser
  `ACCESS=write` also emits callback markers after the mem-access callback path
  was enabled for `CONFIG_XEMU_BROWSER_BOOT`. The resulting
  `BOOT_MARK b6 memory-watch ...` markers include `access_filter`,
  identify read/write accesses, current pre-access value, CPU context, and
  stream-idle state for physical `0x0003a890`; they are diagnostic only and
  must not satisfy B6. The stable v2 browser artifact samples
  `0x00000000 -> 0x00002710` in write callbacks after the shared poll, while
  its shared poll still reads `0x00000000`. The current ready-edge plus
  host-fallback artifact improves the shared poll to `0x00002710`, but native
  still reads `0x0014c080`; both values are exact multiples of `0x2710`, so the
  current focused boundary reports native at 136 units, browser at 1 unit, and
  `shared_memory_poll_tick_delta=135`. Use the exact run commands in `goal.md`
  before adding more broad timer or PFIFO probes.
- New runs tag `main-loop=timers` with `source=main-loop-wait` for regular QEMU
  main-loop passes and `source=browser-headless-host-pump-bounded` for the
  browser headless host-side timer pass. The focused comparator reports
  `*_main_loop_timer_sources`; use that to tell whether browser host-side timer
  progress appears before adding deeper scheduler changes.
- Fresh browser-headless gate diagnostic, 2026-06-30: broad host-side timer
  pumping immediately after entry-ready is a bad path. The diagnostic
  `build-real-b3-matrix/browser-runtime-firefox-bidi-headless-gate-v1.log`
  proved the browser headless loop can see `entry_ready=yes`, but that early
  pump happens before PFIFO pusher-empty and can perturb the run while the timer
  observer filters the evidence. Current code gates the browser headless
  host pump through
  `xemu_xbe_boot_trace_main_loop_timer_pump_ready()`, using the same PFIFO-empty
  condition as the main-loop timer observer, and emits bounded
  `headless=timer-pump-gate ... entry_ready=... pump_ready=...` diagnostics.
  The corrected
  `build-real-b3-matrix/browser-runtime-firefox-bidi-headless-gate-v2.log` still
  times out with `pump_ready=no`, no PFIFO stream-idle, no `main-loop=timers`,
  and no `dashboard=xbe-executed`; keep it diagnostic-only and do not promote it
  over the frozen B5-pass browser baseline.
- Combined pre-transition plus after-empty browser-headless diagnostic,
  2026-06-30:
  `build-real-b3-matrix/browser-runtime-firefox-bidi-headless-pretransition-then-empty-filtered-limit4-v1-combined.log`
  uses
  `XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-before-transition-activity-then-after-pfifo-empty`,
  `XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4`, and no TCG timer
  pumping. It emits 8 `headless=timer-pump-step` markers for the before/after
  phases of the 4 bounded host pumps, reaches 4 browser main-loop
  timer-progress events, preserves browser-runtime read/load, entry-ready,
  section-map, PFIFO stream-idle, PIC ack, vector `0x30` service, and IRET
  evidence, and still fails B6 at `missing-xbe-executed-marker`. This is the
  preferred current focused browser diagnostic when present.
- Previous after-PFIFO-only browser-headless cap diagnostic, 2026-06-30:
  `build-real-b3-matrix/browser-runtime-firefox-bidi-headless-gate-bounded-no-tcg-limit4-v1-combined.log`
  uses `XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4`, keeps TCG timer
  pumping disabled, waits for PFIFO pusher-empty, and caps the browser headless
  host pump at the promoted native run's 4 timer-progress callbacks. It still
  times out and fails B6 at `missing-xbe-executed-marker`, but it removes the
  timer-progress count mismatch while preserving browser-runtime read/load,
  entry-ready, section-map, PFIFO stream-idle, PIC ack, vector `0x30` service,
  and IRET evidence. It is useful history, but the combined pre-transition plus
  after-empty artifact above supersedes it as the default focused diagnostic.
- Pre-transition host-pump negative probe, 2026-06-30:
  `build-real-b3-matrix/browser-runtime-firefox-bidi-headless-pretransition-activity-filtered-fastpoll-nosideeffect-limit4-v1-combined.log`
  uses `XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-before-transition-activity`,
  fast 2 ms post-entry host polling, TCG timer pumping disabled, and the cleaned
  sleep-interval path in `ui/xemu-headless.c` that no longer calls the
  side-effecting pump-readiness function before sleeping. It reaches
  browser-runtime read/load/entry-ready, section-map, and PFIFO stream-idle, but
  still times out and fails B6 at `missing-xbe-executed-marker`. The current
  boundary helper reports `browser_main_loop_timer_progress_events=0`,
  `post_idle_timer_divergence=browser-missing-main-loop-timer-progress`, and
  `next=restore-browser-main-loop-timer-progress` for this artifact. Do not
  promote this over the combined pre-transition plus after-empty diagnostic; use
  it as proof that a gate/readiness marker is not enough. Future pre-transition
  work must produce confirmed `headless=timer-pump-step` and `main-loop=timers`
  progress markers.
- Broad earlier-pump diagnostic, 2026-06-30:
  `build-real-b3-matrix/browser-runtime-firefox-bidi-headless-pump-limit4-anywhere-v1-combined.log`
  allows the same capped host timer-progress callbacks before PFIFO
  pusher-empty. It proves earlier host timer delivery can reach native-like
  IRQ/IRET frames such as `0x80014720`, but it regresses the command-stream
  boundary (`pfifo_transition=fail`,
  `post_idle_flow_divergence=command-stream-not-idle`) and still fails B6 at
  `missing-xbe-executed-marker`. Keep it diagnostic-only.
- Native detector acceptance, strict native dashboard execution, and native
  framebuffer reference are now proven by
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`.
  Normal native headless was missing the browser-headless-style
  `graphic_hw_update` pump; `XEMU_HEADLESS_BOOT_GRAPHIC_UPDATE=1` enables the
  opt-in native probe. The promoted artifact emits
  `dashboard=xbe-executed context=native-headless ... phys_match=yes
  section_index=3 section_flags=0x00000006` and
  `NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless
  source=native-framebuffer
  hash=2aa899fb497643b12c4bae3a089d3dc98b2077ea18a075fbf38f10e266841b78
  width=640 height=480 dashboard=xbe-executed`.
  Do not go back to native detector-proof work unless fresh evidence regresses
  this artifact.
- The focused native actual-execution helper is
  `scripts/xbox-native-actual-xbe-execution-check.py
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`. The
  current expected result is
  `NATIVE_ACTUAL_XBE_EXECUTION result=pass reason=strict-dashboard-executed`,
  with `strict_xbe_executed=yes`, `direct_entry_pc=yes`, and first strict marker
  at the dashboard entry `0x00017d60`.
- The focused native headless handoff helper is
  `scripts/xbox-native-headless-handoff-check.py
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`. The current
  expected result is
  `NATIVE_HEADLESS_HANDOFF result=pass
  terminal_state=dashboard-executed-with-native-reference
  actual_xbe_executed=yes native_reference=pass`, with
  `latest_stream_idle_eip=0x80045c92`,
  `latest_stream_idle_cpu_interrupt_request=0x00000000`,
  `after_idle_top_edge=0x80030e84->0x80030f31`, and
  `after_idle_cpu_interrupt_nonzero=6`. This satisfies the native side of the
  B6 contract but not browser B6.
- `scripts/xbox-boot-smoke.sh` accepts `XEMU_SMOKE_SKIP_BOOT_ANIM=1` to write
  `skip_boot_anim = true` and launch native QEMU with `short-animation=on`.
  The targeted artifact
  `build-real-b3-matrix/native-skip-boot-anim-xbe-detector-proof-v1/boot-smoke.log`
  is negative evidence: short animation is active, detector proof still passes,
  but `scripts/xbox-native-actual-xbe-execution-check.py` still reports
  `result=fail reason=no-strict-dashboard-executed-marker`,
  `exec_probe_phys_match_yes=0`, and `direct_entry_pc=no`. Do not repeat this
  run as the next step unless native/headless behavior changes. The handoff
  helper comparison reports the default and short-animation logs both end in
  `native-headless-timeout-after-stream-idle` with
  `either_actual_xbe_executed=no`.
- Treat browser-only TCG timer pumps and PFIFO pre-commit pumps as probes, not
  the final architecture. The target is browser timer/main-loop behavior that
  converges toward native semantics; specifically, converge browser
  post-service CPU flow after the controlled host pump without broad timer
  pumping before PFIFO pusher-empty, instead of leaning harder on diagnostic
  TCG timer pumps. The fresh pre-commit probe confirms that PFIFO pre-commit
  PIT delivery is a negative path for the current boundary because it removes
  browser main-loop timer progress and falls back to the older `0x8001b030`
  loop.
- Keep `XEMU_BROWSER_DASHBOARD_CAPTURE_REQUIRE_EXECUTED=1`; final
  browser-vs-native visual comparison should wait until true browser-runtime
  `dashboard=xbe-executed` exists.

Historical first implementation slice, now completed. Do not use this as the
current B6 next step:

1. Add gated boot markers and a controlled timeout/instruction budget.
2. Add a native headless/null boot harness.
3. Remove accidental SDL dependency from `hw/xbox/nv2a/pgraph/null/meson.build`.
4. Add a boot smoke script that extracts B0/B1/B2/B3 from logs.
5. Start the reduced wasm build profile only after native headless evidence exists.

Implementation constraints:

- Keep proprietary Xbox assets local and untracked.
- Standard local fixture directories are `fixtures/` and `xemu-fixtures/`; the real B3 runner auto-discovers `flash.bin`, `xbox_hdd.img`, optional `mcpx.bin`, optional `eeprom.bin`, and optional `dvd.iso` there, or from `XEMU_REAL_B3_FIXTURE_DIR`.
- Validate required flash and HDD fixture files as present and non-empty before real B3 runs.
- Validate MCPX boot ROM size as 512 bytes when used.
- Validate EEPROM size as 256 bytes.
- The first wasm target should be `i386-softmmu` with `--enable-tcg-interpreter`.
- Use the null renderer first.
- Keep audio and networking disabled for the initial browser boot path.
- Avoid desktop UI, SDL, OpenGL, Vulkan, ImGui, ImPlot, libpcap, and libsamplerate dependencies in the reduced wasm boot target.
- Browser pthread runs require a cross-origin-isolated context with COOP/COEP headers and `SharedArrayBuffer`.

Browser automation/tooling:

- Preferred browser automation is Playwright when available.
- This machine has Playwright installed globally under `$HOME/.npm-global/lib/node_modules`; set `NODE_PATH="$(npm root -g)"` before Node-based browser tests so `require("playwright")` resolves it.
- A quick local Playwright sanity check is `export NODE_PATH="$(npm root -g)"` and then `node -e 'require("playwright"); console.log("playwright ok")'`.
- Verified on this machine on 2026-06-28 with the unattended env prefix below: Node `v22.22.2`, npm `10.9.7`, global Playwright `1.61.1`, and Playwright browser binaries under `$HOME/.cache/ms-playwright`.
- If Playwright or npm globals were installed during an already-open shell, refresh command lookup and paths before rerunning browser tests: `hash -r; export PATH="$HOME/.npm-global/bin:$PATH"; export NODE_PATH="$(npm root -g)"`. If the npm-global PATH setup lives in a shell startup file, `source ~/.profile` or open a fresh shell first.
- For unattended commands, prefer explicit environment prefixes instead of relying on shell startup files: `PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin NODE_PATH=$HOME/.npm-global/lib/node_modules <command>`.
- Browser wasm C-side `getenv()` does not reliably see host `XEMU_BOOT_TRACE_*` env overrides from the smoke command. For C-side browser diagnostics, use browser-specific compiled defaults or add explicit JS-to-wasm env plumbing before assuming a host env limit took effect.
- Browser runtime smokes can select the Playwright engine with `XEMU_BROWSER_RUNTIME_BROWSER=chromium` or `XEMU_BROWSER_RUNTIME_BROWSER=firefox`; `XEMU_BROWSER_RUNTIME_CHANNEL` only applies to Chromium.
- Keep Firefox BiDi scripts as the fallback path when Playwright is absent or Playwright progress lags the BiDi evidence. Direct Firefox BiDi fallback scripts do not need the Playwright module; when isolating that path, it is acceptable to run with `NODE_PATH=`. For current long real browser-runtime probes, prefer the explicit real-matrix driver `XEMU_REAL_B3_BROWSER_RUNTIME_DRIVER=firefox-bidi` until Playwright reaches comparable IDE-read/B4 evidence.
- Current verified local browser stack, checked on 2026-06-28: Node v22.22.2, npm 10.9.7, global Playwright 1.61.1 under `$HOME/.npm-global/lib/node_modules`, installed Playwright browser binaries, Firefox 140.11.0esr, Python 3.12.13, `qemu-img` 10.1.0, and Podman 5.8.2 through `/tmp/xemu-podman-wrapper/docker`.
- If a verifier reports `docker: command not found`, prepend the local wrapper directory before rerunning: `export PATH="/tmp/xemu-podman-wrapper:$PATH"`.
- For long-running unattended work, prefer commands that produce clear artifact/log output and do not depend on shell startup files. Logs should include enough `BOOT_MARK`/`BROWSER_*` evidence to decide pass/fail without manual visual inspection.
- Current local real fixture exports for this machine:
  - `XEMU_MCPX='/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin'`
  - `XEMU_FLASH='/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin'`
  - `XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin` for isolated B6 smoke runs; the user-supplied source EEPROM is `/home/sammy/.local/share/xemu/xemu/eeprom.bin`
  - `XEMU_HDD='/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2'`
- Historical browser-runtime stall: Playwright Firefox passed selected-assets browser runtime smoke but only reached browser-block B3 within 60 seconds, and earlier Firefox BiDi probes reached B4 plus only the first IDE read at `read_lba=3`. Native then immediately continued to FATX at `read_lba=4609024` and `xboxdash.xbe` at `read_lba=4609192`, proving the browser stall was in the post-read AIO/DMA completion path.
- Current browser-runtime storage status: the first-read AIO stall is fixed by polling the current AIO context after IDE stores the returned DMA AIOCB. Firefox BiDi now reaches browser-runtime dashboard storage reads, and the standard real matrix log contains `BOOT_MARK b6 dashboard=xbe-read context=browser-runtime ...` for `xboxdash.xbe`.
- Current B6 B5-pass baseline: the preferred Firefox BiDi browser artifact for
  B5/runtime-stable dashboard-read evidence is
  `build-real-b3-matrix/browser-runtime-firefox-bidi-section-map-v2-combined.log`.
  It uses the rebuilt wasm with XBE section-map diagnostics and appended
  FATX/IDE dashboard-read proof. It passes B5 runtime evidence, passes B4 display
  capture, proves browser-runtime `xboxdash.xbe` read plus
  `dashboard=xbe-loaded source=virtual-header`, proves
  `dashboard=xbe-entry-probe status=ready`, emits
  `dashboard=xbe-section-map phase=entry-ready`, and maps executable entry
  section 3 from entry `0x00017d60` to `entry_phys=0x000c7d60`. It also matches
  the native preferred vector `0x30` service/IRET frame. It still correctly fails
  the B6 checker at `missing-xbe-executed-marker`; there is no accepted
  browser-runtime `dashboard=xbe-executed` and no browser/native visual match
  yet. The raw C read-progress count (`172032`) is the FATX file size for
  `xboxdash.xbe`; the header `image_size=175080` is the in-memory XBE image
  size, not a missing disk-read count. The promoted native execution/reference
  artifact is
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`; keep
  `build-real-b3-matrix/native-post-iret-flow-v1/boot-smoke.log` as a historical
  IRET comparator reference. Do not loop on another generic timer-pump/browser
  rerun unless fresh evidence changes the current boundary.
- Historical B6 memory-sample diagnostic:
  `build-real-b3-matrix/browser-memory-sample-0x3a890-full-baseline-v1-combined.log`
  preserves the full focused baseline while adding cheap memory samples for
  physical `0x0003a890`. It is superseded first by the write-watch v2 artifact
  and then by the ready-edge plus host-fallback artifact named near the top of
  this file. Keep it as history for the zero-tick shared-poll boundary, not as
  the current front-most browser diagnostic.
- Current B6 section-map diagnostic: validate the active boundary with
  `scripts/xbox-dashboard-section-map-evidence-check.sh build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`.
  The older B5-pass baseline can still be validated with
  `scripts/xbox-dashboard-section-map-evidence-check.sh build-real-b3-matrix/browser-runtime-firefox-bidi-section-map-v2-combined.log`.
  The expected current result is
  `DASHBOARD_SECTION_MAP_EVIDENCE result=pass ... phase=entry-ready ... executable_sections=1 entry_section=3 mapped_entry_rows=1`.
  This marker is metadata-only and diagnostic-only: it explains the dashboard XBE
  section ranges and physical mappings, but it must not satisfy B6 without
  browser-runtime `dashboard=xbe-executed` and native/browser dashboard
  visual-match evidence.
- `dashboard=xbe-executed` is intentionally strict: the marker and
  `scripts/xbox-dashboard-loaded-evidence-check.sh` require `phys_match=yes` and
  an executable XBE section (`section_flags` containing `0x4`) so headers, data,
  or high-alias physical mismatches cannot satisfy B6.
- The older v5 combined artifact
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pit-after-idle-full-post-iret-v5-combined.log`
  is still useful read/load/entry-ready evidence, but it has no browser PFIFO
  stream-idle. The older
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pit-after-idle-full-pump-v1.log`
  reaches PFIFO-empty and matches the preferred IRET frame, but it timed out at
  the outer runtime harness and lacks the combined FATX read proof. The
  section-map v2 combined artifact supersedes both as the B5-pass dashboard-read
  baseline, while the ready-edge plus host-fallback artifact near the top of
  this file is the current front-most B6 browser diagnostic.
- The callback-v1 browser artifact is diagnostic-only because its runtime smoke ends with `BROWSER_RUNTIME_SMOKE result=fail reason=runtime-timeout`; keep `build-real-b3-matrix/browser-runtime-firefox-bidi-irq-source-v6-combined.log` for older source-attribution comparisons, but prefer the section-map v2 combined artifact above for current B5-pass B6 work. Older hard-IRQ-service, timer-pump, PCRTC-vblank, IRET-frame, PIC-ack, IRQ-route, command-window, `native-120s-irq-watch-route-v1`, v4 browser, and v2 native artifacts remain historical IRQ, timer, PCRTC, IRET, and PFIFO/PGRAPH baselines.
- The current callback-v1 artifact contains B4 display capture, browser-runtime `xboxdash.xbe` read correlation, entry-ready evidence, PCRTC vblank-off evidence, `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=idle-loop-serviceable`, `XEMU_BOOT_TRACE_XBE_IRQ_WATCH=6,12`, post-PFIFO CPU hard-IRQ evidence from the native-observed serviceable idle PC `0x8001b030`, and `cpu=hard-irq-service` evidence showing vector `0x30` delivered to handler PC `0x80030e4c`. It removes the earlier first-IRQ-at-`0x8001b02f` boundary and sharpens the remaining divergence: browser-only IRQ12 is sourced by ACPI PM timer callback plus PM SCI routing, and browser-only IRQ6 is sourced by AC97 playback callback and BM index 1 through the MCPX ACI route, both asserted at `eip=0x8001b030` after PFIFO reaches pusher-empty.
- The source-comparable native v3 run uses the same PM SCI/AC97 source hooks and timer-pump settings, and records no matching PM timer callback, PM event write, PM SCI assertion, AC97 callback, AC97 bus-master write, AC97 transfer, or AC97 IRQ assertion. The latest comparator reports browser-only `browser_pm_timer_events=1`, `browser_ac97_callback_events=9`, `browser_pm_sci_events=2`, `browser_ac97_transfer_events=1`, and `browser_extra_pic_ack_vectors=0x3c,0x36`, with no native counterparts. The combined browser log still fails `scripts/xbox-dashboard-loaded-evidence-check.sh` at `missing-xbe-executed-marker`, which is the correct next boundary. Do not go back to treating `missing-dashboard-read-overlap`, `missing-xbe-loaded-marker`, PGRAPH notify-clear waiting, PFIFO/PGRAPH command progress, PCRTC cadence alone, timer/IRQ activity alone, interrupt delivery alone, interrupt-return parity alone, or non-empty B4 display as the active blocker unless fresh evidence regresses.
- Current post-IRET update: with the promoted native baseline and current
  ready-edge plus host-fallback browser diagnostic,
  `scripts/xbox-b6-current-boundary.sh`
  reports `b6_reason=missing-xbe-executed-marker`,
  `browser_main_loop_timer_progress_events=4`,
  `post_idle_timer_divergence=none`,
  `browser_tcg_timer_progress_events=0`,
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
  `headless_pump_divergence=pump-before-stream-idle-boundary`,
  `headless_pump_timer_before_boundary=yes`,
  `headless_pump_timer_after_boundary=no`,
  `post_idle_flow_divergence=missing-interrupt-service`,
  `pfifo_transition_divergence=post-transition-hard-irq-set-mismatch`, and
  `next=converge-browser-post-service-flow` for
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
  versus
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`.
  Browser interrupt delivery is no longer missing in this diagnostic, and the
  timer-progress count now matches native: it reaches PIC ack, vector `0x30`
  service, and IRET. The remaining slice is why the browser falls into
  `0x8001b02f->0x8001b030` and `0x80031ffa` memory-poll paths while promoted
  native continues toward strict dashboard execution. The sharpest clue is the
  shared post-service memory read at guest virtual `0x8003a890` / physical
  `0x0003a890`: native reads a nonzero pointer-like value, while browser reads
  `0x00002710` in the ready-edge plus host-fallback probe. These values are
  exact multiples of `0x2710`: native has 136 units, browser has 1, so browser
  is 135 units behind at the shared poll. The limit136 probe
  `build-real-b3-matrix/browser-memory-sample-0x3a890-limit136-v1-combined.log`
  proves raising the browser host-pump progress limit to 136 does not fix B6:
  the shared poll still sees browser at 0 units, the later browser timer-watch
  maximum reaches only 65 units, and `dashboard=xbe-executed` remains absent.
  The separate broad earlier-pump artifact
  `build-real-b3-matrix/browser-runtime-firefox-bidi-headless-pump-limit4-anywhere-v1-combined.log`
  proves earlier timer delivery can reach native-like IRQ frames, but it
  regresses command-stream idle and is diagnostic-only. The older
  `build-real-b3-matrix/native-post-iret-flow-v1/boot-smoke.log` comparison
  remains historical evidence that one browser artifact matched an earlier
  vector `0x30` service/IRET frame, but that native artifact did not prove
  actual dashboard execution. The next B6 slice is browser pre-service tick
  accumulation before the first watched `0x0003a890` read, then post-service
  flow convergence toward the promoted native execution/reference path, not
  B3/B4/B5, PFIFO/PGRAPH command progress, PM/AC97 attribution, native detector
  proof, or another generic timer-pump run. If using the pre-transition activity host-pump
  mode, require confirmed `headless=timer-pump-step` plus `main-loop=timers`
  markers; a `headless=timer-pump-gate` or readiness log alone is diagnostic
  noise. The v4 browser run
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pit-after-idle-full-post-iret-v4.log`
  is negative evidence because it passes runtime evidence but misses PFIFO
  stream-idle and re-samples earlier PGRAPH wait state.
- Current browser trace-control correction: the after-idle kernel-loop sample
  budget and the browser PIT-pump after-idle gate are separate controls. Use
  `XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT` only for sample/logging
  budget and `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT` for the
  `idle-loop-serviceable-pit-after-idle-full` pump gate. Do not raise the
  sample budget and assume the pump still fires after the old threshold unless
  the pump gate is set explicitly.
- Current B6 entry-point diagnostic: `dashboard=xbe-entry-probe` is diagnostic only and must not satisfy `dashboard=xbe-executed`. The latest native artifact, `build-real-b3-matrix/native-60s-xbe-entry-probe-v2/boot-smoke.log`, and browser artifact, `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-entry-probe-combined.log`, both show decoded dashboard entry `0x00017d60` first unreadable, then `status=ready` with `entry_phys=0x000c7d60`, `entry_code_hash=0x7cbb4e8a328f1553`, and `entry_opcode=0x55`. The browser artifact also passes B4 display capture, B5 runtime evidence, and browser-runtime `xboxdash.xbe` read correlation, but it still fails `scripts/xbox-dashboard-loaded-evidence-check.sh` at `missing-xbe-executed-marker`.
- Current B6 entry-target diagnostic: `dashboard=xbe-entry-target-probe` is diagnostic only and must not satisfy `dashboard=xbe-executed`. The latest native artifact, `build-real-b3-matrix/native-60s-xbe-entry-target-probe/boot-smoke.log`, and browser artifact, `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-entry-target-probe-combined.log`, both emit 16 bounded probes for decoded branch targets within the entry window. The sampled near-entry targets are still kernel/high-alias paths with `target_status=near-phys-unknown`, including targets near `0x8001ae75`, `0x80018d30`, and `0x800241fe`; the browser artifact passes B4/B5 and `xboxdash.xbe` read correlation, but still fails the B6 checker at `missing-xbe-executed-marker`.
- Current B6 dispatch diagnostic: `dashboard=xbe-dispatch-probe` is diagnostic only and must not satisfy `dashboard=xbe-executed`. It is controlled by `XEMU_BOOT_TRACE_XBE_DISPATCH_LIMIT` and summarizes registers plus the top 16 stack words without dumping proprietary stack contents. The latest native artifact, `build-real-b3-matrix/native-60s-xbe-dispatch-probe-v3/boot-smoke.log`, emits 16 probes; the latest browser artifact, `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-dispatch-probe-v3-combined.log`, emits 10 probes. Browser and native both show no register physical match and no register entry-near candidate. Direct stack candidates, when present, are inside XBE headers (`stack_first_in_headers=yes`), while other stack candidates are high-alias mismatches or unknown physical mappings near kernel paths. No `dashboard=xbe-executed` marker appears.
- B6 kernel-loop/NV2A/PFIFO/PGRAPH diagnostic markers:
  `dashboard=kernel-loop-probe`, `BOOT_MARK b6 nv2a=pmc-access ...`,
  `BOOT_MARK b6 nv2a=irq-source ...`, `BOOT_MARK b6 nv2a=irq-line ...`,
  `BOOT_MARK b6 pfifo=progress ...`, `BOOT_MARK b6 pfifo=window ...`,
  `BOOT_MARK b6 pgraph=method ...`, `BOOT_MARK b6 pgraph=method-window ...`,
  `BOOT_MARK b6 pgraph=notify-error ...`, `BOOT_MARK b6 pgraph=notify-clear ...`,
  `BOOT_MARK b6 tcg=timer-pump ...`, `BOOT_MARK b6 cpu=hard-irq-service ...`,
  `BOOT_MARK b6 cpu=iret ...`, and the `nv2a_wait_*` fields on kernel-loop
  probes are diagnostic only and must not satisfy `dashboard=xbe-executed`.
  Kernel-loop probes are controlled by `XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT`
  and `XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_MIN_HITS`; browser TCG timer pumping is
  controlled by `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL` and
  `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE`; hard-IRQ service probes are
  controlled by `XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT`; IRET probes are
  controlled by `XEMU_BOOT_TRACE_XBE_IRET_LIMIT`; PMC/IRQ/PFIFO/PGRAPH probes
  retain their existing `XEMU_BOOT_TRACE_NV2A_*` limits. The null-renderer
  flip-stall mismatch is fixed, and the command-window artifacts remain the
  PFIFO/PGRAPH progress baseline: native and browser both continue past
  `NV097_FLIP_STALL`, consume the late command window through
  `NV097_SET_COLOR_CLEAR_VALUE`, and reach PFIFO empty with
  `dma_get=dma_put=0x03881318` and `waiting_flip=no`. Older idle-loop timer-pump
  artifacts proved browser post-PFIFO PIT/PIC/CPU hard-IRQ markers, vector
  `0x30`, handler PC `0x80030e4c`, and an earlier matching IRET frame, but the
  active boundary is now the ready-edge plus host-fallback pre-service tick gap
  before the first watched read. No diagnostic in this family emits acceptable
  browser-runtime `dashboard=xbe-executed`.
- Browser-only PCRTC vblank cadence can be changed for diagnostics with `XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=normal|off|suppress-until-dashboard-observed|suppress-until-entry-ready`. The browser page/worker path writes the selected mode into `/xemu-fixtures/pcrtc_vblank_mode.txt` so C-side wasm diagnostics do not rely only on host `getenv()` propagation. Non-normal runs emit sampled `BOOT_MARK b6 nv2a=pcrtc-vblank-gate ...` markers and remain diagnostic only; they must not satisfy B6 without true `dashboard=xbe-executed context=browser-runtime` plus native-reference visual match evidence.
- Browser-only QEMU virtual-time diagnostics can be enabled with `XEMU_BROWSER_BOOT_ICOUNT=<qemu-icount-value>`; the browser page logs `BROWSER_DIAGNOSTIC name=browser_icount ...`, the worker appends `-icount <value>` to the wasm QEMU argv, and the transcript logs `BROWSER_DIAGNOSTIC_APPLY name=browser_icount ... target=argv:-icount`. This is diagnostic-only and must not become the default browser boot path without fresh evidence. The latest probes are `build-real-b3-matrix/browser-runtime-firefox-bidi-icount-shift10-v1.log` and `build-real-b3-matrix/browser-runtime-firefox-bidi-icount-shift0-v1.log`. `shift=10,sleep=off` still timed out, reached entry-ready, and produced heavy AC97 playback callback activity. `shift=0,sleep=off` timed out after B4 display captures, `dashboard=xbe-loaded`, entry-ready evidence, no PM timer callback, and only one AC97 playback callback; it still failed the B6 checker at `missing-xbe-read-marker` and never emitted `dashboard=xbe-executed`. The useful conclusion is that lower virtual time can reduce the PM/AC97 timing divergence, but it does not by itself produce dashboard execution.
- Browser dashboard visual comparison is gated with `XEMU_BROWSER_DASHBOARD_NATIVE_HASH=<native-frame-hash>` in `scripts/xbox-browser-runtime-smoke.sh`. Both the Playwright path and Firefox BiDi fallback emit `BROWSER_DASHBOARD_CAPTURE` from the latest non-empty browser display capture only when a native hash is supplied; by default `XEMU_BROWSER_DASHBOARD_CAPTURE_REQUIRE_EXECUTED=1` makes the runtime emit `result=skip reason=missing-xbe-executed` until real browser-runtime `dashboard=xbe-executed` exists. Final B6 evidence must also include `NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless ... dashboard=xbe-executed ...`, validated with `scripts/xbox-native-reference-evidence-check.sh <log>`, and the browser capture `native_hash` must match that native reference hash. This wiring prepares the final B6 visual comparison without allowing B4-only non-empty scanout to pass.
- Latest post-idle interrupt-flow diagnostic: `build-real-b3-matrix/browser-runtime-firefox-bidi-pm-ac97-callback-v1-combined.log` ran with `XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=off`, `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=1`, `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=idle-loop-serviceable`, `XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1`, `XEMU_BOOT_TRACE_XBE_IRQ_WATCH=6,12`, source-level PM SCI/AC97 probes, PM timer callback probes, PM event-write probes, AC97 playback callback probes, AC97 bus-master write probes, AC97 descriptor-transfer probes, and expanded PIC/hard-IRQ/IRET limits. The native comparison run is `build-real-b3-matrix/native-120s-irq-source-v3/boot-smoke.log`.
- Callback-v1 keeps B4 display capture and proves browser-runtime `xboxdash.xbe` read/load plus entry-ready evidence, but it times out before a passing B5 runtime result. The service markers still show vector `0x30` accepted and handler PC `0x80030e4c` after delivery in both native and browser, and the IRET comparator reports matching service frame hashes and return state.
- The preferred post-idle comparator now reports the remaining browser-only source divergence: `browser_pm_timer_events=1`, `browser_first_pm_timer=pm-timer:callback:ticks=22991275:overflow=16777216:sts=0x0000->0x0000:en=0x0001:masked=0x0000:eip=0x8001b030`, `browser_ac97_callback_events=9`, `browser_first_ac97_callback=ac97-callback:po:bm=1:free=4460:sr=0x0000:cr=0x1d:civ=0:lvi=0:picb=4096:bd=0x03fdd000/0xc0001000:eip=0x8001b030`, `browser_pm_sci_events=2`, `browser_first_pm_sci_assert=pm:pm1-update:assert`, `browser_ac97_transfer_events=1`, and `browser_extra_pic_ack_vectors=0x3c,0x36`. IRQ12 is ACPI PM SCI routed to PIC IRQ12 and IRQ6 is AC97/MCPX ACI routed to PIC IRQ6; the source-comparable native run records no matching PM timer callback, AC97 playback callback, LPC route, PIC line assertion, PM SCI assertion, PM event write, AC97 BM write, AC97 transfer, or AC97 IRQ assertion. The B6 checker still fails at `missing-xbe-executed-marker`. The v6 source probe remains the latest B5-pass source-comparable browser artifact; older PIC-ack, idle-loop timer-pump, hard-IRQ-service, PCRTC-off, original IRET-frame, IRQ-route, route-v1, v4/v2 source probe, and suppress-until-entry artifacts remain useful historical baselines, but they are no longer the preferred local B6 diagnostic baseline.
- Historical timer-pump attribution diagnostic: `build-real-b3-matrix/browser-runtime-firefox-bidi-timer-pump-attribution-v2.log` is diagnostic-only because it times out and lacks full combined B6 read evidence, but the comparator proves the browser-only PM/AC97 source events fire inside the browser TCG-side virtual timer pump: `browser_pm_timer_pump_active_events=1`, `browser_ac97_callback_pump_active_events=9`, `browser_ac97_transfer_pump_active_events=1`, and `browser_ac97_irq_pump_active_events=1`. Cleanup writes are pump-inactive: `browser_pm_evt_write_pump_active_events=0` and `browser_ac97_bm_write_pump_active_events=0`. This is useful background for why browser-only pump modes are risky, but it is superseded by `goal.md` as active guidance. Do not treat PM/AC97 timer-pump filtering as the current front-most B6 target unless fresh evidence regresses the baseline.
- Historical idle-before-PFIFO diagnostic: `BOOT_MARK b6 cpu=idle-before-pfifo-transition ...` is diagnostic only and must not satisfy `dashboard=xbe-executed`. It is controlled by `XEMU_BOOT_TRACE_XBE_IDLE_BEFORE_PFIFO_TRANSITION_LIMIT` and summarized with `scripts/xbox-idle-before-pfifo-transition-compare.py --native-log <native.log> --browser-log <browser.log>`. The focused artifacts were `build-real-b3-matrix/native-pfifo-activity-v1/boot-smoke.log` and `build-real-b3-matrix/browser-runtime-firefox-bidi-pfifo-activity-v1.log`; the comparator reported `divergence=idle-before-transition-mismatch` with both markers present. Native and browser both reached the same idle edge, `0x8001b02e -> 0x8001b02f`, while PFIFO still had `dma_get=0x0388130c`, `dma_put=0x03881318`, and 12 bytes left. The diagnostic PFIFO activity snapshot also aligned on `pfifo_activity_phase=puller-method-pgraph-return`, `pfifo_activity_pfifo_lock_released=yes`, `pfifo_activity_pgraph_locked=yes`, and `pfifo_activity_final_transition_candidate=no`. Keep this as historical context only. The active slice is now the `goal.md` pre-service tick accumulation window before the first watched read, after the native-matching vector `0x30` service/IRET frame.
- Current B6 alias/hash diagnostic: `dashboard=xbe-alias-compare` and `dashboard=xbe-entry-target-probe` target hashes are diagnostic only and must not satisfy `dashboard=xbe-executed`. The alias guard is controlled by `XEMU_BOOT_TRACE_XBE_ALIAS_COMPARE_LIMIT` and hashes, without dumping raw bytes, the executing high-alias code and the corresponding low dashboard XBE image bytes for high-bit PCs that numerically overlap the XBE virtual range. Entry-target probes now also hash decoded branch target bytes and corresponding low XBE image bytes as `target_code_hash` and `target_image_code_hash`. Use `scripts/xbox-dashboard-xbe-hash-evidence.py --hdd <hdd> --log <log> --require-context browser-runtime` to aggregate those samples and compare them to the dashboard XBE file hashes without dumping proprietary bytes. The helper also audits sampled `dashboard=xbe-exec-probe`, `dashboard=xbe-exec-transition`, `dashboard=xbe-exec-edge`, and decoded entry-target hashes against the dashboard file. The latest callback-v1 artifact reports `DASHBOARD_XBE_HASH_EVIDENCE result=pass ... samples=32 comparable=32 guest_image_hash_match=0 guest_disk_hash_match=0 image_disk_hash_match=2 exec_samples=80 exec_comparable=74 exec_disk_hash_match=0 ...`; the fresh target-hash artifact `build-real-b3-matrix/browser-runtime-firefox-bidi-target-hash-v1.log` reports `target_samples=16 target_comparable=16 target_disk_hash_match=0 target_image_disk_hash_match=0`. This rules out the sampled high-alias, sampled execution, and sampled decoded entry-target paths as dashboard bytes executed through a different alias.

Verification expectations:

- Every browser-boot task should have concrete pass/fail evidence.
- Use `scripts/xbox-browser-boot-verify-synthetic.sh` as the preferred no-private-assets regression gate before real fixture B3 work.
- Use `scripts/xbox-boot-next-step.sh` to get the current machine-readable next command from evidence. If it points back to the known failing B6 checker, immediately pair it with `scripts/xbox-b6-current-boundary.sh` and the loop guard in `goal.md` before starting another run.
- Use `scripts/xbox-fixture-privacy-check.sh` to verify standard private fixture paths are ignored and known fixture files are not tracked.
- Use `scripts/xbox-real-fixtures-ready.sh` for a non-emulating readiness report before preflight; set `XEMU_REAL_FIXTURE_READY_REQUIRE=1` when a missing or invalid fixture should fail the command.
- Use `scripts/xbox-real-fixture-manifest.sh` to generate a no-emulation handoff artifact with readiness and git privacy evidence before running real B3.
- Use `XEMU_REAL_FIXTURE_IGNORE_REPO_DIRS=1 scripts/xbox-real-fixtures-ready.sh` only for isolated negative tests that must ignore repo-local `fixtures/` and `xemu-fixtures/` directories.
- Use `XEMU_REAL_B3_PREFLIGHT_ONLY=1 scripts/xbox-real-b3-matrix.sh` to validate real fixture discovery/sizes before running the full real B3 matrix. The matrix writes `build-real-b3-matrix/real-fixture-manifest.log`, `build-real-b3-matrix/real-fixture-manifest/real-fixture-manifest.md`, and `build-real-b3-matrix/real-fixture-ready.log`; evidence summary and next-step helpers use real B3 outputs when present.
- A full real B3 pass must include native/wasm marker comparison, real browser-block reads, and the browser selected-assets runtime smoke with a B3 marker plus config persistence evidence.
- Use `scripts/xbox-real-b3-evidence-check.sh <log>` to validate real B3 matrix evidence format.
- B4 is not proven by a marker alone; require a B4 marker plus `BROWSER_DISPLAY_CAPTURE result=pass ... nonempty=yes ...`.
- Use `scripts/xbox-display-capture-evidence-check.sh <log>` to validate B4 display capture evidence format.
- B5 is not proven by page load alone; require real selected-assets browser smoke with capabilities, artifacts, asset validation, config persistence, and B3 evidence.
- Use `scripts/xbox-browser-runtime-evidence-check.sh <log>` to validate B5 real browser runtime evidence format.
- Use `scripts/xbox-boot-completion-audit.sh` as the final diagnostic completion gate; it must fail until synthetic prerequisites and real B3/B4/B5/B6 evidence all pass.
- For B6 dashboard-loaded work, do not rely on visual impression alone. Add explicit dashboard evidence such as FATX/XBE reads, XBE header/code load, execution into the dashboard XBE region, and browser-vs-native reference frame comparison.
- B6 visual comparison should use Playwright screenshots or canvas pixel capture when available, with Firefox BiDi as a fallback.
- Use `scripts/xbox-native-reference-evidence-check.sh <log>` to validate native reference-frame provenance for B6. It must require `NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless ... dashboard=xbe-executed ...`; this line is necessary for final visual comparison but does not satisfy B6 by itself.
- Use `scripts/xbox-dashboard-loaded-evidence-check.sh <log>` to validate B6 dashboard-loaded evidence format. It must require `context=browser-runtime` XBE read/load/entry-ready/execute markers, `source=virtual-header` on `dashboard=xbe-loaded`, `dashboard=xbe-entry-probe status=ready entry_code_read=yes phys_match=yes`, `NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless ... dashboard=xbe-executed ...`, and `BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes` whose `native_hash` matches the native reference hash; a B4 non-empty frame, a physical-scan diagnostic, entry readiness alone, or native-only dashboard progress is not enough.
- Use `scripts/xbox-dashboard-loaded-evidence-check-selftest.sh` when changing the B6 evidence contract. The no-private-assets synthetic verifier also runs this selftest.
- Use `scripts/xbox-dashboard-xbe-hash-evidence-selftest.sh` when changing the B6 alias/execution hash audit helper. The helper is diagnostic only; it must not make B6 pass without `dashboard=xbe-executed` and `BROWSER_DASHBOARD_CAPTURE native_ref_match=yes`.
- Use `scripts/xbox-post-idle-interrupt-flow-compare.py --native-log <native.log> --browser-log <browser.log>` to summarize the current post-PFIFO-idle CPU-flow boundary. It compares service vectors, IRET returns, and first post-service loop edges, but it is diagnostic only and must not satisfy B6 without real browser-runtime `dashboard=xbe-executed` plus native-frame visual match evidence.
- Use `scripts/xbox-post-service-memory-poll-compare.py --native-log <native.log> --browser-log <browser.log>` to summarize the current post-service memory-poll boundary. It compares focused post-stream-idle/post-IRET kernel-loop samples and reports shared memory-read value mismatches such as the current ready-edge host4 split: `0x8003a890` native `0x0014c080` versus browser `0x00002710`. It also normalizes exact `0x2710` multiples into tick fields; the current promoted comparison reports native 136, browser 1, delta 135, relation `browser-behind`. It is diagnostic only and must not satisfy B6 without real browser-runtime `dashboard=xbe-executed` plus native-frame visual match evidence.
- Use `scripts/xbox-post-service-watch-edge-compare.py --native-log <native.log> --browser-log <browser.log>` to summarize the watched-word values around the post-service `0x80030e84 -> 0x80030f31` block. The current promoted comparison reports `block_delta_match=yes`, with native 136->137 ticks and browser 0->1 ticks. It is diagnostic only and must not satisfy B6 without real browser-runtime `dashboard=xbe-executed` plus native-frame visual match evidence.
- Use `scripts/xbox-pre-service-tick-gap-compare.py --native-log <native.log> --browser-log <browser.log>` to summarize the first watched read after PFIFO stream-idle relative to timer progress, first watched write, hard-IRQ service, and IRET. The current promoted comparison reports `divergence=browser-first-watch-read-before-catchup`, with native first read at 136 tick units and browser first read at 0. It is diagnostic only and must not satisfy B6 without real browser-runtime `dashboard=xbe-executed` plus native-frame visual match evidence.
- Use `scripts/xbox-headless-pump-placement-compare.py --browser-log <browser.log>` to summarize browser headless host-pump placement around the PFIFO stream-idle boundary. The stable v2 comparison reports `host_ready_before_boundary=yes`, `timer_before_boundary=no`, and `timer_after_boundary=yes`; the current ready-edge host4 comparison reports `timer_before_boundary=yes`, `timer_after_boundary=no`, `first_timer_watch_zero=yes`, and `first_memory_write_zero=yes`. It is diagnostic only and must not satisfy B6 without real browser-runtime `dashboard=xbe-executed` plus native-frame visual match evidence.
- `BOOT_MARK b6 memory-watch ...` is a producer/order diagnostic for the current
  `0x8003a890` / `0x0003a890` split only. It records access type and CPU context
  for a watched low-RAM word, but it is not execution evidence and must not make
  `scripts/xbox-dashboard-loaded-evidence-check.sh` pass. Native callback-watch
  evidence is useful; browser write-only callback-watch now works for the v2
  diagnostic, but all-access browser callback watches remain too perturbing. If
  callback attribution is needed, prefer
  `XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS=write` before returning to an
  all-access browser callback watch.
- Use `scripts/xbox-pfifo-stream-idle-boundary-compare.py --native-log <native.log> --browser-log <browser.log>` to summarize the PFIFO stream-idle transition and `pusher-empty` boundary. It compares the final `DMA_GET` commit into empty, the first PFIFO-empty snapshot, CPU context, and latest translated-block transition; it is diagnostic only and must not satisfy B6 without real browser-runtime `dashboard=xbe-executed` plus native-frame visual match evidence.
- Use `scripts/xbox-idle-before-pfifo-transition-compare.py --native-log <native.log> --browser-log <browser.log>` to summarize whether either side reaches the Xbox idle-loop PCs before the final PFIFO stream-idle transition. It is diagnostic only and must not satisfy B6 without real browser-runtime `dashboard=xbe-executed` plus native-frame visual match evidence.
- Use `scripts/xbox-pfifo-transition-irq-timing.py --native-log <native.log> --browser-log <browser.log>` to summarize PIT/timer, hard-IRQ set/reset, PIC ack, and hard-IRQ service events around `pfifo=stream-idle-transition`. It is diagnostic only and should guide the next B6 interrupt-scheduling slice.
- Use `scripts/xbox-native-headless-handoff-check.py <native-log>` to summarize
  whether a native headless/null run actually executes the dashboard, emits a
  native reference, or instead times out after stream-idle. Use `--compare-log`
  to compare targeted native variants such as the `short-animation=on` run. It
  is diagnostic only and must not satisfy B6 without strict
  `dashboard=xbe-executed` plus native/browser visual-match evidence.
- Current B6 marker hook: `xemu-xbe.c` exposes a boot-trace probe, and `ui/xemu-headless.c` polls it from the shared timeout loop. The IDE DMA read-progress path also invokes the same virtual-header probe once the dashboard image base reads as `XBEH`, so `xbe-loaded` is not dependent on the coarse headless poll. The TCG execution path in `accel/tcg/cpu-exec.c` calls `xemu_xbe_boot_trace_observe_exec(..., "tcg-tb")` before translated blocks and `xemu_xbe_boot_trace_observe_exec_transition(..., "tcg-tb-post")` after translated blocks in native Xbox and browser-boot builds; `xbe-executed` is emitted when one of those execution observations or the synchronized i386 CPU PC enters the loaded XBE image range, even before entry-ready diagnostics begin. High-bit guest PC aliases are only accepted as dashboard execution when the observed PC and the low dashboard image alias translate to the same guest physical page. The optional browser/Emscripten TCG-side virtual timer pump is controlled by `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL` and `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE` (`all` by default, `idle-loop`, `idle-loop-serviceable`, `idle-loop-serviceable-pit-only`, `pit-after-idle`, `pit-after-idle-full`, or `pit-after-pfifo-transition` for the current B6 diagnostics) and logs `BOOT_MARK b6 tcg=timer-pump ... mode=...` when a pump is emitted; it is diagnostic only and must not satisfy B6. The optional physical RAM scan emits `dashboard=xbe-header-resident source=physical-scan`, and the IDE/TCG/NV2A diagnostic paths can emit `dashboard=xbe-virtual-probe source=virtual-probe`, `dashboard=xbe-read-progress source=ide-dma-read-progress`, `dashboard=xbe-exec-probe source=tcg-tb`, `dashboard=xbe-exec-transition source=tcg-tb-post`, bounded `dashboard=xbe-exec-edge` summaries controlled by `XEMU_BOOT_TRACE_XBE_EXEC_EDGE_LIMIT`, bounded `dashboard=xbe-alias-compare` summaries controlled by `XEMU_BOOT_TRACE_XBE_ALIAS_COMPARE_LIMIT`, bounded `dashboard=xbe-entry-target-probe` summaries controlled by `XEMU_BOOT_TRACE_XBE_ENTRY_TARGET_LIMIT` and `XEMU_BOOT_TRACE_XBE_ENTRY_TARGET_WINDOW`, bounded `dashboard=xbe-dispatch-probe` summaries controlled by `XEMU_BOOT_TRACE_XBE_DISPATCH_LIMIT`, bounded `dashboard=kernel-loop-probe` summaries controlled by `XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT` and `XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_MIN_HITS`, bounded `cpu=hard-irq-service` summaries around x86 TCG hard-IRQ delivery using the `XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT` budget, bounded `xbox-pm=evt-write` and `xbox-pm=sci-update` summaries gated by the watched IRQ12/PFIFO-idle path, bounded `ac97=bm-write`, `ac97=transfer`, and `ac97=irq-update` summaries gated by the watched IRQ6/PFIFO-idle path, bounded `nv2a=pmc-access` summaries controlled by `XEMU_BOOT_TRACE_NV2A_PMC_LIMIT`, bounded `nv2a=irq-source` summaries controlled by `XEMU_BOOT_TRACE_NV2A_IRQ_LIMIT`, bounded `nv2a=irq-line` summaries controlled by `XEMU_BOOT_TRACE_NV2A_IRQ_LINE_LIMIT`, a separate non-priority IRQ-line cap controlled by `XEMU_BOOT_TRACE_NV2A_IRQ_LINE_LOW_PRIORITY_LIMIT`, bounded `pfifo=progress` summaries controlled by `XEMU_BOOT_TRACE_NV2A_PFIFO_LIMIT`, bounded `pfifo=stream-idle-transition` summaries at the final PFIFO `DMA_GET` commit into empty with CPU context and latest translated-block transition state, bounded `pfifo=stream-idle-boundary` summaries at the first PFIFO `pusher-empty` snapshot with CPU context and latest translated-block transition state, bounded `pgraph=method` summaries controlled by `XEMU_BOOT_TRACE_NV2A_PGRAPH_METHOD_LIMIT`, bounded `pgraph=notify-error` summaries controlled by `XEMU_BOOT_TRACE_NV2A_PGRAPH_NOTIFY_LIMIT`, and bounded `pgraph=notify-clear` summaries controlled by `XEMU_BOOT_TRACE_NV2A_PGRAPH_NOTIFY_CLEAR_LIMIT`; those diagnostic markers must not satisfy B6. The verbose TCG execution diagnostics are now gated until `dashboard=xbe-entry-probe status=ready` so their finite budgets describe post-entry handoff instead of being exhausted while the entry page is still unreadable; their markers include `entry_ready=yes`. Edge diagnostics now retain up to 64 unique edge shapes internally and decode register plus memory-indirect `FF /2` and `FF /4` call/jmp targets, including operand addresses for `call-mem32`/`jmp-mem32`; transition/edge logs also classify decoded branch targets with `next_branch_relation`, `next_branch_address_mode`, physical mapping, and `next_branch_phys_match`. Alias-compare diagnostics hash high-alias code and corresponding low XBE image bytes instead of dumping raw bytes. Kernel-loop diagnostics log CPU interrupt/halt/exit state plus decoded memory operands, widths, virtual region, physical mapping, and physical address, including targeted two-byte `0F B6`/`0F B7`/`0F BE`/`0F BF` `movzx`/`movsx` memory operands when readable. Dispatch diagnostics classify register and stack values as direct, entry-near, or high-alias mismatch candidates and hash stack bytes instead of logging raw stack contents. PFIFO diagnostics log post-load method, pusher/puller, waiting, interrupt state, the final stream-idle transition, and the focused stream-idle boundary only after `dashboard=xbe-loaded` and before accepted `dashboard=xbe-executed`; PGRAPH method diagnostics start earlier, after dashboard DMA/header observation, to capture the native context/error window before `xbe-loaded`; PGRAPH notify-error diagnostics record the actual trapped nonzero NOP parameter at notification raise time; PGRAPH notify-clear diagnostics record the guest interrupt-clear write plus before/after wait flags and interrupt state. Native runs set `XEMU_BOOT_TRACE_CONTEXT`; wasm/browser runs write `boot_trace_context.txt` in the mounted fixture/smoke path so these markers can distinguish native, wasm/node, and browser-runtime evidence.
- Current entry-probe marker hook: `xemu-xbe.c` emits bounded `dashboard=xbe-entry-probe` lines while the decoded XBE entry address is unreadable, then one `status=ready` line once the entry code can be read and physically matched. The B6 checker requires that ready marker as a load-quality precondition, but it remains diagnostic; B6 still needs `dashboard=xbe-executed context=browser-runtime` plus native reference-frame match.
- Current IRET diagnostic marker hook: `target/i386/tcg/seg_helper.c` calls `xemu_xbe_boot_trace_observe_iret()` before and after protected-mode IRET, and `xemu-xbe.c` emits bounded diagnostic-only `BOOT_MARK b6 cpu=iret` lines. The budget is controlled by `XEMU_BOOT_TRACE_XBE_IRET_LIMIT`. These markers must not satisfy B6; they only compare native/browser interrupt-return frame state while the B6 checker still requires `dashboard=xbe-executed` plus `BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes`.
- Current B6 read correlator: `hw/ide/core.c` emits bounded guest-LBA read markers, and `scripts/xbox-dashboard-xbe-read-evidence.py` maps those reads through FATX to dashboard XBE candidates such as `xboxdash.xbe`. The real matrix proves native-headless `xbe-read`; the latest Firefox BiDi IDE-poll diagnostic proves browser-runtime `xbe-read`.
- Remaining B6 work is browser-runtime dashboard XBE execution evidence and
  browser-vs-native frame comparison that emits
  `BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes`. Start with the
  promoted native reference hash above, then tune browser scheduling/graphic
  update behavior until browser-runtime `dashboard=xbe-executed` exists.
- Latest native TCG execution diagnostic: `build-real-b3-matrix/native-60s-xbe-exec-probe-cpu-context/boot-smoke.log` ran 60s from `build-docker-b6-xbe-scan` with the TCG translated-block execution hook, high-alias physical verification, and CPU-context fields in periodic exec-probe diagnostics. It emits `dashboard=xbe-loaded context=native-headless` and bounded `dashboard=xbe-exec-probe` samples through `observed_tbs=310000`, but still emits no `dashboard=xbe-executed`. The probe fields show sampled high aliases that overlap the XBE virtual range are `address_mode=high-alias-mismatch` with `phys_match=no` once the dashboard mapping is present, and every sampled TB remains `cpu_mode=protected32 cpl=0 cs=0x0008`.
- Latest browser TCG execution diagnostic: `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-exec-probe-cpu-context-combined.log` proves browser-runtime `xboxdash.xbe` read plus `dashboard=xbe-loaded context=browser-runtime`, emits `dashboard=xbe-exec-probe context=browser-runtime` with phys-map and CPU-context fields through `observed_tbs=200000`, and correctly fails `scripts/xbox-dashboard-loaded-evidence-check.sh` at `missing-xbe-executed-marker`. Early high-alias samples overlap the XBE virtual range while the image alias is not yet mapped; later samples are outside the dashboard XBE alias range. Every sampled browser TB also remains `cpu_mode=protected32 cpl=0 cs=0x0008`.
- Latest ret-target execution diagnostic: native `build-real-b3-matrix/native-60s-xbe-exec-ret-target-probe/boot-smoke.log` and browser `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-exec-ret-target-probe-combined.log` add non-content-leaking code-site hashes, opcode/modrm fields, branch kind, and readable return/direct/register branch targets to `dashboard=xbe-exec-probe`. Native sampled returns target `0x80030e84`; browser sampled returns target kernel high aliases such as `0x8001ae75` and `0x8001a429`. These targets remain `branch_relation=above` and do not physically match the loaded dashboard image. The browser combined log still proves `xboxdash.xbe` read/load and still fails the B6 checker at `missing-xbe-executed-marker`.
- Latest post-TB transition diagnostic: native `build-real-b3-matrix/native-60s-xbe-exec-transition-probe/boot-smoke.log` and browser `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-exec-transition-probe-combined.log` emit `dashboard=xbe-exec-transition` after translated blocks execute. The hook samples the synchronized next PC and can emit `dashboard=xbe-executed` if that next PC reaches the loaded dashboard image. Current native next PCs still cycle through kernel locations such as `0x80030e84`, `0x80014f32`, and `0x800426d4`; browser next PCs still cycle through kernel locations such as `0x8002430e`, `0x8001ae75`, `0x80060ffe`, and `0x80014fb4`. No post-TB next PC physically matches the loaded dashboard image, and the browser combined log still fails the B6 checker at `missing-xbe-executed-marker`.
- Latest transition-edge diagnostic: native `build-real-b3-matrix/native-60s-xbe-exec-edge-probe/boot-smoke.log` and browser `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-exec-edge-probe-combined.log` emit bounded `dashboard=xbe-exec-edge` summaries after translated blocks. The latest browser run proves `xboxdash.xbe` read/load, B4 display capture, and B5 runtime evidence, emits 64 edge samples, and still fails the B6 checker at `missing-xbe-executed-marker`. Repeated browser edges include kernel/high-alias paths such as `0x80014159 -> 0x80014386`, `0x8004cdb8 -> 0x80014fb4`, and `0x80014fb4 -> 0x8001aea5`; none physically match the loaded dashboard image.
- Latest branch-target diagnostic: native `build-real-b3-matrix/native-60s-xbe-branch-target-classification/boot-smoke.log` and browser `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-branch-target-classification-combined.log` decode indirect branch operands in edge samples and classify decoded targets against the loaded dashboard image. Native and browser both resolve a memory-indirect `call-mem32` through operand address `0x8003ad24` to target `0x800241fe`; the browser run also records `call-reg` dispatch to `0x80046280`. These targets remain kernel/high-alias paths (`next_branch_relation=above`, `next_branch_address_mode=high-alias-mismatch` or `none`, and no physical match to the loaded dashboard image), the browser log still contains browser-runtime `xboxdash.xbe` read plus `dashboard=xbe-loaded`, and the combined log still fails the B6 checker at `missing-xbe-executed-marker`.
- Latest dispatch diagnostic: native `build-real-b3-matrix/native-60s-xbe-dispatch-probe-v3/boot-smoke.log` and browser `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-dispatch-probe-v3-combined.log` inspect whether post-load registers or the top stack words contain dashboard image or entry-near dispatch candidates. Native emits 16 probes and browser emits 10. Both keep `reg_phys_match_count=0` and `reg_entry_near_count=0`; browser keeps `reg_first_candidate=none` throughout. Native has one register candidate (`ecx=0x8003a950`) but it is a high-alias mismatch above the image, not an execution handoff. Stack direct matches are in XBE header bytes such as offsets `0x00000282`, `0x00000293`, `0x00000246`, or `0x00000000`; other stack candidates are high-alias mismatches or unknown near kernel paths such as `0x8001ae75`, `0x8001a429`, and `0x800141bb`. No `dashboard=xbe-executed` marker appears.
- Earlier native diagnostic: `build-real-b3-matrix/native-60s-xbe-scan/boot-smoke.log` ran 60s from `build-docker-b6-xbe-scan`, read `xboxdash.xbe`, and emitted no `dashboard=xbe-loaded`/`dashboard=xbe-executed` before the read-progress virtual-header hook was added.
- Latest DMA/virtual diagnostic: `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-read-progress-loaded-combined.log` contains browser-runtime `xbe-read`, `dashboard=xbe-read-progress` transitioning from `page_status=pde-not-present` to `page_status=mapped-page`, and `dashboard=xbe-loaded context=browser-runtime guest_addr=0x00010000 source=virtual-header phys_addr=0x000e0000`. The B6 checker correctly fails that combined log at `missing-xbe-executed-marker`. The matching native focused run is `build-real-b3-matrix/native-60s-xbe-read-progress-loaded/boot-smoke.log`, which emits `dashboard=xbe-loaded context=native-headless` but no `dashboard=xbe-executed`.
- Historical B6 tooling note: Firefox BiDi plus Playwright capture tooling remains the final visual path, but visual comparison is staged behind true XBE execution. The callback diagnostic artifact `build-real-b3-matrix/browser-runtime-firefox-bidi-pm-ac97-callback-v1-combined.log` proved browser-runtime `xboxdash.xbe` read/load/entry-ready and reached the first browser hard IRQ from the same serviceable idle PC as native (`0x8001b030`), but it timed out as a runtime smoke and still failed at `missing-xbe-executed-marker`. The B5-pass source-comparable browser artifact `build-real-b3-matrix/browser-runtime-firefox-bidi-irq-source-v6-combined.log` is historical context, not the active B6 baseline.
- Historical PIT-only timer-pump diagnostic: `build-real-b3-matrix/browser-runtime-firefox-bidi-pit-only-pump-v1.log` used `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=idle-loop-serviceable-pit-only`, tagged the PIT timer as pump-eligible, and filtered the browser TCG pump to that timer. Native and wasm builds passed. The focused comparator reported no extra vectors, no extra PIC/LPC assertions, no PM/AC97 callback/source events, and native-matching first hard-IRQ service plus first IRET; the artifact still timed out and remained diagnostic-only because it did not emit `dashboard=xbe-executed` or carry full B6 visual-reference evidence. Keep this as evidence that pump modes are probes, not the final architecture.
- Historical PFIFO transition diagnostics: `build-real-b3-matrix/native-pfifo-activity-v1/boot-smoke.log`, `build-real-b3-matrix/browser-runtime-firefox-bidi-pfifo-activity-v1.log`, `build-real-b3-matrix/browser-runtime-firefox-bidi-pfifo-transition-pit-at-transition-v1.log`, `build-real-b3-matrix/browser-runtime-firefox-bidi-pfifo-before-transition-v3.log`, `build-real-b3-matrix/browser-runtime-firefox-bidi-pfifo-before-transition-activity-v1.log`, `build-real-b3-matrix/browser-runtime-firefox-bidi-pfifo-before-transition-activity-defer-v2.log`, `build-real-b3-matrix/browser-runtime-firefox-bidi-pfifo-before-transition-activity-pre-tb-defer-v1.log`, and `build-real-b3-matrix/browser-runtime-firefox-bidi-pfifo-defer-to-idle-v1.log` added the exact final `DMA_GET` commit marker before the older `pusher-empty` boundary plus PFIFO pre-transition gate and IRQ-service ordering diagnostics. Native and wasm builds passed. The browser runtime still timed out and emitted no `dashboard=xbe-executed`, but both sides emitted `pfifo=stream-idle-transition` for the same final command: `dma_get_before=0x03881314`, `dma_get_after=0x03881318`, `dma_put=0x03881318`, `method=0x1d90`, `processed=1`. The newer defer-to-idle diagnostic proved browser can keep the hard IRQ pending until native serviceable idle PC `0x8001b030`; its first `cpu=hard-irq-service` and `cpu=iret` frame hash matched native. This evidence is superseded by the `goal.md` front-most target: pre-service tick accumulation before the first watched read, then post-idle/post-service CPU flow after the native-matching service/IRET frame.
- The next technical target is no longer generic PIC acknowledgement, callback
  attribution, PM/AC97 timer-pump filtering, repeated PIT delivery, PFIFO/PGRAPH
  command progress, hard-IRQ service frame mismatch, native detector proof, or
  renderer polish. Native actual dashboard execution and native reference are
  proven by `native-headless-graphic-update-v2`; converge the browser
  pre-service tick accumulation before the first watched read, preserve the
  useful post-service watch edge, and then re-check whether it reaches
  browser-runtime `dashboard=xbe-executed`. All
  B6 diagnostic markers remain insufficient for
  completion until browser-runtime `dashboard=xbe-executed` plus
  native-reference visual match evidence exist.
- Prefer logs or trace events over manual visual inspection until B4.
- Emit deterministic markers shaped like `BOOT_MARK ...` and a final `BOOT_SMOKE_RESULT ...` from smoke runs.
- Native headless boot smoke mode is enabled with `XEMU_HEADLESS_BOOT=1`; set `XEMU_BOOT_TRACE=1` for markers and optionally `XEMU_HEADLESS_BOOT_MS=<milliseconds>` for the timeout.
- Compare native headless and wasm marker sequences before investigating browser-only behavior.
- Measure TCI speed before investing heavily in renderer or product work.

## How To Continue On Another Machine

1. Check out this branch and install the same normal xemu build prerequisites plus Docker.
2. Do not commit proprietary Xbox assets. Put legally obtained local fixtures in `fixtures/` or `xemu-fixtures/`:
   - Required: `flash.bin`, `xbox_hdd.img`
   - Optional: `mcpx.bin` exactly 512 bytes, `eeprom.bin` exactly 256 bytes, `dvd.iso`
3. Run `scripts/xbox-fixture-privacy-check.sh` and confirm it reports fixture directories as ignored and no fixture files as tracked.
4. Run `scripts/xbox-real-fixtures-ready.sh`. Continue only after it reports `REAL_FIXTURE_READY_RESULT result=pass`.
5. Run `XEMU_REAL_B3_PREFLIGHT_ONLY=1 scripts/xbox-real-b3-matrix.sh` to validate discovery, sizes, privacy, and manifest output without doing the full real boot matrix.
6. Run `scripts/xbox-real-b3-matrix.sh` for real B3 evidence.
7. Run `scripts/xbox-boot-evidence-report.sh` and `scripts/xbox-boot-next-step.sh` after each meaningful run. The generated `xbox-browser-boot-status.md` should always explain the current state and next command.
8. Do not move to renderer/product polish until `scripts/xbox-real-b3-evidence-check.sh build-real-b3-matrix/real-b3-matrix.log` passes.
9. After B3 passes, pursue B4 by adding a real display-path marker plus non-empty browser display capture evidence, then validate with `scripts/xbox-display-capture-evidence-check.sh build-real-b3-matrix/real-b3-matrix.log`.
10. After B4 passes, pursue B5 browser usability and validate with `scripts/xbox-browser-runtime-evidence-check.sh build-real-b3-matrix/real-b3-matrix.log`.
11. The final completion gate is `scripts/xbox-boot-completion-audit.sh`; it must fail until synthetic prerequisites and real B3/B4/B5/B6 evidence all pass.
12. After B3/B4/B5 pass, the next long-term goal is B6 dashboard loaded: add dashboard/XBE markers, native reference frame capture, and browser-vs-native frame comparison before claiming the dashboard fully loads.
13. Current B6 next slice on this machine: browser-side pre-service tick
    accumulation toward browser-runtime dashboard execution.
    Native actual execution and native reference are now proven by
    `native-headless-graphic-update-v2`; start from
    `scripts/xbox-b6-current-boundary.sh`,
    `scripts/xbox-native-actual-xbe-execution-check.py
    build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`,
    `scripts/xbox-native-headless-handoff-check.py
    build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`,
    `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`, and
    `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`.
    Keep the older 300s, `pit-after-idle-full-pump-v1`, v5 combined, PFIFO
    transition, PFIFO pre-commit, and section-map-v2 logs as historical context.
    The fresh
    `build-real-b3-matrix/browser-memory-watch-write-0x3a890-precommit-v1-combined.log`
    is also historical/negative context, not a promoted baseline.
    The latest useful browser artifact preserves B4 display capture, dashboard
    FATX read/load/entry-ready evidence, executable section-map evidence, PFIFO
    stream-idle, bounded browser main-loop timer progress, vector `0x30`
    service/IRET evidence, and the current `0x0003a890` memory-sample mismatch:
    native reads `0x0014c080`, browser reads `0x00002710`, and the comparator
    normalizes that to native 136 ticks versus browser 1 tick. Browser remains
    the missing side: it must converge pre-service tick accumulation before the
    first watched read, preserve the post-service edge, emit strict
    browser-runtime `dashboard=xbe-executed`, and then
    `BROWSER_DASHBOARD_CAPTURE native_ref_match=yes` against the native hash.

For iOS app work in this workspace, do not use the simulator.
