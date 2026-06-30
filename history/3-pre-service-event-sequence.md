# Pre-Service Event Sequence

## Purpose

- One new fact this run was supposed to produce: whether the browser first watched read of physical `0x0003a890` happens before or after the first IRQ service, first watched write, and first IRET after PFIFO stream-idle.

## Command(s)

```sh
sed -n '2485,2540p' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

sed -n '3748,3770p' build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: command stdout only
- Fixture assumptions: existing local B6 real fixtures and already-captured native/browser logs

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `pre_service_browser_first_watch_read_ticks` and `browser_post_service_top_edge`.

## Findings

- Result: diagnostic comparator still passes with `divergence=browser-first-watch-read-before-catchup`.
- Browser first watched read remains at tick `0` on `0x80014f32->0x80030e84`.
- Browser first IRQ service starts before the first watched read: service line `2500`, read line `2511`.
- Browser first watched write happens after the first watched read: write line `2517`, delta from read `6`, `eip=0x80030e84`, pre-access value `0x00000000`.
- Browser first IRET after service is later still: line `2533`, `eip=0x80030f31`.
- Native is already at tick `136` before the analogous first watched read on `0x80014f5f->0x80030e84`; native does not need an additional post-read write to explain that first read value.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not tested by this excerpt/comparator probe; it only explains ordering in existing logs.

## Decision

- Status: current
- Why: the browser is behind before the first watched read, not merely inside the later `0x80030e84->0x80030f31` arithmetic block.
- Independent critique used: no

## Next Step

- Narrow follow-up: make the boundary helper surface the first timer/read/write/service/IRET ordering fields so future run summaries can reject broad pump loops without re-reading raw logs.
