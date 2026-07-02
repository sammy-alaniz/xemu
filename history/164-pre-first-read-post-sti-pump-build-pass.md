# Pre-First-Read Post-STI Pump Build Pass

## Purpose

- One new fact this run was supposed to produce: whether the exact post-STI first-read predecessor timer-pump patch compiles and links in the browser/WASM build.

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
- Restored-boundary browser log: `build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log`
- Output directory/log: `build-wasm-pic`, linked target `qemu-system-i386.js`
- Fixture assumptions: podman escalation is required for browser/WASM build access in this environment.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `post_sti_first_read_predecessor_timer_pump_buildable`.

## Findings

- Result: pass.
- `git diff --check -- xemu-xbe.c` produced no output.
- The escalated podman build completed and linked `qemu-system-i386.js`.
- The patch keeps broad IRQ-inhibited states rejected.
- The patch special-cases only `XEMU_XBE_FIRST_READ_PREDECESSOR_PC_BROWSER` (`0x80014f32`) when IF is set, `HF_INHIBIT_IRQ_MASK` is set, and no interrupt is already pending.
- The patch keeps broadening to `0x80014f3d` rejected.
- The gate marker now emits only after entry-ready and only when PFIFO stream-idle has been observed or the PC is one of the exact scheduler candidate PCs.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not tested; this was compile/link verification only.

## Decision

- Status: current
- Why: build verification passed, so the next decision is whether one runtime validation is justified for `post_sti_first_read_predecessor_timer_pump`.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/163` approved this exact code change and no broader predicate expansion.

## Next Step

- Narrow follow-up: run the required loop check before any runtime validation. The proposed runtime must be judged first on whether the scheduler starts at or near `0x80014f32`, whether TCG timer-pump markers appear, and whether the first watched read moves from 0 ticks.
