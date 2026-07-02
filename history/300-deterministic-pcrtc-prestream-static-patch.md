# 300 - Deterministic PCRTC Pre-Stream Static Patch

## Purpose

- One new fact this patch was supposed to produce:
  implement the default-off exact-predicate deterministic PCRTC pre-stream
  tick-window mode and verify it statically before any runtime.

## Command(s)

```sh
git diff --check -- xemu-xbe.h xemu-xbe.c ui/xemu-headless.c \
  hw/xbox/nv2a/nv2a.c browser/xbox-boot/main.js \
  browser/xbox-boot/worker.js scripts/xbox-browser-runtime-smoke.sh \
  scripts/xbox-browser-runtime-firefox-bidi.mjs

node --check browser/xbox-boot/main.js
node --check browser/xbox-boot/worker.js
node --check scripts/xbox-browser-runtime-firefox-bidi.mjs
bash -n scripts/xbox-browser-runtime-smoke.sh

rg -n "xemu_xbe_boot_trace_main_loop_timer_pump_pcrtc_prestream_ready|xemu_xbe_boot_trace_pfifo_stream_idle_transition_observed|pcrtc-intr-clear-before-stream-idle-then-after-pfifo-empty|deterministic-pcrtc-prestream-tick-window|XEMU_BROWSER_BOOT_DETERMINISTIC_PCRTC_PRESTREAM|browser_boot_deterministic_pcrtc_prestream|browser-deterministic-pcrtc-prestream|dashboard=xbe-executed" \
  xemu-xbe.c xemu-xbe.h ui/xemu-headless.c hw/xbox/nv2a/nv2a.c \
  browser/xbox-boot/main.js browser/xbox-boot/worker.js \
  scripts/xbox-browser-runtime-smoke.sh \
  scripts/xbox-browser-runtime-firefox-bidi.mjs

PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh
```

## Inputs And Artifacts

- Design:
  `history/298-deterministic-pcrtc-prestream-service-design.md`
- Loop-check approval:
  `history/299-pcrtc-prestream-patch-loop-check.md`
- Modified files:
  - `xemu-xbe.h`
  - `xemu-xbe.c`
  - `ui/xemu-headless.c`
  - `hw/xbox/nv2a/nv2a.c`
  - `browser/xbox-boot/main.js`
  - `browser/xbox-boot/worker.js`
  - `scripts/xbox-browser-runtime-smoke.sh`
  - `scripts/xbox-browser-runtime-firefox-bidi.mjs`
- Build artifact:
  `build-wasm-pic/qemu-system-i386.js`
- Fixture assumptions:
  new behavior is disabled unless
  `XEMU_BROWSER_BOOT_DETERMINISTIC_PCRTC_PRESTREAM` or
  `/xemu-fixtures/browser_boot_deterministic_pcrtc_prestream.txt` is set.

## Expected Field(s)

- Loop-guard field(s) this patch could change or explain:
  `browser_pre_stream_vector_service_state`

## Findings

- Result:
  static patch and Podman wasm build passed.
- Important marker/comparator lines:
  - Added `xemu_xbe_boot_trace_main_loop_timer_pump_pcrtc_prestream_ready()`
    with an exact `pcrtc/intr-clear` predicate.
  - Added public
    `xemu_xbe_boot_trace_pfifo_stream_idle_transition_observed()` so NV2A can
    gate pre-stream PCRTC vblank raise without reading internal trace state.
  - Added new headless timer mode aliases:
    `pcrtc-intr-clear-before-stream-idle-then-after-pfifo-empty` and
    `deterministic-pcrtc-prestream-tick-window`.
  - Added source tag `browser-deterministic-pcrtc-prestream`.
  - Added browser fixture/env plumbing for
    `browser_boot_deterministic_pcrtc_prestream`.
  - `hw/xbox/nv2a/nv2a.c` now allows at most one default-off deterministic
    pre-stream PCRTC vblank raise only after dashboard observed, entry-ready,
    PCRTC vblank enabled, not pending, and before PFIFO stream-idle.
  - `pcrtc_write()` remains the only path that publishes
    `source=pcrtc op=intr-clear`; this patch does not synthesize that marker.
  - Strict `dashboard=xbe-executed` detection in
    `xemu_xbe_boot_trace_mark_executed()` was not changed.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not tested at runtime. Static verification and wasm build passed only.

## Decision

- Status: current
- Why:
  The patch implements the reviewed default-off exact-predicate mode and builds.
  It is not yet runtime evidence and must not be promoted until a loop check
  approves one bounded browser run.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  `history/299` approved this static-first implementation and disallowed
  runtime until after patch history plus loop check.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary:
  The method remains tied to the missing pre-stream `pcrtc/intr-clear` context
  and avoids old normal-vblank or broad pump branches.
- If yes, process adjustment for next 2-3 turns:
  Run the mandatory loop check. If it approves runtime, run exactly one bounded
  browser artifact with the new default-off knobs explicitly enabled.

## Next Step

- Narrow follow-up:
  Run the required bounded loop check before any runtime, probe, or further code
  change.
