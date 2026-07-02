# Post PFIFO Pre First Read TCG Runtime

## Purpose

- One new fact this run was supposed to produce:
  whether the new opt-in `pit-post-pfifo-pre-first-read` TCG checkpoint mode
  activates before the first watched read and moves
  `browser_first_watch_read_ticks` away from 0 without weakening strict B6.

## Command(s)

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin NODE_PATH= \
XEMU_MCPX='/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin' \
XEMU_FLASH='/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin' \
XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin \
XEMU_HDD='/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
XEMU_BROWSER_RUNTIME_MODE=real \
XEMU_BROWSER_RUNTIME_EXPECT_B3=1 \
XEMU_BROWSER_RUNTIME_DRIVER=firefox-bidi \
XEMU_BROWSER_RUNTIME_BROWSER=firefox \
XEMU_BROWSER_RUNTIME_BUILD_DIR=../../build-wasm-pic \
XEMU_BROWSER_RUNTIME_PORT=8846 \
XEMU_BROWSER_RUNTIME_BOOT_MS=90000 \
XEMU_BROWSER_RUNTIME_TIMEOUT_MS=150000 \
XEMU_BROWSER_RUNTIME_DUMP_TRANSCRIPT=1 \
XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=off \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT=32 \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT=32 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS=0x0003a890 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT=64 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS=write \
XEMU_BOOT_TRACE_XBE_PIC_IRQ_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT=256 \
XEMU_BOOT_TRACE_XBE_IRET_LIMIT=256 \
XEMU_BOOT_TRACE_XBE_PIT_IRQ_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_MAIN_LOOP_TIMER_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_TIMER_OPPORTUNITY_LIMIT=8 \
XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4 \
XEMU_BOOT_TRACE_XBE_TICK_BLOCK_LIMIT=256 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=1 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-post-pfifo-pre-first-read \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT=4 \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1/browser-runtime.log \
  2>&1

scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1-combined.log \
  --require-context browser-runtime

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1-combined.log

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1-combined.log

scripts/xbox-post-service-edge-decision-compare.py \
  --log baseline=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  --log tcg=build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1-combined.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1/browser-runtime.log`
- Combined output:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1-combined.log`
- Fixture assumptions: real browser runtime, Firefox BiDi, rebuilt
  `build-wasm-pic`, ready-edge host4 shape preserved, only the opt-in TCG
  timer-pump mode changed.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `tcg_timer_pump_mode_seen`, `pre_first_read_tcg_checkpoint_active`,
  `browser_first_watch_read_ticks`, `browser_post_service_top_edge`, and
  `browser_dashboard_xbe_executed`.

## Findings

- Result: strict B6 still failed with
  `DASHBOARD_LOADED_EVIDENCE result=fail
  reason=missing-xbe-executed-marker`.
- The runtime applied the requested knobs:
  `trace_xbe_tcg_timer_pump_interval=1`,
  `trace_xbe_tcg_timer_pump_after_idle_limit=4`, and
  `trace_xbe_tcg_timer_pump_mode=pit-post-pfifo-pre-first-read`.
- No `BOOT_MARK b6 tcg=timer-pump` marker appeared, so the new checkpoint did
  not activate. This makes `tcg_timer_pump_mode_seen=no` and
  `pre_first_read_tcg_checkpoint_active=no`.
- The pre-service tick gap did not improve:
  `browser_first_watch_read_ticks=0`, native remained 136, and
  `first_watch_read_tick_delta=136`.
- The first browser watched read remained
  `0x80014f32->0x80030e84` with value `0x00000000`.
- The post-service edge regressed versus the active baseline:
  `classifications=baseline:useful-post-service-edge,tcg:post-service-edge-diverged`
  and `top_edges=baseline:0x80030e84->0x80030f31,tcg:0x80018e04->0x80018e07`.
- The expected block still appeared later:
  `first_block_edge=0x80030e84->0x80030f31` with
  `first_block_start_ticks=1`.
- Marker ordering around the boundary showed the ready-edge pump at
  `eip=0x80018e04` with `cpu_interrupt_request=0x00000002`, then hard IRQ
  service, then a host-pump sample at `eip=0x80014f32` with
  `irq_inhibited=yes`, then the first `0x80030e84` watched write and
  edge-decision.
- Dashboard read/load/entry-ready and detector proof remained present:
  `dashboard=xbe-loaded`, `dashboard=xbe-entry-probe status=ready`,
  `dashboard=xbe-executed-detector-proof result=pass`, and combined
  `dashboard=xbe-read`.
- Section-map remained valid:
  `DASHBOARD_SECTION_MAP_EVIDENCE result=pass ... executable_sections=1
  entry_section=3`.
- B4/B5/read/load/entry-ready/section-map did not regress. Strict B6 and the
  useful post-service top edge did not pass.

## Decision

- Status: negative evidence.
- Why: the mode was configured, but its readiness gate never opened before the
  first watched read. It did not move `browser_first_watch_read_ticks` and it
  made the top post-service edge worse.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: `history/121` approved exactly one validation of
  this opt-in mode. The result answers that validation: the checkpoint did not
  fire, so the next step must explain the closed gate or revise the gate from
  code/log evidence before any additional runtime.

## Progress-Method Critique

- This run was justified because it tested one new ownership field instead of
  remeasuring host-pump counts.
- The method is now at risk of becoming diagnostic-heavy if the next step is
  another browser runtime without first explaining why the TCG gate did not
  open.
- The current evidence still connects to strict dashboard execution because the
  dashboard marker is blocked behind the same pre-first-read tick/CPU-flow
  divergence, but the next 2-3 turns should prefer static gate analysis over
  another runtime.
- Process adjustment: require the next action to name the exact readiness
  predicate it changes or explains, for example pending IRQ, IRQ inhibition,
  idle-loop PC selection, PFIFO-empty state, expired-timer state, or
  tick/edge-decision count.

## Next Step

- Narrow follow-up: run the required loop check. If approved, inspect the TCG
  gate predicates against the runtime timeline and revise or kill the
  `pit-post-pfifo-pre-first-read` mode before any further browser run.
