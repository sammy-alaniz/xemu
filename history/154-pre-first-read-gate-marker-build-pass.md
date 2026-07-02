# Pre-First-Read Gate Marker Build Pass

## Purpose

- One new fact this run was supposed to produce: whether the bounded `scheduler=pre-first-read-gate` diagnostic compiles and links in the browser/WASM build.

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

- Loop-guard field(s) this run could change or explain: `pre_first_read_gate_marker_buildable`.

## Findings

- Result: pass.
- `git diff --check -- xemu-xbe.c` produced no output.
- The escalated podman build completed and linked `qemu-system-i386.js`.
- The diagnostic patch adds a bounded `BOOT_MARK b6 scheduler=pre-first-read-gate` marker with a `reason=` field and gate state for mode, trace, entry-ready, loaded, interval, TB budget, pump limit, virtual timer state, CPU serviceability, first-read edge count, tick-block count, watched-word ticks, and NV2A wait state.
- The patch also keeps the after-TB pump exclusion from consuming gate-marker budget by using a non-emitting predicate there.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not tested; this was compile/link verification only.

## Decision

- Status: current
- Why: build verification passed, so the marker is ready for one runtime validation to explain `scheduler_not_armed_reason`.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/153` recommended code inspection or a tiny diagnostic code change, then no runtime until the code can emit one compact gate-state line before the first watched read.

## Next Step

- Narrow follow-up: run the required loop check before any runtime validation. The proposed runtime must change or explain `scheduler_not_armed_reason` and should not be treated as a B6-success run unless strict browser `dashboard=xbe-executed` appears.
