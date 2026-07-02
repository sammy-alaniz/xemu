# Pre First Read TCG Tick Block PC Build

## Purpose

- One new fact this code/build step was supposed to produce:
  `pre_first_read_tcg_checkpoint_pc_allowed`, specifically whether the opt-in
  `pit-post-pfifo-pre-first-read` readiness path can now pass at the audited
  pre-read/tick-block PC `0x80030e84` while preserving the existing safety
  gates.

## Command(s)

```sh
apply_patch <<'PATCH'
# Add xemu_xbe_exec_context_is_post_pfifo_pre_first_read_serviceable().
# It keeps protected32 CPL0, IF set, no HF_INHIBIT_IRQ_MASK, and no pending
# interrupt, but accepts either 0x8001b030 or XEMU_XBE_TICK_BLOCK_PC
# (0x80030e84) for this one opt-in TCG mode.
PATCH

git diff --check -- xemu-xbe.c
sed -n '1438,1545p' xemu-xbe.c
git diff -- xemu-xbe.c

PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh
```

## Inputs And Artifacts

- Source changed: `xemu-xbe.c`
- Build artifact:
  `build-wasm-pic/qemu-system-i386.js`
- Prior audit:
  `history/124-pre-first-read-tcg-gate-audit.md`
- Prior loop check:
  `history/125-pre-first-read-tcg-gate-loop-check.md`
- Fixture assumptions: build only; no browser runtime started.

## Expected Field(s)

- Loop-guard field(s) this code/build step could change or explain:
  `pre_first_read_tcg_checkpoint_pc_allowed`.

## Findings

- Result: the readiness path now has a mode-specific serviceability helper,
  `xemu_xbe_exec_context_is_post_pfifo_pre_first_read_serviceable()`.
- The helper keeps the existing CPU safety gates:
  protected32, CPL0, IF set, no `HF_INHIBIT_IRQ_MASK`, and
  `cpu_interrupt_request == 0`.
- The helper accepts `XEMU_XBE_TCG_TIMER_PUMP_IDLE_LOOP_PC_2`
  (`0x8001b030`) or `XEMU_XBE_TICK_BLOCK_PC` (`0x80030e84`).
- Only `xemu_xbe_tcg_timer_pump_post_pfifo_pre_first_read_ready()` was changed
  to use this helper. The older idle-loop readiness helper still requires
  `0x8001b030`.
- The mode still requires the existing non-CPU guards: positive limit,
  delivery attempts below limit, PFIFO stream-idle transition observed, no
  `tick-block=complete`, no `edge-decision`, current wait state PFIFO-empty,
  and virtual timers present/expired.
- The change does not mutate `interrupt_request`, `exit_request`, or icount.
- `git diff --check -- xemu-xbe.c` passed.
- Podman WASM build passed and relinked `qemu-system-i386.js`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not measured. This was a code/build step only.

## Decision

- Status: current code candidate.
- Why: the code now implements the one predicate change approved by
  `history/125`, is opt-in to `pit-post-pfifo-pre-first-read`, and builds.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: the prior critique approved changing only the
  `pc == 0x80030e84` predicate for this TCG mode while preserving all safety
  gates, then building before any browser validation.

## Progress-Method Critique

- This is a direct movement toward strict browser dashboard execution because
  it addresses the exact closed predicate that prevented the TCG checkpoint
  from running before the first watched read.
- The work is now less diagnostic-heavy than the previous turn because it
  converts the audit finding into a scoped code candidate.
- The history/loop-check process helped avoid a blind rerun and forced the
  change to stay narrow.
- Process adjustment for the next 2-3 turns: validate this code candidate with
  exactly one browser runtime only if the required loop check approves, and
  judge it first on `tcg=timer-pump mode=pit-post-pfifo-pre-first-read` at
  `eip=0x80030e84`, then `browser_first_watch_read_ticks`, post-service edge
  preservation, and strict B6.

## Next Step

- Narrow follow-up: run the required loop check. If approved, perform one
  browser runtime validation of the updated opt-in TCG mode.
