# Pre-First-Read Entry-Ready Gate Filter Build Pass

## Purpose

- One new fact this run was supposed to produce: whether the entry-ready-only gate marker filter compiles and links in the browser/WASM build.

## Command(s)

```sh
git diff --check -- xemu-xbe.c

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

- Loop-guard field(s) this run could change or explain: `entry_ready_gate_marker_filter_buildable`.

## Findings

- Result: pass.
- `git diff --check -- xemu-xbe.c` produced no output.
- The escalated podman build completed and linked `qemu-system-i386.js`.
- The diagnostic filter now requires `entry_ready=yes` before consuming the `scheduler=pre-first-read-gate` marker budget or reading the watched word.
- Scheduler arming behavior is unchanged.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not tested; this was compile/link verification only.

## Decision

- Status: current
- Why: build verification passed, so the next decision is whether one runtime validation is justified to explain `entry_ready_gate_scheduler_not_armed_reason`.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/157` approved only the entry-ready marker filter change and no scheduler behavior change.

## Next Step

- Narrow follow-up: run the required loop check before any runtime validation. The proposed runtime must be judged primarily on the first entry-ready `scheduler=pre-first-read-gate reason=...` marker.
