# Deferred DMA PUT Observer Design Static

## Purpose

- One new fact this run was supposed to produce: `deferred_dma_put_observer_design_safe_enough`.

## Command(s)

```sh
# Static design step only. No shell command, code edit, or runtime.
```

## Inputs And Artifacts

- Current marker implementation: `hw/xbox/nv2a/user.c`
- Prior safety review: `history/266-dma-put-observability-safety-static.md`
- Prior loop check: `history/267-deferred-dma-put-design-loop-check.md`
- Fixture assumptions: static design only; no code change and no runtime.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  - `deferred_dma_put_observer_design_safe_enough`

## Findings

- Result: `deferred_dma_put_observer_design_safe_enough=conditional-only-with-preinit-cheap-snapshot-deferred-emission-and-preservation-gate`.
- A simple fixture/env plumbing change is not safe enough.
- The current `user_boot_trace_dma_put()` call site is unsafe because it does expensive work between the guest's `DMA_PUT` write and `pfifo_kick_with_source()` while `d->pfifo.lock` is held.
- Minimal safe-enough code shape:
  - Keep the observer opt-in and default off for native and browser.
  - Pre-initialize observer config before guest execution or before the first observed hot-path write; no env/file reads in `user_write()`.
  - In `user_write()`, under `pfifo.lock`, only:
    - set `NV_PFIFO_CACHE1_DMA_PUT`,
    - copy a small fixed-size snapshot if the cached observer config is enabled and the hard cap has not been reached,
    - avoid CPU capture,
    - avoid XBE helper calls,
    - avoid context/file/env lookup,
    - avoid `fprintf`,
    - avoid dynamic allocation,
    - then call `pfifo_kick_with_source("nv-user-dma-put")`.
  - Release `pfifo.lock` before emitting any line.
  - Emit a short capped marker outside the lock, after the PFIFO kick has been broadcast.
  - Marker fields should be limited to publication facts:
    - sequence,
    - channel/current channel,
    - offset/size/raw value,
    - `dma_get`,
    - `old_dma_put`,
    - `new_dma_put`,
    - `old_dma_to_put`,
    - `new_dma_to_put`.
  - Do not include CPU state, EFLAGS, XBE loaded flags, entry flags, dashboard flags, or executed flags in the first safe observer.
- Future runtime preservation gate before interpreting PUT fields:
  - B4/B5/read/load/entry-ready/section-map must still pass.
  - Strict B6 may still fail at `missing-xbe-executed-marker`, but no weaker success contract is allowed.
  - The stable post-service watch edge must still be present.
  - Pre-service tick gap and post-service edge comparators must preserve the stable shape closely enough for causal interpretation.
  - If preservation fails like `history/206`, PUT fields must not be interpreted causally.
- Design conclusion:
  - The observer can be made safe enough in principle, but only with a redesign.
  - Current marker plus fixture plumbing remains rejected.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run.

## Decision

- Status: current
- Why: if the next loop check approves code work, implement only the minimal deferred observer design. Do not re-enable the current marker as-is and do not broaden into CPU-flow or graphics work before resolving PUT publication observability.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/267-deferred-dma-put-design-loop-check.md` required this static design before any observer code or runtime.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the prior loop check said the work remains connected to strict dashboard execution but is very diagnostic-heavy; this design narrows any future code to one necessary missing fact.
- If yes, process adjustment for next 2-3 turns: any code change must be minimal, default-off, deferred, capped, and followed by build-only verification before a runtime is considered.

## Next Step

- Narrow follow-up: run the required post-history loop check. Ask whether to implement the minimal deferred observer design as code, or revise/stop because even deferred emission is too perturbing.
