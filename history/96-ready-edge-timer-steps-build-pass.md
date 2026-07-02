# Ready Edge Timer Steps Build Pass

## Purpose

- One new fact this run was supposed to produce: whether the ready-edge host-pump timer-step patch compiles into the browser WASM artifact.

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

- Loop-guard field(s) this run could change or explain: compile viability for the ready-edge timer-step behavior that targets `browser_first_watch_read_ticks`.

## Findings

- Result: build passed.
- Build compiled `ui_xemu-headless.c.o`.
- Build linked `qemu-system-i386.js`.
- The browser artifact now allows the ready-edge host timer pump to use the existing timer-step count when `XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS` is greater than 1, without requiring full deterministic mode.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not measured; no runtime was started.

## Decision

- Status: current
- Why: the behavioral change compiles and is ready for one targeted runtime run with deterministic mode off and timer steps set to 2.
- Independent critique used: no

## Next Step

- Narrow follow-up: run the required loop check, then run one ready-edge host4 browser runtime with `XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS=2` and deterministic mode unset. The primary field is `browser_first_watch_read_ticks`.
