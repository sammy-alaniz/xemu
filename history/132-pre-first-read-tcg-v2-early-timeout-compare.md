# 132. Pre-first-read TCG v2 early-timeout comparison

## Purpose

Explain why the rebuilt browser runtime validation for the post-PFIFO/pre-first-read TCG pump predicate timed out before dashboard read/load markers, without starting another emulation run.

## Loop-Guard Field

- `v2_early_timeout_cause`

## Exact Commands

```sh
rg -n "BROWSER_RUNTIME_CONFIG|BROWSER_RUNTIME_ASSET|BROWSER_ASSET_AUTO|BROWSER_BLOCK_BACKING|BOOT_MARK b[0-6]|BROWSER_RUNTIME_TRANSCRIPT|BROWSER_RUNTIME_SMOKE|DASHBOARD_|display_capture|BROWSER_DISPLAY_SCANOUT" \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1/browser-runtime.log \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log

rg -n "bmdma|ide_dma|ide=hdd|first_read_lba|dashboard=xbe-read|dashboard=xbe-load|entry-ready|section-map|pfifo=stream-idle|tcg=timer-pump" \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1/browser-runtime.log \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log

sed -n '120,210p' build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1/browser-runtime.log
sed -n '120,210p' build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log

rg -n "BROWSER_ASSET_AUTO|ASSET_AUTO|BROWSER_BLOCK_BACKING|opfs|localStorage|indexedDB|port|origin|persist" \
  scripts browser

rg -n "browser-tcg-post-pfifo-pre-first-read-v1|PORT=8846|PORT=8847|browser-tcg-post-pfifo-pre-first-read-v2" \
  history goal.md AGENTS.md

git diff -U8 -- xemu-xbe.c
```

## Inputs and Artifacts

- Previous runtime artifact:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1/browser-runtime.log`
- Rebuilt runtime artifact:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log`
- Browser host code:
  `browser/xbox-boot/main.js`
  `browser/xbox-boot/worker.js`
- Runtime smoke wrapper:
  `scripts/xbox-browser-runtime-smoke.sh`
- Edited source:
  `xemu-xbe.c`

## Findings

- The v2 timeout happened very early. The log is only 153 lines and never reaches dashboard read/load, entry-ready, section-map, PFIFO stream-idle, memory-watch, edge-decision, tick-block, or `tcg=timer-pump` markers.
- Both v1 and v2 reach browser startup, OPFS block backing, initial block reads, device initialization, and `nv2a-pfifo started`.
- v1 continues after device init into BMDMA/IDE DMA activity, including `bmdma=irq`, `bmdma=start_dma`, `ide_dma`, `ide=hdd first_read_lba=3`, and later dashboard XBE reads.
- v2 does not emit BMDMA/IDE DMA activity after device init. It only continues placeholder display scanout markers until timeout.
- The v1 runtime used port `8846`; the v2 runtime used port `8847`.
- v1 includes a `BROWSER_ASSET_AUTO result=pass name=hdd ...` marker. v2 does not include `BROWSER_ASSET_AUTO`.
- The rebuilt wasm size changed as expected after the source edit, but the edited TCG readiness predicate is gated behind `xemu_xbe_boot_trace_entry_ready()`. Because v2 never reaches dashboard read/load or entry-ready, that predicate should not be reachable in this early stall.

## Decision

The comparison does not validate or invalidate the TCG predicate change. It shows the v2 validation run diverged before the B6 CPU boundary under test.

Current best explanation:

`v2_early_timeout_cause=validation-harness-drift-before-b6-boundary`

The strongest suspect is browser runtime state/origin drift from moving the run from port `8846` to port `8847`, because the browser boot path uses browser-side persisted state and v2 lacks the v1 `BROWSER_ASSET_AUTO` marker. This is plausible but not proven.

## Next Step

Run the required bounded sub-agent loop check before any new experiment. Ask it to critique whether the next controlled step should be a single same-origin rerun of the rebuilt wasm on port `8846`, writing to a new artifact directory, to distinguish `port/origin setup drift` from `code/build regression`.
