# Call Chain Podman Build Smoke Preflight

## Purpose

- One new fact this run was supposed to produce:
  whether the rebuilt Podman-backed native binary can run with
  `XEMU_BOOT_TRACE_CALL_CHAIN=1` and emit the broad call-chain trace.

## Command(s)

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_DOCKER_BUILD_DIR=build-docker-b6-pfifo-boundary \
scripts/docker-build-xemu.sh

PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_SMOKE_BUILD_DIR=build-docker-b6-pfifo-boundary \
XEMU_SMOKE_OUT_DIR=build-real-b3-matrix/call-chain-trace-v1 \
XEMU_HEADLESS_BOOT_MS=30000 \
XEMU_BOOT_TRACE=1 \
XEMU_BOOT_TRACE_CALL_CHAIN=1 \
scripts/xbox-boot-smoke.sh docker-headless
```

## Inputs And Artifacts

- Baseline native log: not used.
- Baseline browser log: not used.
- Output directory/log: intended `build-real-b3-matrix/call-chain-trace-v1`,
  but the smoke stopped during fixture preflight before emulation.
- Fixture assumptions: the first smoke command omitted `XEMU_FLASH`,
  `XEMU_MCPX`, `XEMU_EEPROM`, and `XEMU_HDD` from the shell environment.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `call_chain_trace_reaches_mark_executed_attempt`.

## Findings

- Result:
  - Podman-backed native build succeeded in `build-docker-b6-pfifo-boundary`.
  - The smoke command failed before emulation with `XEMU_FLASH is required`.
- Important marker/comparator lines:
  - Build completed through `[513/513] Linking target qemu-system-i386`.
  - Smoke preflight output: `XEMU_FLASH is required`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not measured; emulation did not start.

## Decision

- Status: failed run
- Why: build succeeded, but the runtime smoke omitted fixture environment
  values already documented in `AGENTS.md`.
- Independent critique used: no

## Next Step

- Narrow follow-up:
  rerun the same `XEMU_BOOT_TRACE_CALL_CHAIN=1` smoke with the documented
  fixture env values from `AGENTS.md` if continuing the explanatory call-chain
  experiment.
