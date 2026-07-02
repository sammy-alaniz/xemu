# 305 - deterministic PCRTC pre-stream log classification

## Purpose

Inspect only the failed deterministic PCRTC pre-stream browser-runtime artifact
from history/304 to classify why the gate never became eligible. The one new
field this inspection could explain was `browser_pre_stream_vector_service_state`.

## Exact commands

```sh
rg -n "entry_ready|entry-ready|dashboard=entry|dashboard=xbe|headless=timer-pump|deterministic=timer-pump" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v1/browser-runtime.log
```

```sh
rg -n "pcrtc|intr-clear|vblank|wait-state|wait_state|pfifo=stream|stream-idle|vector=0x30|iret|memory-watch" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v1/browser-runtime.log
```

```sh
rg -n "BOOT_SMOKE_RESULT|BROWSER_BOOT_RESULT|BROWSER_RUNTIME_TRANSCRIPT|BROWSER_RUNTIME_SMOKE|BOOT_REAL_B3_MATRIX_RESULT|BROWSER_DISPLAY|display_capture|b4_marker" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v1/browser-runtime.log
```

```sh
rg -n "entry_ready=yes|deterministic_ready=yes|dashboard=read|dashboard=loaded|dashboard=entry|dashboard=xbe|section-map|memory-watch-install|memory-watch|pfifo=stream|main-loop=timers|cpu=hard-irq|pic=|vector=|iret|intr-clear|pcrtc.*intr|vblank-raise" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v1/browser-runtime.log
```

```sh
tail -n 80 build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v1/browser-runtime.log
```

## Inputs and artifacts

- Inspected log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v1/browser-runtime.log`

## Loop-guard fields

- `browser_pre_stream_vector_service_state`
- `native_pre_stream_serviceable_state_browser_mapping`
- `pre_service_browser_first_watch_read_ticks`

## Findings

1. The run never emitted `entry_ready=yes`.
2. The run never emitted `deterministic_ready=yes`.
3. The run never emitted dashboard read/load/entry markers, section-map
   markers, PFIFO stream-idle markers, vector `0x30`, IRET, or memory-watch
   runtime markers.
4. The only `pcrtc`, `intr-clear`, and `vblank` matches were diagnostic config
   lines and summary fields. There was no runtime `pcrtc/intr-clear` wait-state
   evidence and no `vblank-raise` evidence.
5. The runtime did emit many deterministic opportunity markers with
   `reason=deterministic-blocked`, `entry_ready=no`,
   `deterministic_ready=no`, and later `virtual_has_timers=yes` /
   `virtual_expired=yes`. This shows expired timers existed, but the exact gate
   correctly refused to pump before the dashboard entry-ready prerequisite.
6. The tail of the log shows the run was still in B3 HDD/DMA activity near the
   timeout, ending after `ide_dma`/`bmdma` markers and then
   `BOOT_SMOKE_RESULT reason=browser-main-timeout`.
7. Therefore this artifact did not measure
   `pre_service_browser_first_watch_read_ticks`. The blocker was earlier:
   `entry_ready` was absent, so `browser_pre_stream_vector_service_state` is
   `not-reached-before-entry-ready`.

## Decision

Quarantine this runtime result as a regression artifact. It does not prove the
PCRTC pre-stream service design wrong at the intended B6 boundary; it proves the
current exact gate can block all browser-side timer pumping early enough that
the run fails before dashboard entry-ready and B4 display evidence.

## Next step

Run the required bounded sub-agent loop check before any new run, checker,
comparator, or code change. The likely revised direction is to avoid promoting
or rerunning the exact gate as-is, and instead decide whether to relax only the
pre-entry blocking behavior or abandon this deterministic PCRTC branch in favor
of a less perturbing static explanation of the missing browser pre-stream
service state.
