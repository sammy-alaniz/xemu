# Pre-First-Read Micro-Scheduler Build Pass

## Purpose

- One new fact this run was supposed to produce: whether the opt-in pre-first-read micro-scheduler patch compiles and links in the browser/WASM podman build after the one-line C syntax fix.

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

- Loop-guard field(s) this run could change or explain: `build_verification_status`

## Findings

- Result: pass.
- `git diff --check -- xemu-xbe.c xemu-xbe.h accel/tcg/cpu-exec.c` produced no output.
- The escalated podman build completed and linked `qemu-system-i386.js`.
- The compile result proves the opt-in `pit-pre-first-read-micro-scheduler` code path builds, but does not yet prove runtime behavior.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not tested; this was compile/link verification only.

## Decision

- Status: current
- Why: build verification passed, so the next useful question is whether the new opt-in mode changes the targeted runtime field without weakening strict B6 evidence.
- Independent critique used: no

## Next Step

- Narrow follow-up: run the required loop check before any browser runtime validation. The proposed runtime field is `pre_first_read_tick_block_completions_browser`, guarded by `browser_first_watch_read_ticks` and post-service edge preservation.
