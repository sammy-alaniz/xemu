# Pre-First-Read Micro-Scheduler Activation Build Pass

## Purpose

- One new fact this run was supposed to produce: whether the armed-only before-interrupt site activation fix compiles and links in the browser/WASM build.

## Command(s)

```sh
git diff --check -- xemu-xbe.c xemu-xbe.h accel/tcg/cpu-exec.c

PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
  XEMU_WASM_SKIP_IMAGE_BUILD=1 \
  XEMU_WASM_BUILD_DIR=build-wasm-pic \
  XEMU_WASM_JOBS=4 \
  scripts/docker-build-xemu-wasm.sh
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: `build-wasm-pic`, linked target `qemu-system-i386.js`
- Fixture assumptions: podman escalation is required for browser/WASM build access in this environment.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `build_verification_status`, `scheduler_site_armed_only`

## Findings

- Result: pass.
- `git diff --check -- xemu-xbe.c xemu-xbe.h accel/tcg/cpu-exec.c` produced no output.
- The escalated podman build completed and linked `qemu-system-i386.js`.
- The code now separates mode selection from before-interrupt site activation:
  the before-interrupt site is active only when the pre-first-read scheduler's entry-ready, timer-expired, and serviceable-PC gates pass.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not tested; this was compile/link verification only.

## Decision

- Status: current
- Why: build verification passed, so the next useful question is whether the armed-only activation restores the normal B4/dashboard boundary before evaluating scheduler stop reasons.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/149` approved revising only site activation, then building before any validation.

## Next Step

- Narrow follow-up: run the required loop check before any runtime validation. The proposed runtime must first judge `scheduler_site_armed_only_restores_boundary` before interpreting `pre_first_read_tick_block_completions_browser`.
