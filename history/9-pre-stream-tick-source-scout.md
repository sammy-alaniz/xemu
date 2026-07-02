# Pre-Stream Tick Source Scout

## Purpose

- One new fact this probe was supposed to produce: whether existing native/browser logs visibly support the hypothesis that native accumulates the `0x0003a890` tick word through earlier PIT/vector `0x30` service before PFIFO stream-idle, while the browser baseline waits until the ready-edge path and reaches the first watched read at zero ticks.

## Command(s)

```sh
rg -n "pit=irq-timer|cpu=hard-irq-service|pfifo=stream-idle-transition|main-loop=timers|memory-watch|dashboard=kernel-loop-probe" \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log | sed -n '1,80p'
```

## Inputs And Artifacts

- Native baseline: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Browser baseline: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output: command stdout only; the tool view was truncated because matching kernel-loop lines are very large.
- Fixture assumptions: already-captured local B6 real-fixture logs.

## Expected Field(s)

- Loop-guard field(s) this probe could explain: `pre_service_browser_first_watch_read_ticks` and the pre-stream timing split behind the browser `0` ticks versus native `136` ticks gap.

## Findings

- Result: diagnostic scout only; the output is not narrow enough to count as final evidence.
- Visible native lines show PIT `irq_level=1` and `main-loop=timers timer_progress=yes` well before the stream-idle boundary, including native line `991` PIT activity at `eip=0x800143c8` and native line `994` timer progress that leaves `cpu_interrupt_request=0x00000002`.
- The native excerpt also shows continued pre-stream timer/PIT activity around lines `1015`, `1017`, `1028`, and `1029`, while the broad browser excerpt is dominated by pre-stream kernel-loop samples and does not provide a concise comparable count.
- The scout reinforces the current hypothesis, but the output shape is too noisy and was truncated, so the next step must be a narrow parser instead of another broad `rg`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No new emulation run was performed, so artifact status did not change. The front-most browser baseline remains `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`.

## Decision

- Status: historical support
- Why: useful enough to justify a narrow comparator, but not auditable enough to steer implementation alone.
- Independent critique used: no

## Next Step

- Add a focused pre-stream tick-source comparator that counts pre-stream PIT rising edges, main-loop timer progress, PIC vector `0x30` acknowledgements, vector `0x30` service entries, IRET returns, and watched-word samples for native versus browser.
