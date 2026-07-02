# Pre First Read TCG V2 Early Timeout

## Purpose

- One new fact this run was supposed to produce:
  whether the updated `pit-post-pfifo-pre-first-read` mode emits
  `tcg=timer-pump` at `0x80030e84` before the first watched read.

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
XEMU_BROWSER_RUNTIME_PORT=8847 \
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
  > build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log \
  2>&1

scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log \
  --out build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-combined.log \
  --require-context browser-runtime

rg -n "BROWSER_RUNTIME_(TRANSCRIPT|SMOKE)|BROWSER_DISPLAY_CAPTURE|BROWSER_DISPLAY_SCANOUT|DASHBOARD_LOADED_EVIDENCE|DASHBOARD_SECTION_MAP_EVIDENCE|BOOT_MARK b6 tcg=timer-pump|BOOT_MARK b6 dashboard=xbe-(read|loaded|entry-probe|executed|exec-section-miss)|BOOT_MARK b6 dashboard=section-map|BOOT_MARK b6 pfifo=stream-idle|BOOT_MARK b6 main-loop=timers|BOOT_MARK b6 memory-watch|BOOT_MARK b6 edge-decision|BOOT_MARK b6 tick-block=complete" \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log

tail -n 180 build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log
wc -l build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log
```

## Inputs And Artifacts

- Runtime log:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log`
- Failed combined output target:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-combined.log`
- Prior code/build:
  `history/126-pre-first-read-tcg-tick-block-pc-build.md`
- Prior loop approval:
  `history/129-pre-first-read-tcg-v2-eeprom-loop-check.md`
- Fixture assumptions: same approved validation shape, with only EEPROM path
  corrected to `/tmp/xemu-b6-eeprom.bin`.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `pre_first_read_tcg_checkpoint_active`, `browser_first_watch_read_ticks`, and
  `browser_post_service_top_edge`.

## Findings

- Result: the corrected browser runtime started but timed out very early,
  before dashboard read/load.
- The runtime log has only 153 lines.
- `BROWSER_RUNTIME_TRANSCRIPT result=pass` and
  `BROWSER_RUNTIME_SMOKE result=pass`, but `boot_result=timeout`.
- The transcript reports `b4_marker=no` and `display_capture=no`.
- Display output remained placeholder-only:
  `BROWSER_DISPLAY_SCANOUT result=skip reason=placeholder`.
- Combining dashboard read evidence failed:
  `DASHBOARD_XBE_READ_EVIDENCE result=fail reason=missing-ide-read-markers`.
- Strict dashboard evidence failed on the raw runtime log:
  `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-read-marker`.
- No `dashboard=xbe-read`, `dashboard=xbe-loaded`,
  `dashboard=xbe-entry-probe`, section-map, PFIFO stream-idle,
  `tcg=timer-pump`, memory-watch, edge-decision, or tick-block markers were
  present.
- The run did not reach the audited B6 boundary, so it did not evaluate whether
  allowing `0x80030e84` opens the TCG checkpoint.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Yes relative to the active B6 baseline and the `v1` TCG artifact:
  read/load/entry-ready/section-map/stream-idle and B4 were all missing.

## Decision

- Status: failed validation / negative setup evidence.
- Why: the run did not test the intended pre-first-read TCG predicate because
  it timed out before dashboard read/load and before the B6 CPU-flow boundary.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: `history/129` approved a corrected rerun after
  fixture preflight. This artifact proves the corrected run started, but it
  regressed too early to answer the approved field.

## Progress-Method Critique

- This result does not advance strict dashboard execution directly because the
  run failed before the dashboard was read.
- It does reveal that the validation setup is no longer preserving the
  known-good browser baseline, so another blind runtime would be rerun-heavy.
- The next 2-3 turns should not tweak the TCG predicate again until the
  early-timeout cause is separated from the B6 checkpoint behavior.
- Process adjustment: require the next action to explain whether this early
  timeout is fixture/runtime setup drift, port/origin state, or a code
  regression, before another browser validation.

## Next Step

- Narrow follow-up: run the required loop check. Ask whether to inspect
  fixture/runtime setup versus compare the `v1` and `v2` early logs/source
  before any further runtime.
