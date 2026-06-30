# Pre-Stream Native Tick Accumulation Probe

## Purpose

- One new fact this probe was supposed to produce: whether native reaches the first watched read of physical `0x0003a890` with `136` ticks already accumulated because native has earlier PIT/vector `0x30` service before the PFIFO stream-idle boundary, while the browser path only asserts the useful IRQ at the ready edge after the watched word is still zero.

## Command(s)

```sh
rg -n "main-loop=timers|pit=irq-timer|pic=irq-ack|pic=irq-line|cpu=hard-irq|cpu=hard-irq-service|cpu=iret|dashboard=kernel-loop-probe|memory-watch" \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log | sed -n '1,260p'

rg -n "main-loop=timers|pit=irq-timer|pic=irq-ack|pic=irq-line|cpu=hard-irq|cpu=hard-irq-service|cpu=iret|dashboard=kernel-loop-probe|memory-watch" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log | sed -n '1,260p'

scripts/xbox-pfifo-transition-irq-timing.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

scripts/xbox-post-idle-interrupt-flow-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

## Inputs And Artifacts

- Native baseline: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Browser baseline: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output: command stdout only
- Fixture assumptions: already-captured local B6 real-fixture logs

## Expected Field(s)

- Loop-guard field(s) this probe could explain: `pre_service_browser_first_watch_read_ticks`, `browser_post_service_top_edge`, and the timing split around PFIFO stream-idle.

## Findings

- Result: diagnostic probe only; the broad `rg` output was too noisy and was truncated in the tool view, so this should not be treated as complete machine-readable evidence.
- Visible native lines show PIT/PIC/hard-IRQ activity well before PFIFO stream-idle, including PIT toggles around `eip=0x800143c8`, a hard IRQ set shortly after, and `main-loop=timers` progress before the current stream-idle boundary.
- Visible native lines also show earlier vector `0x30` service/IRET cycles returning through the known handler path around `0x80030e4c`, before the later first watched read that has `ticks=136`.
- This supports, but does not yet prove with a narrow comparator, the current hypothesis: native accumulated watched-word ticks through pre-stream periodic timer/interrupt service, while the browser baseline first reaches the comparable watched read with `ticks=0`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No new run was performed, so this probe did not change artifact status. The current front-most browser baseline remains `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`.

## Decision

- Status: explanatory lead, not proof
- Why: hand-scanned broad output gives a plausible source for the 136-tick gap, but the output shape is not auditable enough to steer the next implementation by itself.
- Independent critique used: no

## Next Step

- Add or extend a narrow parser that counts pre-stream PIT/vector `0x30` service, IRET, timer-progress, and watched-word samples for native and browser, then emits a single pass/fail line explaining whether the browser lacks native-like pre-stream tick service.
