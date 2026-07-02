# Call Chain Direct Podman Smoke

## Purpose

- One new fact this run was supposed to produce:
  whether the rebuilt native binary emits the env-gated broad call-chain trace
  when `XEMU_BOOT_TRACE_CALL_CHAIN=1` is explicitly passed into the Podman
  container.

## Command(s)

```sh
mkdir -p build-real-b3-matrix/call-chain-trace-v2

PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
docker run --rm -t \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp/xemu-home \
  -e XEMU_HEADLESS_BOOT=1 \
  -e XEMU_BOOT_TRACE=1 \
  -e XEMU_BOOT_TRACE_CONTEXT=native-headless \
  -e XEMU_HEADLESS_BOOT_MS=30000 \
  -e XEMU_BOOT_TRACE_CALL_CHAIN=1 \
  -v "/home/sammy/Downloads/xemu/xemu:/workspace" \
  -v "/home/sammy/Downloads/xemu/xemu/build-real-b3-matrix/call-chain-trace-v1:/xemu-smoke-out:ro" \
  -v "/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin:/xemu-fixtures/flash.bin:ro" \
  -v "/tmp/xemu-b6-eeprom.bin:/xemu-fixtures/eeprom.bin" \
  -v "/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin:/xemu-fixtures/mcpx.bin:ro" \
  -v "/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2:/xemu-fixtures/xbox_hdd.img" \
  -w "/workspace/build-docker-b6-pfifo-boundary" \
  xemu-native-build:latest \
  ./qemu-system-i386 -config_path /xemu-smoke-out/xemu-smoke.toml \
  > build-real-b3-matrix/call-chain-trace-v2/boot-smoke.log 2>&1

rg -n '^CALL_CHAIN' build-real-b3-matrix/call-chain-trace-v2/boot-smoke.log
rg -n 'dashboard=xbe-(loaded|entry-probe|executed|exec-probe|exec-section-miss)|BOOT_SMOKE_RESULT|runstate=main-loop' \
  build-real-b3-matrix/call-chain-trace-v2/boot-smoke.log | head -80
```

## Inputs And Artifacts

- Baseline native log: not used.
- Baseline browser log: not used.
- Output directory/log:
  `build-real-b3-matrix/call-chain-trace-v2/boot-smoke.log`.
- Fixture assumptions: documented local real fixtures from `AGENTS.md`.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `call_chain_trace_reaches_mark_executed_attempt`.

## Findings

- Result: pass for the explanatory call-chain experiment.
- Important marker/comparator lines:
  - `CALL_CHAIN started qemu_init!`
  - `CALL_CHAIN started qemu_init_board!`
  - `CALL_CHAIN started machine/device/CPU setup!`
  - `CALL_CHAIN ended machine/device/CPU setup!`
  - `CALL_CHAIN ended qemu_init_board!`
  - `CALL_CHAIN ended qemu_init!`
  - `CALL_CHAIN started TCG vCPU execution loop!`
  - `CALL_CHAIN started tcg_cpu_exec!`
  - `CALL_CHAIN started cpu_exec!`
  - `CALL_CHAIN started cpu_exec_loop!`
  - `CALL_CHAIN started cpu_loop_exec_tb!`
  - `CALL_CHAIN started xemu_xbe_boot_trace_observe_exec!`
  - `CALL_CHAIN started xemu_xbe_boot_trace_mark_executed!`
  - `CALL_CHAIN ended xemu_xbe_boot_trace_mark_executed!`
  - `BOOT_MARK b6 dashboard=xbe-loaded context=native-headless ...`
  - `BOOT_MARK b6 dashboard=xbe-entry-probe context=native-headless status=ready ...`
  - `BOOT_MARK b6 dashboard=xbe-exec-section-miss context=native-headless reason=high-alias-phys-mismatch ...`
  - `BOOT_SMOKE_RESULT reason=timeout elapsed_ms=30019 exit=0`
- The first `mark_executed` call happened after native-headless
  `dashboard=xbe-loaded` but before entry was readable, and it returned through
  an exec-section-miss path. Later exec probes continued to show high-alias
  physical mismatches rather than strict `dashboard=xbe-executed`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not evaluated as a browser B6 baseline. This was a native-headless
  explanatory call-chain smoke only.

## Decision

- Status: historical support
- Why: it proves the requested broad call-chain trace works when the env var is
  actually delivered into the runtime container. It is not B6 completion
  evidence and does not move the browser tick metric.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  `history/57-call-chain-env-forwarding-loop-check.md` allowed this corrected
  call-chain run only for `call_chain_trace_reaches_mark_executed_attempt`; it
  reiterated that the better B6-focused experiment remains the source-tagged
  PFIFO scheduler run for `first_kick_after_last_opportunity_source`.

## Next Step

- Narrow follow-up:
  keep this as explanatory support for the call path. Return to the B6-focused
  source-tagged PFIFO scheduler path when continuing dashboard-loaded work.
