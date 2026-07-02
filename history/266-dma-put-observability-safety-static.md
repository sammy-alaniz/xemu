# DMA PUT Observability Safety Static

## Purpose

- One new fact this run was supposed to produce: `dma_put_publication_observability_safe_path`.

## Command(s)

```sh
find history -maxdepth 1 -type f -name '206*.md' -o -name '208*.md' -o -name '210*.md' | sort -V

# These initial guessed names failed and produced no useful content:
sed -n '1,220p' history/206-dma-put-marker-runtime.md
sed -n '1,220p' history/208-dma-put-marker-quarantine-build.md
sed -n '1,220p' history/210-dma-put-marker-quarantine-loop-check.md

sed -n '1,240p' history/206-dma-put-runtime-preservation-regressed.md
sed -n '1,240p' history/208-dma-put-marker-perturbation-review.md
sed -n '1,260p' history/210-dma-put-marker-quarantine-build.md
sed -n '181,370p' hw/xbox/nv2a/user.c
git diff -- hw/xbox/nv2a/user.c browser/xbox-boot/main.js browser/xbox-boot/worker.js scripts/xbox-browser-runtime-smoke.sh | sed -n '1,260p'

sed -n '1,180p' hw/xbox/nv2a/user.c
rg -n "XEMU_BOOT_TRACE_NV2A_USER|user_dma_put|nv2a=user-dma-put|user_boot_trace_dma_put" \
  AGENTS.md goal.md scripts browser hw/xbox/nv2a/user.c
```

## Inputs And Artifacts

- Prior negative history:
  - `history/206-dma-put-runtime-preservation-regressed.md`
  - `history/208-dma-put-marker-perturbation-review.md`
  - `history/210-dma-put-marker-quarantine-build.md`
- Source inspected: `hw/xbox/nv2a/user.c`
- Diff context inspected for browser fixture plumbing and marker state.
- Fixture assumptions: static inspection only; no code change and no runtime.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  - `dma_put_publication_observability_safe_path`

## Findings

- Result: `dma_put_publication_observability_safe_path=current-marker-unsafe-defer-or-redesign-before-runtime`.
- Prior runtime result:
  - `history/206` passed broad B4/B5/read/load/entry-ready/section-map gates but failed to preserve the stable post-service watch edge.
  - It classified the DMA_PUT marker artifact as shape-regressed for marker causality.
- Prior source review:
  - `history/208` classified `dma_put_marker_perturbation_risk=high`.
  - The risk was specifically that the marker runs after guest `DMA_PUT` publication but before `pfifo_kick_with_source()`, while holding `d->pfifo.lock`.
  - The marker may initialize context, check environment/fixture state, call XBE trace helpers, capture CPU state, compute EFLAGS, and synchronously `fprintf` a long line.
- Quarantine:
  - `history/210` set `XEMU_NV2A_USER_DMA_PUT_TRACE_DEFAULT_LIMIT` to `0` and build-only verification passed.
- Current source still has the same high-risk placement:
  - `d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUT] = val;`
  - `user_boot_trace_dma_put(...);`
  - `pfifo_kick_with_source(d, "nv-user-dma-put");`
- Current source still has the quarantine:
  - `#define XEMU_NV2A_USER_DMA_PUT_TRACE_DEFAULT_LIMIT 0`
- No browser fixture plumbing was found for `XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT`.
- Static safety decision:
  - Do not re-enable the current marker as-is.
  - A safe-enough observation path must not do env/file init, CPU capture, XBE helper calls, or long `fprintf` while holding `pfifo.lock` before the kick.
  - The least risky design would split observation into a cheap snapshot of `old_dma_put`, `new_dma_put`, `dma_get`, channel, offset, size, and raw value, then emit after `pfifo_kick_with_source()` and after releasing `pfifo.lock`.
  - Even deferred emission can perturb CPU scheduling, so it should be sharply filtered or capped and must preserve the ready-edge host4 shape before any causal interpretation.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run.

## Decision

- Status: current
- Why: current marker use is unsafe for the next runtime. The next step should be a critique/loop decision on whether to implement a deferred minimal PUT observer, find an existing non-perturbing artifact, or return to CPU/tick flow without PUT marker runtime.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: `history/265-dma-put-observability-revise-loop-check.md` rejected immediate plumbing/runtime and required this static safety decision.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the prior loop check said the method remains connected to strict dashboard execution but re-enabling a high-risk marker would make the work too diagnostic-heavy.
- If yes, process adjustment for next 2-3 turns: no PUT marker runtime until the observer is redesigned or explicitly rejected by critique.

## Next Step

- Narrow follow-up: run the required post-history loop check. Ask whether the next field should be `deferred_dma_put_observer_design_safe_enough`, or whether to avoid PUT runtime and inspect guest CPU flow that should submit the later PUT.
