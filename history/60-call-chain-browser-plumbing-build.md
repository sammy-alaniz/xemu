# Call Chain Browser Plumbing Build

## Purpose

- One new fact this step was supposed to produce:
  whether the browser/WASM runtime can receive the call-chain trace flag through
  the existing browser diagnostic fixture-file path instead of relying on a host
  environment variable.

## Command(s)

```sh
git diff --check -- ui/xemu-headless.c system/vl.c \
  accel/tcg/tcg-accel-ops.c accel/tcg/cpu-exec.c xemu-xbe.c \
  browser/xbox-boot/worker.js browser/xbox-boot/main.js \
  scripts/xbox-browser-runtime-smoke.sh \
  scripts/xbox-browser-runtime-firefox-bidi.mjs

PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh
```

## Inputs And Artifacts

- Source files updated:
  - `ui/xemu-headless.c`
  - `system/vl.c`
  - `accel/tcg/tcg-accel-ops.c`
  - `accel/tcg/cpu-exec.c`
  - `xemu-xbe.c`
  - `browser/xbox-boot/worker.js`
  - `browser/xbox-boot/main.js`
  - `scripts/xbox-browser-runtime-smoke.sh`
  - `scripts/xbox-browser-runtime-firefox-bidi.mjs`
- Build artifact:
  `build-wasm-pic/qemu-system-i386.js`

## Expected Field(s)

- Loop-guard field(s) this can explain:
  `browser_call_chain_markers_present`,
  specifically `browser_call_chain_reaches_mark_executed_attempt`.

## Findings

- `git diff --check` passed for the touched files.
- The WASM rebuild completed successfully and linked `qemu-system-i386.js`.
- The browser worker now writes `/xemu-fixtures/call_chain_trace.txt` from
  `traceOptions.callChainTrace`.
- The Playwright and Firefox BiDi runtime drivers now populate
  `traceOptions.callChainTrace` from `XEMU_BOOT_TRACE_CALL_CHAIN`.
- The C call-chain helpers now still honor `XEMU_BOOT_TRACE_CALL_CHAIN` in
  native mode and fall back to `call_chain_trace.txt` in browser/WASM mode.

## Decision

- Status: prerequisite support
- Why: this does not answer whether browser call-chain markers appear, but it
  removes the env-forwarding ambiguity identified by the loop check.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary:
  `history/59-call-chain-browser-runtime-loop-check.md` said the browser run is
  justified only after the flag is actually delivered into browser/WASM runtime.

## Next Step

- Narrow follow-up:
  run the browser runtime with `XEMU_BOOT_TRACE_CALL_CHAIN=1` and check whether
  `CALL_CHAIN` markers appear in the browser transcript, especially
  `xemu_xbe_boot_trace_observe_exec` and
  `xemu_xbe_boot_trace_mark_executed`.
