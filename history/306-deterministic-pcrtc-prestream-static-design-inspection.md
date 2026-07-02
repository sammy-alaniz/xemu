# 306 - deterministic PCRTC pre-stream static design inspection

## Purpose

Inspect the deterministic PCRTC pre-stream patch without running emulation or
changing code. The field this inspection could explain was
`browser_pre_stream_vector_service_state`: whether the browser runtime failed
because the exact PCRTC gate was wrong after entry-ready, or because the patch
blocked too broadly before entry-ready.

## Exact commands

```sh
rg -n "pcrtc-intr-clear|deterministic-pcrtc|pcrtc_prestream|main_loop_timer_pump_ready|timer_pump_ready|deterministic_ready|entry_ready|pump_ready" xemu-xbe.c ui/xemu-headless.c hw/xbox/nv2a/nv2a.c xemu-xbe.h
```

```sh
nl -ba ui/xemu-headless.c | sed -n '1,260p'
nl -ba xemu-xbe.c | sed -n '1080,1305p'
nl -ba ui/xemu-headless.c | sed -n '480,850p'
nl -ba xemu-xbe.c | sed -n '990,1082p'
nl -ba hw/xbox/nv2a/nv2a.c | sed -n '880,1110p'
nl -ba xemu-xbe.c | sed -n '1330,1362p'
```

## Inputs and artifacts

- `xemu-xbe.c`
- `xemu-xbe.h`
- `ui/xemu-headless.c`
- `hw/xbox/nv2a/nv2a.c`

## Loop-guard fields

- `browser_pre_stream_vector_service_state`
- `native_pre_stream_serviceable_state_browser_mapping`
- `pre_service_browser_first_watch_read_ticks`

## Findings

1. `xemu_xbe_boot_trace_main_loop_timer_pump_ready()` returns false before
   `xemu_xbe_boot_trace_entry_ready()` for all modes, including the new exact
   PCRTC pre-stream mode.
2. `xemu_xbe_boot_trace_main_loop_timer_pump_pcrtc_prestream_ready()` also
   requires `entry_ready`, exact PCRTC pre-stream mode, no PFIFO stream-idle,
   and the latest wait snapshot matching `pcrtc/intr-clear`.
3. `xemu_headless_pump_browser_timers()` only enables deterministic warmup when
   `xemu_headless_browser_timer_pump_poll_active()` is true. That helper is
   also just `xemu_xbe_boot_trace_entry_ready()`.
4. Therefore, before entry-ready, the new exact PCRTC mode cannot pump timers,
   cannot do deterministic warmup, and cannot become
   `pcrtc_prestream_ready`.
5. `nv2a_browser_deterministic_pcrtc_prestream_should_raise()` requires both
   dashboard observed and entry-ready before allowing its one deterministic
   PCRTC vblank raise.
6. When deterministic PCRTC pre-stream is enabled,
   `nv2a_browser_pcrtc_vblank_should_raise()` returns false for all other PCRTC
   vblank opportunities. This is intentional for the exact experiment, but it
   means the branch must not be used as the whole boot path unless the known
   baseline already reaches entry-ready.
7. The history/304 runtime did not reach entry-ready. Static inspection
   therefore classifies the failure as `pre-entry-dead-zone`: the branch removed
   the known ready-edge/host-fallback behavior but could not activate the exact
   after-entry PCRTC gate.

## Decision

Revise the branch before any runtime retry. The exact `pcrtc/intr-clear` gate
should be treated as an after-entry/pre-stream diagnostic, not as a replacement
for the whole browser headless timer path from process start.

## Next step

Run the required bounded sub-agent loop check. If it approves a code change, the
smallest safe patch is to preserve the known pre-entry behavior and apply the
exact PCRTC gate only after entry-ready, with boundary preservation as an
explicit invariant before any future runtime.
