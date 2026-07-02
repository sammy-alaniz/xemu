# Browser Late PGRAPH Presence Static

## Purpose

- One new fact this run was supposed to produce: `browser_late_pgraph_notify_clear_presence`.

## Command(s)

```sh
rg -c "pgraph-notify-clear|notify-error-clear" \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

rg -c "pgraph-notify-clear|notify-error-clear" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

rg -n -m 20 "pgraph-notify-clear|notify-error-clear" \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

rg -n -m 20 "pgraph-notify-clear|notify-error-clear" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

rg -n -m 5 "^BOOT_MARK b6 dashboard=xbe-executed " \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: existing logs only.
- Fixture assumptions: static inspection only; no code change and no runtime.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  - `browser_late_pgraph_notify_clear_presence`

## Findings

- Result: `browser_late_pgraph_notify_clear_presence=early-present-late-wait-state-absent`.
- Native has 638 matches for `pgraph-notify-clear|notify-error-clear`.
- Browser has 8 matches for `pgraph-notify-clear|notify-error-clear`.
- Browser's 8 matches are exactly the early `BOOT_MARK b6 pgraph=notify-clear ... op=notify-error-clear` sequence:
  - line 1794: seq 1, `dma_get=0x03880524`, `dma_put=0x03881318`
  - line 1815: seq 2, `dma_get=0x03880558`, `dma_put=0x03881318`
  - line 1827: seq 3, `dma_get=0x0388056c`, `dma_put=0x03881318`
  - line 1839: seq 4, `dma_get=0x03880588`, `dma_put=0x03881318`
  - line 1854: seq 5, `dma_get=0x0388059c`, `dma_put=0x03881318`
  - line 1866: seq 6, `dma_get=0x038805b8`, `dma_put=0x03881318`
  - line 1878: seq 7, `dma_get=0x038805cc`, `dma_put=0x03881318`
  - line 1933: seq 8, `dma_get=0x03880e30`, `dma_put=0x03881318`
- Native has the same early notify-clear sequence, but continues far beyond it.
- Native later reaches the late handoff wait-state seen in the prior static entry:
  - line 6163: `dashboard=kernel-loop-probe ... start_pc=0x8001e374 next_pc=0x8001e374 ... nv2a_wait_source=pgraph-notify-clear nv2a_wait_op=notify-error-clear`
  - line 6178: `dashboard=xbe-executed ... guest_pc=0x00017d60 ... image_pc=0x00017d60 ... address_mode=direct ... phys_match=yes`
- Browser has no `dashboard=xbe-executed` match in the exact strict-marker query; native has the single strict marker at line 6178.
- Classification: the browser does not fail by missing all PGRAPH notify-clear handling. It matches the early sequence and then stops before the later native handoff regime where the wait snapshot itself reports `pgraph-notify-clear/notify-error-clear` and native exits to direct low XBE execution.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run.

## Decision

- Status: current
- Why: the next static boundary should explain what native keeps doing after the shared early notify-clear sequence that browser lacks before its later high-alias timeout loop.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/255-exact-pgraph-query-loop-check.md` required exact bounded marker count/list queries.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the prior loop check said exact queries keep the work aligned and prevent broad graphics/PFIFO exploration.
- If yes, process adjustment for next 2-3 turns: compare the post-early-notify-clear command-stream/state transition, not all graphics behavior.

## Next Step

- Narrow follow-up: run the required post-history loop check. Ask whether the next field should be `post_early_notify_clear_native_continuation_absent_in_browser` or an existing focused helper such as `scripts/xbox-pgraph-command-stream-compare.py` against the stable native/browser logs.
