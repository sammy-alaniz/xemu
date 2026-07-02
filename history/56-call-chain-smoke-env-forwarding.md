# Call Chain Smoke Env Forwarding

## Purpose

- One new fact this run was supposed to produce:
  whether the rebuilt Podman-backed native smoke emits
  `XEMU_BOOT_TRACE_CALL_CHAIN=1` one-shot call-chain markers.

## Command(s)

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_MCPX='/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin' \
XEMU_FLASH='/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin' \
XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin \
XEMU_HDD='/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
XEMU_SMOKE_BUILD_DIR=build-docker-b6-pfifo-boundary \
XEMU_SMOKE_OUT_DIR=build-real-b3-matrix/call-chain-trace-v1 \
XEMU_HEADLESS_BOOT_MS=30000 \
XEMU_BOOT_TRACE=1 \
XEMU_BOOT_TRACE_CALL_CHAIN=1 \
scripts/xbox-boot-smoke.sh docker-headless

rg -n '^CALL_CHAIN' build-real-b3-matrix/call-chain-trace-v1/boot-smoke.log
rg -n 'dashboard=xbe-(read|loaded|entry-probe|executed)|BOOT_SMOKE_RESULT' \
  build-real-b3-matrix/call-chain-trace-v1/boot-smoke.log | head -80
```

## Inputs And Artifacts

- Baseline native log: not used.
- Baseline browser log: not used.
- Output directory/log:
  `build-real-b3-matrix/call-chain-trace-v1/boot-smoke.log`.
- Fixture assumptions: documented local real fixtures from `AGENTS.md`.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `call_chain_trace_reaches_mark_executed_attempt`.

## Findings

- Result:
  - The smoke ran successfully and timed out cleanly after about 3 seconds.
  - The log contains native-headless dashboard read/load/entry-ready markers and
    exec-probe diagnostics.
  - `rg '^CALL_CHAIN'` found no call-chain markers.
- Important marker/comparator lines:
  - `BOOT_SMOKE_SUMMARY result=pass mode=docker-headless level=B6 expected=B0 exit=0`
  - `BOOT_SMOKE_RESULT reason=timeout elapsed_ms=3009 exit=0`
  - `BOOT_MARK b6 dashboard=xbe-loaded context=native-headless ...`
  - `BOOT_MARK b6 dashboard=xbe-entry-probe context=native-headless status=ready ...`
- Root cause:
  `scripts/xbox-boot-smoke.sh` forwards a fixed allowlist of diagnostic
  environment variables into `docker run`; `XEMU_BOOT_TRACE_CALL_CHAIN` is not
  in that allowlist, so the rebuilt binary never saw the opt-in flag.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not evaluated as a B6/browser baseline. This was a native-headless
  explanatory call-chain smoke only.

## Decision

- Status: failed run
- Why: the runtime executed, but the intended call-chain flag was not delivered
  to the process under test.
- Independent critique used: no

## Next Step

- Narrow follow-up:
  rerun the same rebuilt binary through Podman with
  `-e XEMU_BOOT_TRACE_CALL_CHAIN=1` explicitly passed, or add that env var to
  the smoke wrapper allowlist before rerunning.
