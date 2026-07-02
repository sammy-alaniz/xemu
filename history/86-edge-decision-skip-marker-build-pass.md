# Edge Decision Skip Marker Build Pass

## Purpose

- One new fact this run was supposed to produce: whether the low-impact `edge-decision-skip` marker patch compiles in the podman-backed WASM build.

## Command(s)

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: `build-wasm-pic/qemu-system-i386.js`
- Fixture assumptions: podman-backed WASM build with image build skipped.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: compile viability of the `edge_trace_marker_absence_reason` diagnostic.

## Findings

- Result: build passed.
- Build compiled `xemu-xbe.c.o`.
- Build linked `qemu-system-i386.js`.
- This verifies the new `BOOT_MARK b6 edge-decision-skip` code is in the current browser runtime artifact.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not measured; no runtime was started.

## Decision

- Status: current
- Why: the diagnostic compiles and is ready for one targeted browser runtime run to populate `edge_trace_marker_absence_reason`.
- Independent critique used: no

## Next Step

- Narrow follow-up: run the required loop check, then run exactly one ready-edge host4 browser runtime with `XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4` to collect `edge-decision-skip` or `edge-decision` markers.
