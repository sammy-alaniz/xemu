# 324 - pcrtc final-window BQL ownership patch

## Purpose

- One new fact this patch was supposed to produce: whether the final-window
  PCRTC IRQ delivery path can be changed from PFIFO-thread-without-BQL to the
  local BQL-safe ownership pattern without changing final-window gate
  semantics.

## Command(s)

```sh
# manual edit via apply_patch
```

## Inputs And Artifacts

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log:
  code patch only; no runtime output
- Fixture assumptions: no fixtures used.

## Expected Field(s)

- Loop-guard field(s) this patch could change or explain:
  `pcrtc_final_window_irq_delivery_ownership`

## Findings

- Result:
  `hw/xbox/nv2a/pfifo.c` now identifies the one-word final-window candidate at
  the PCRTC pre-stream call site and delivers that candidate using the local
  PFIFO diagnostic ownership pattern: release `d->pfifo.lock`, take BQL, call
  `nv2a_browser_deterministic_pcrtc_prestream_maybe_raise()`, release BQL, and
  re-lock `d->pfifo.lock`.
- Important marker/comparator lines:
  - The final-window predicate remains the same as the helper's allow shape:
    `dma_get_before != dma_get_after`, `dma_get_after == dma_put`,
    pending bytes equal 4, `available == 1`, and `processed == 1`.
  - Non-final blocked marker calls remain on the existing direct path because
    they cannot assert the diagnostic PCRTC IRQ.
  - The patch does not tune PFIFO windows, pump counts, PCRTC modes, timer
    limits, or dashboard execution detection.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; this was a code patch only.

## Decision

- Status: current
- Why:
  The patch targets only `pcrtc_final_window_irq_delivery_ownership`. It should
  be followed by build/static verification, not runtime probing, until a loop
  check approves the next step.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  `history/323-pcrtc-final-window-bql-ownership-loop-check.md` approved exactly
  this scoped code change and build/static verification afterward.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary:
  The prior critique said this code-correction step is still on the causal
  path to browser pre-stream service and strict `dashboard=xbe-executed`, and
  that no runtime should run until the patched ownership path is recorded and
  loop-checked.
- If yes, process adjustment for next 2-3 turns:
  Continue naming only the exact lock/BQL ownership field being changed or
  verified. Do not run browser/native runtime before build/static verification
  and the next loop check.

## Next Step

- Narrow follow-up: run the required loop check with progress-method critique.
  If approved, run build/static verification for
  `pcrtc_final_window_irq_delivery_ownership`.
