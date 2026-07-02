# 298 - Deterministic PCRTC Pre-Stream Service Design

## Purpose

- One new fact this design was supposed to produce:
  define a deterministic, default-off browser mode that can recreate the native
  pre-stream serviceable state without promoting normal vblank or another broad
  timer pump.

## Command(s)

```sh
# Design-only artifact. No runtime, static helper, or code patch was run.
```

## Inputs And Artifacts

- Native baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Stable browser baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Source inspection:
  `history/296-browser-pre-stream-vector-service-state-inspection.md`
- Loop-check approval:
  `history/297-pcrtc-service-design-loop-check.md`
- Fixture assumptions:
  stable browser baseline remains unchanged and default behavior stays off.

## Expected Field(s)

- Loop-guard field(s) this design could change or explain:
  `browser_pre_stream_vector_service_state`

## Design

Design name:

```text
deterministic-pcrtc-prestream-tick-window
```

Important correction:

- The desired vector `0x30` service is the PIT/PIC timer service. PCRTC is not
  the vector source. Native's useful shape is that PIT/PIC vector `0x30` is
  serviced while the latest NV2A wait state is `pcrtc/intr-clear`, before PFIFO
  stream-idle.
- Therefore the deterministic mode must not fake dashboard execution and must
  not fake a PCRTC interrupt service. It must create the same NV2A context that
  native has, then allow a bounded virtual-timer/PIT service window there.

Exact state predicate:

```text
browser_pre_stream_pcrtc_tick_window_ready =
  browser-runtime &&
  XEMU_BROWSER_BOOT_DETERMINISTIC=1 &&
  XEMU_BROWSER_BOOT_DETERMINISTIC_PCRTC_PRESTREAM=1 &&
  boot_trace_enabled &&
  dashboard_observed &&
  entry_ready &&
  !pfifo_stream_idle_transition_seen &&
  latest_nv2a_wait.source == "pcrtc" &&
  latest_nv2a_wait.op == "intr-clear" &&
  latest_nv2a_wait.pcrtc_enabled has NV_PCRTC_INTR_0_VBLANK &&
  latest_nv2a_wait.pcrtc_pending == 0 &&
  latest_nv2a_wait.pmc_pending has no NV_PMC_INTR_0_PCRTC &&
  virtual_clock_has_timers &&
  virtual_clock_expired
```

Ownership and code shape:

- `hw/xbox/nv2a/nv2a.c`
  - Add a browser-only, default-off PCRTC vblank mode such as
    `deterministic-prestream-service`.
  - In `nv2a_vga_gfx_update()`, keep current normal/off behavior unchanged.
  - When the deterministic mode is enabled, allow a small capped PCRTC vblank
    raise only if:
    - dashboard is observed and entry-ready;
    - PFIFO stream-idle has not been observed;
    - PCRTC vblank is enabled;
    - PCRTC vblank is not already pending.
  - All other browser PCRTC vblank opportunities remain suppressed until the
    after-stream-idle fallback. This avoids repeating the negative normal-vblank
    branch.
- `hw/xbox/nv2a/pcrtc.c`
  - Do not synthesize `pcrtc/intr-clear`.
  - The guest must still write `NV_PCRTC_INTR_0`; only the existing
    `pcrtc_write()` path may publish `source=pcrtc op=intr-clear`.
- `xemu-xbe.c`
  - Add an exact wait helper for `pcrtc/intr-clear`, not the existing broad
    PCRTC wait helper that also accepts `intr-enable`, `vblank-suppress`, and
    `vblank-raise`.
  - Add a new headless pump mode such as
    `pcrtc-intr-clear-before-stream-idle-then-after-pfifo-empty`.
  - Before PFIFO stream-idle, `xemu_xbe_boot_trace_main_loop_timer_pump_ready()`
    returns true only for the exact predicate above.
  - After PFIFO stream-idle, it falls back to the existing PFIFO-empty readiness
    so the stable post-service edge can still be preserved.
  - Include the new mode in the pre-sleep/poll-active classification only
    because the readiness predicate is exact.
- `ui/xemu-headless.c`
  - Reuse the existing deterministic timer-step machinery.
  - Do not use the broad deterministic warmup path as the success mechanism.
  - If needed, tag the timer source distinctly, for example
    `browser-deterministic-pcrtc-prestream`, but only after the exact wait
    predicate is true.
- Browser JS/scripts
  - Plumb any new default-off fixture/env knobs exactly like existing
    deterministic and PCRTC mode knobs.
  - The stable ready-edge host4 command remains unchanged unless the new knobs
    are explicitly set.

Preserved ready-edge host4 invariants:

- Default browser runtime remains the current stable ready-edge host4 baseline.
- `XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=normal` is not promoted.
- No old `pcrtc-before-stream-idle-then-after-pfifo-empty`,
  PIT/precommit/scheduler/before-interrupt/DMA_PUT branch is revived.
- Strict `dashboard=xbe-executed` remains unchanged and cannot be satisfied by
  PCRTC, timer, frame, or read/load markers.
- Future runtime must preserve B4/B5/read/load/entry-ready/section-map,
  PFIFO stream-idle, vector `0x30` service/IRET, and the useful
  `0x80030e84->0x80030f31` post-service edge before promotion.

Review criteria before any runtime:

- Static review confirms default-off behavior for every new knob.
- Static review confirms no code path writes a fake `pcrtc/intr-clear`.
- Static review confirms pre-stream timer readiness requires exact
  `pcrtc/intr-clear` and cannot pass on `vblank-suppress`, `vblank-raise`,
  `intr-enable`, or `pfifo-window/pusher-empty`.
- Static review confirms after-stream-idle fallback remains PFIFO-empty gated.
- Static review confirms the detector for `dashboard=xbe-executed` is untouched.

Future single-runtime acceptance criteria, after code review only:

- Browser emits a pre-stream `pcrtc/vblank-raise` followed by guest
  `pcrtc/intr-clear`.
- Browser emits `main-loop=timers` from the deterministic PCRTC source while
  wait state is exactly `pcrtc/intr-clear`.
- Browser services vector `0x30` before PFIFO stream-idle.
- `pre_service_browser_first_watch_read_ticks` moves above 0 toward native's
  136.
- B4/B5/read/load/entry-ready/section-map, PFIFO stream-idle, IRET, and the
  post-service watch edge do not regress.
- Strict B6 still fails or passes only according to real
  `dashboard=xbe-executed`; the new mode is not a substitute marker.

## Findings

- Result:
  The next code change, if approved, should be a narrow exact-predicate mode:
  create a real guest-clearable PCRTC wait context first, then allow a bounded
  PIT/PIC timer window only while the wait context is `pcrtc/intr-clear`.
- Important marker/comparator lines:
  No new markers were produced. This design uses the lines identified in
  `history/296`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; no runtime was started.

## Decision

- Status: current
- Why:
  This plan names the state predicate and keeps the change deterministic and
  default-off. It avoids both mistakes called out by prior evidence: normal
  vblank promotion and generic timer pumping.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  `history/297` approved drafting this exact design plan before any code or
  runtime.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary:
  The method remains causal because it ties the next change to the absent
  native pre-stream state and keeps strict B6 unchanged.
- If yes, process adjustment for next 2-3 turns:
  Run a loop check on this plan before any patch. If approved, implement only
  the default-off exact-predicate mode and static verification first.

## Next Step

- Narrow follow-up:
  Run the required bounded loop check. Candidate next action is a code patch
  for the default-off deterministic PCRTC pre-stream tick-window mode, followed
  by static verification only.
