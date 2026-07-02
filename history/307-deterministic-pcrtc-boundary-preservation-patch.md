# 307 - deterministic PCRTC boundary preservation patch

## Purpose

Apply the approved static patch after history/306. The field this code change
can change or explain is `browser_pre_stream_vector_service_state`, by removing
the `pre-entry-dead-zone` design and preserving the established ready path until
the exact after-entry/pre-stream PCRTC condition is actually present.

## Exact commands

Static diff check:

```sh
git diff --check -- xemu-xbe.c hw/xbox/nv2a/nv2a.c
```

WASM build:

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh
```

## Inputs and artifacts

- Edited:
  - `xemu-xbe.c`
  - `hw/xbox/nv2a/nv2a.c`
- Build artifact:
  - `build-wasm-pic/qemu-system-i386.js`

## Loop-guard fields

- `browser_pre_stream_vector_service_state`
- `native_pre_stream_serviceable_state_browser_mapping`
- `pre_service_browser_first_watch_read_ticks`

## Findings

1. `xemu_xbe_boot_trace_main_loop_timer_pump_ready()` now treats exact
   `pcrtc/intr-clear` as a special success before PFIFO stream-idle, but if
   that exact state is not present it falls back to the established PFIFO-empty
   readiness check instead of returning false.
2. `xemu_xbe_main_loop_timer_pump_block_reason()` now mirrors that behavior:
   the exact PCRTC mode is unblocked by either exact `pcrtc/intr-clear` or
   PFIFO-empty, and otherwise reports
   `wait-not-pcrtc-intr-clear-or-pfifo-empty`.
3. `nv2a_browser_pcrtc_vblank_should_raise()` now lets the deterministic PCRTC
   branch suppress ordinary PCRTC vblank policy only while dashboard observed,
   entry-ready, and pre-stream-idle are all true. This keeps the deterministic
   PCRTC mode from globally controlling earlier boot phases.
4. `git diff --check` passed.
5. The Podman WASM build passed and relinked `qemu-system-i386.js`, including
   rebuilt `hw_xbox_nv2a_nv2a.c.o` and `xemu-xbe.c.o`.
6. No browser runtime was started for this history entry.

## Decision

The patch is valid as a boundary-preservation correction. It does not claim B6
progress by itself; it only removes the static design flaw that prevented the
exact PCRTC branch from preserving the known path to entry-ready.

## Next step

Run the required bounded sub-agent loop check before any runtime or additional
code change. The next approved action should be either a static artifact update
in `goal.md` documenting the corrected invariant, or one bounded browser
runtime whose first success condition is preserving B4/B5/dashboard
read/load/entry-ready before evaluating `pre_service_browser_first_watch_read_ticks`.
