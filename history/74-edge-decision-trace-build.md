# Edge Decision Trace Build

## Purpose

- One new fact this run was supposed to produce: whether the bounded pre-TB
  `edge-decision` marker can compile in the browser/WASM build.

## Command(s)

```sh
rg -n "mem_kind =|mem_region =|xemu_xbe_decode_memory_probe" xemu-xbe.c
git diff --check
python3 -m py_compile scripts/xbox-post-service-edge-decision-compare.py
node --check scripts/xbox-browser-runtime-firefox-bidi.mjs
node --check browser/xbox-boot/main.js
node --check browser/xbox-boot/worker.js
bash -n scripts/xbox-browser-runtime-smoke.sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin XEMU_WASM_SKIP_IMAGE_BUILD=1 XEMU_WASM_BUILD_DIR=build-wasm-pic XEMU_WASM_JOBS=4 scripts/docker-build-xemu-wasm.sh
```

## Inputs And Artifacts

- Baseline native log: none.
- Baseline browser log: none.
- Output directory/log: rebuilt `build-wasm-pic/qemu-system-i386.js`.
- Fixture assumptions: no runtime fixtures used; this was a compile/build
  validation.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `browser_post_service_top_edge`.

## Findings

- Result: static checks passed and podman WASM build passed.
- Important marker/comparator lines:
  - Added opt-in `BOOT_MARK b6 edge-decision` marker around `cpu_loop_exec_tb`
    for bounded post-idle `pc==0x80030e84` hits.
  - Added browser fixture plumbing for
    `XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT` /
    `xbe_edge_decision_limit.txt`.
  - Build linked `qemu-system-i386.js`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not remeasured; no emulation run was started.

## Decision

- Status: current
- Why: the trace compiles and can now be used for a focused browser runtime
  experiment.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: history/73 required the marker to capture pre-TB
  GPRs/eflags for a few post-idle `0x80030e84` hits; the implementation follows
  that direction and remains opt-in.

## Next Step

- Narrow follow-up: run the required loop-check, then run a focused browser
  runtime with `XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4` to populate
  `edge-decision` markers and explain `browser_post_service_top_edge`.
