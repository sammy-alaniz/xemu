# 309 - deterministic PCRTC v2 helper reduction

## Purpose

Reduce the post-patch deterministic PCRTC v2 artifact with existing helpers only.
The primary fields were `browser_pre_stream_vector_service_state` and
`pre_service_browser_first_watch_read_ticks`, while preserving B4/B5/read/load/
entry-ready/section-map as gates.

## Exact commands

```sh
scripts/xbox-combine-dashboard-xbe-read-evidence.sh --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' --log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2/browser-runtime.log --out build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2-combined.log --require-context browser-runtime
```

```sh
scripts/xbox-browser-runtime-evidence-check.sh build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2/browser-runtime.log
scripts/xbox-display-capture-evidence-check.sh build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2/browser-runtime.log
scripts/xbox-dashboard-section-map-evidence-check.sh --require-context browser-runtime build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2-combined.log
scripts/xbox-dashboard-loaded-evidence-check.sh build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2-combined.log
scripts/xbox-pre-service-tick-gap-compare.py --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2-combined.log
scripts/xbox-post-service-watch-edge-compare.py --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2-combined.log
scripts/xbox-post-service-memory-poll-compare.py --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2-combined.log
```

```sh
rg -n "dashboard=xbe-read|dashboard=xbe-read-complete|dashboard=xbe-loaded|dashboard=xbe-entry-probe|dashboard=xbe-section-map|dashboard=xbe-executed" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2-combined.log
rg -n "main-loop=timers|memory-watch|pfifo=stream-idle|cpu=hard-irq|vector=0x30|iret" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2/browser-runtime.log
```

## Inputs and artifacts

- Raw runtime:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2/browser-runtime.log`
- Combined log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2-combined.log`
- Native reference:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`

## Loop-guard fields

- `browser_pre_stream_vector_service_state`
- `pre_service_browser_first_watch_read_ticks`
- `post_service_watch_edge`

## Findings

1. Combine passed:
   `COMBINE_DASHBOARD_XBE_READ_EVIDENCE result=pass`.
2. B5 browser runtime evidence passed:
   `BROWSER_RUNTIME_EVIDENCE result=pass boot_result=timeout`.
3. B4 display evidence passed:
   `DISPLAY_CAPTURE_EVIDENCE result=pass`, with browser framebuffer hash
   `cbe824b825c5e0e8fb7bbdfbddcca5e231e2e3b94514146966d4ca12e9c8237b`.
4. Dashboard section-map evidence passed:
   `DASHBOARD_SECTION_MAP_EVIDENCE result=pass ... phase=entry-ready ...`.
5. Strict dashboard-loaded evidence still failed:
   `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`.
   The log contains `dashboard=xbe-executed-detector-proof`, but not the strict
   `dashboard=xbe-executed` marker required for B6.
6. The pre-service tick-gap comparator failed as not comparable:
   `PRE_SERVICE_TICK_GAP_COMPARE result=fail divergence=missing-first-watch-read`.
   Native first watched read was still 136 ticks, but v2 had no browser first
   watch-read marker in the comparable window.
7. The post-service watch-edge comparator failed:
   `POST_SERVICE_WATCH_EDGE_COMPARE result=fail
   divergence=missing-browser-pre-edge,browser-post-edge`. Native had the
   `0x80014f5f->0x80030e84` and `0x80030e84->0x80030f31` edges at 136/137
   ticks; v2 had no comparable browser pre/post edge.
8. The post-service memory-poll comparator reported browser non-comparable
   memory-poll shape. Browser top edge after stream-idle was
   `0x8001b030->0x8001b02f`, with `browser_top_wait_source=pcrtc`,
   `browser_top_wait_op=vblank-suppress`, no preferred IRET, and max timer
   watch value only `0x00002710` / 1 tick.
9. The exact PCRTC diagnostic did fire after entry-ready and before stream-idle:
   `main-loop=timers source=browser-deterministic-pcrtc-prestream` appears at
   lines 1399, 1404, 1414, and 1419 with `nv2a_wait_source=pcrtc`,
   `nv2a_wait_op=intr-clear`, and timer progress.
10. The v2 artifact had 5 total `main-loop=timers` events: one
    `browser-deterministic-pump` warmup and four
    `browser-deterministic-pcrtc-prestream` events.
11. The watched word write callbacks appeared before stream-idle:
    line 1339 with value `0x00000000`, line 1422 with value `0x00002710`, and
    line 1434 with value `0x00004e20`.
12. PFIFO stream-idle still occurred later at lines 2730/2731, but the log had
    no `cpu=hard-irq`, no vector `0x30`, and no real IRET markers. Therefore
    `browser_pre_stream_vector_service_state` is
    `pcrtc-intr-clear-pumped-but-no-vector-service`.

## Decision

Do not promote the v2 deterministic PCRTC artifact over the stable ready-edge
host4 baseline. The boundary-preservation patch fixed the v1 dead zone and
proved the exact PCRTC pump can fire, but v2 regresses the comparable CPU-flow
shape by losing the vector-service/IRET/post-service-edge evidence.

## Next step

Run the required bounded sub-agent loop check. The likely next action is a
`goal.md` update recording v2 as negative/diagnostic evidence, followed by a
strategy revision that keeps the stable ready-edge host4 baseline primary and
treats exact PCRTC pumping as insufficient unless it preserves vector service,
IRET, and the post-service watch edge.
