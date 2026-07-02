# 286 - Post-Stream-Idle Guest Producer Reducer

## Purpose

Add and run a static reducer for
`post_stream_idle_guest_producer_wait_state` using only existing stable native
and browser logs.

## Commands

```sh
chmod +x scripts/xbox-post-stream-idle-guest-producer-compare.py
python3 -m py_compile scripts/xbox-post-stream-idle-guest-producer-compare.py
git diff --check -- scripts/xbox-post-stream-idle-guest-producer-compare.py

scripts/xbox-post-stream-idle-guest-producer-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

## Inputs / Artifacts

- `scripts/xbox-post-stream-idle-guest-producer-compare.py`
- Stable browser baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Native baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`

## Loop-Guard Field

- `post_stream_idle_guest_producer_wait_state`

## Findings

Reducer output:

```text
POST_STREAM_IDLE_GUEST_PRODUCER_COMPARE result=pass divergence=browser-empty-pfifo-wait-native-continuation boundary=0x03881318 native_xbe_executed=yes browser_xbe_executed=no native_first_boundary_line=3750 browser_first_boundary_line=2492 native_first_empty_boundary_line=3751 browser_first_empty_boundary_line=2493 native_first_dma_put_gt_boundary_line=4192 browser_first_dma_put_gt_boundary_line=0 native_first_dma_put_gt_boundary_kind=pfifo=window browser_first_dma_put_gt_boundary_kind=none native_first_dma_put_gt_boundary_op=pusher-enter browser_first_dma_put_gt_boundary_op=none native_first_dma_put_gt_boundary_dma_get=0x03881318 native_first_dma_put_gt_boundary_dma_put=0x0388f814 native_dma_put_gt_boundary_count=928 browser_dma_put_gt_boundary_count=0 native_pfifo_continuation_count=642 browser_pfifo_continuation_count=0 native_pgraph_continuation_count=286 browser_pgraph_continuation_count=0 native_top_wait=pfifo-window/pusher-empty browser_top_wait=pfifo-window/pusher-empty native_latest_wait=pgraph-notify-clear/notify-error-clear browser_latest_wait=pfifo-window/pusher-empty
```

Interpretation:

- Both logs reach the shared `0x03881318` boundary.
- Browser reaches an empty PFIFO window at `dma_get=dma_put=0x03881318` and
  has no later `dma_put > 0x03881318` evidence in the stable artifact.
- Native also reaches the boundary, then later publishes/observes a larger
  command window starting with `dma_put=0x0388f814`.
- Native proceeds through hundreds of post-boundary PFIFO/PGRAPH continuation
  markers and eventually reaches strict `dashboard=xbe-executed`.
- Browser remains in the empty PFIFO wait state and never shows the post-boundary
  producer continuation.

## Decision

The next causal issue is no longer PFIFO consumption or PGRAPH method decode.
It is why the browser-side guest/producer path does not publish the native-like
post-`0x03881318` command continuation.

## Next Step

Run the required bounded loop check. The next field should stay static and
non-instrumented unless the loop check approves otherwise.
