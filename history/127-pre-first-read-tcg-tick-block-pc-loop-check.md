# Pre First Read TCG Tick Block PC Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce:
  whether the code/build step in `history/126` justifies exactly one browser
  runtime validation.

## Command(s)

```text
Reused read-only sub-agent 019f1e51-23ca-7e93-978c-89e48eb1dc60 with this checkpoint:

Required post-history B6 loop check. Read goal.md, AGENTS.md, and
history/126-pre-first-read-tcg-tick-block-pc-build.md only as needed. Do not
edit files. Context: the approved code change added a mode-specific
serviceability helper for pit-post-pfifo-pre-first-read. It keeps protected32
CPL0, IF set, no HF_INHIBIT_IRQ_MASK, no pending interrupt, and all existing
non-CPU gates: positive limit, attempts below limit, PFIFO stream-idle
observed, current PFIFO-empty wait, no tick-block complete, no edge-decision,
and virtual timers present/expired. The only predicate expansion is accepting
pc == 0x80030e84 (XEMU_XBE_TICK_BLOCK_PC) in addition to 0x8001b030 for this
one opt-in mode. No interrupt state mutation was added. git diff --check passed
and podman WASM build passed/relinked qemu-system-i386.js. Proposed next
action: exactly one browser runtime validation using a new v2 artifact, judged
in order by tcg=timer-pump mode=pit-post-pfifo-pre-first-read at eip=0x80030e84,
browser_first_watch_read_ticks, browser_post_service_top_edge/post-service edge
preservation, B4/B5/read/load/entry-ready/section-map, and strict B6. Answer the
standard loop-check questions, include the required Progress-Method Critique,
and end with one decision.
```

## Inputs And Artifacts

- Code/build summary:
  `history/126-pre-first-read-tcg-tick-block-pc-build.md`
- Fixture assumptions: read-only critique; no runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `pre_first_read_tcg_checkpoint_active`, `browser_first_watch_read_ticks`, and
  `browser_post_service_top_edge`.

## Findings

- Result: critique decision was `continue`.
- It said we are not looping because the previous failed runtime had a named
  blocker and `history/126` changed exactly that predicate.
- It identified the narrowest next fact as whether the revised mode emits
  `BOOT_MARK b6 tcg=timer-pump mode=pit-post-pfifo-pre-first-read` at
  `eip=0x80030e84` before the first watched read.
- It killed idle-loop-PC-only readiness for this mode.
- It kept TCG-owned PIT delivery plus normal CPU interrupt handling, with no
  manual interrupt, `exit_request`, or icount mutation.
- It revised the checkpoint hypothesis to: the tick-block PC can be a safe
  pre-read pump point under the existing no-pending/no-inhibit/PFIFO-empty,
  no-edge/no-tick/expired-timer gates.
- It approved exactly one browser runtime validation.
- It said no better experiment is needed before this validation because the
  build already passed and more static inspection would not answer whether the
  runtime gate now opens.

## Decision

- Status: current.
- Why: the required critique approves one runtime that tests the changed
  predicate instead of rerunning the prior closed gate.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: judge the `v2` run first on checkpoint marker
  presence at `0x80030e84`, then `browser_first_watch_read_ticks`, then
  post-service edge preservation.

## Progress-Method Critique

- The critique said the method still moves toward strict dashboard execution
  because it targets the pre-first-read tick gap blocking browser-runtime
  `dashboard=xbe-executed`; visible main-menu proof and game launch remain
  downstream.
- It said the work is diagnostic-heavy, but this step is not rerun-heavy
  because the predicate changed after a concrete audit.
- It said the history and loop checks are helping the next 2-3 turns by forcing
  a single-field validation instead of broad scheduler churn.
- It said runtime probing is the right next mode now.
- Process adjustment: after the `v2` run, do not tweak this mode again unless
  the history names the first failing predicate or shows improved ticks with an
  edge-preservation regression to explain.

## Next Step

- Narrow follow-up: run one browser runtime validation into a new
  `browser-tcg-post-pfifo-pre-first-read-v2` artifact and reduce it in the
  approved order.
