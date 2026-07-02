# Active Goal: Browser Xbox Main Menu And Game Launch

## Objective

Get the browser-hosted xemu build to boot to the original Xbox main menu and
launch a game from user-provided local assets.

This replaces the narrow B6-only objective. B6 dashboard execution remains a
required prerequisite, but it is no longer the final goal. The final goal is:

- Browser runtime boots real Xbox firmware/dashboard assets.
- The Xbox main menu is visible and recognizable in the browser.
- Browser controls can start/stop the emulator and provide controller input.
- A game image can be selected, mounted, launched from the dashboard, and shown
  executing in browser frames.

## Success Contract

The goal is complete only when one browser-runtime run proves all of these:

- `dashboard=xbe-read`, `dashboard=xbe-loaded`, `dashboard=xbe-entry-probe
  status=ready`, and strict `dashboard=xbe-executed` for the dashboard XBE.
- Browser display capture shows the Xbox main menu, not just non-empty frames.
- Browser input can navigate the main menu.
- A selected game disc or game XBE is mounted through browser storage.
- The dashboard launches the game, or an explicitly documented launch path
  hands off to the game XBE.
- Browser runtime emits game read/load/execute markers.
- Browser display capture shows a recognizable first game screen or game boot
  screen.
- The run is reproducible from a documented command/script and leaves an
  auditable log bundle.

Do not weaken this by treating any single partial signal as success. Non-empty
display, dashboard read/load without execute, or native-only evidence are useful
diagnostics but do not complete the goal.

## Current State

Known working evidence:

- B3/B4/B5 browser evidence exists: real storage reads, browser runtime shell,
  logs, persistence/config path, and non-empty browser framebuffer captures.
- Native headless has strict dashboard execution and native reference evidence.
- Browser runtime reads and loads `xboxdash.xbe`, reaches entry-ready, emits
  section-map evidence, and can produce display frames.
- Front-most CPU-flow baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`.
  Keep this as the primary B6 diagnostic for the pre-service tick and
  post-service watch-edge boundary because it preserves the comparable first
  watched read/post-service edge shape while failing strict B6 at
  `missing-xbe-executed-marker`.
- Current restored-boundary artifact after quarantining the perturbing
  before-interrupt micro-scheduler hook:
  `build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log`.
  It restores B4 display capture, `dashboard=xbe-loaded`,
  entry-ready section-map, memory-watch install, PFIFO stream-idle, vector
  `0x30` PIC ack/hard-IRQ service, and bounded host timer progress. It still
  does not emit strict `dashboard=xbe-executed`, does not preserve the stable
  first-watch-read/post-service-edge comparator path, and must not be promoted
  over the front-most CPU-flow baseline.

Known blocker:

- Browser still fails strict dashboard execution at
  `missing-xbe-executed-marker`.
- Browser reaches `xemu_xbe_boot_trace_mark_executed()`, but the early attempt
  exits through `dashboard=xbe-exec-section-miss` with
  `high-alias-phys-mismatch`.
- The sharper runtime divergence remains timing/order: browser reaches the
  first watched read of physical `0x0003a890` at 0 ticks, while native reaches
  the comparable point at 136 ticks.
- The post-STI pre-first-read before-interrupt micro-scheduler branch is
  perturbing and quarantined. Repeated runs with that hook enabled timed out
  before dashboard read/load at `read_lba=4609024`; disabling only
  `xemu_xbe_boot_trace_tcg_timer_pump_before_interrupt()` restored the useful
  browser boundary. Do not rerun or tune that before-interrupt scheduler path
  unless a new design first proves boundary preservation.
- The restored-boundary raw artifact's
  `missing-xbe-read-complete-marker` is resolved as artifact-specific. Running
  `scripts/xbox-combine-dashboard-xbe-read-evidence.sh` on it produces
  `build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime-combined.log`,
  which advances the strict dashboard helper to
  `missing-xbe-executed-marker`. Do not chase read-complete as the active
  blocker.
- The deferred NV2A `DMA_PUT` observer branch is runtime-negative for causal
  proof. The browser artifact
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deferred-dma-put-v1/browser-runtime.log`
  activates `trace_nv2a_user_dma_put_limit=16` and preserves B4/B5/read/load
  evidence after combination, but it regresses the stable post-service watch
  edge to `missing-browser-post-edge`. Leave the observer default-off and
  diagnostic-only; do not use that runtime branch as B6 causal evidence.
- The deterministic PCRTC pre-stream branch is diagnostic-negative for promotion.
  The v1 artifact
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v1/browser-runtime.log`
  timed out before dashboard read/load/entry-ready and before B4 display because
  the exact gate created `browser_pre_stream_vector_service_state=pre-entry-dead-zone`.
  The boundary-preservation patch then produced v2:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2-combined.log`.
  V2 restores B5 runtime, B4 display capture, dashboard read/load, entry-ready,
  and section-map evidence, and proves exact
  `main-loop=timers source=browser-deterministic-pcrtc-prestream` can fire at
  `pcrtc/intr-clear`. However, it still fails strict B6 at
  `missing-xbe-executed-marker`, has
  `browser_pre_stream_vector_service_state=pcrtc-intr-clear-pumped-but-no-vector-service`,
  loses vector `0x30` service/real IRET, and fails the comparable
  first-watch-read/post-service-edge path with `missing-first-watch-read` and
  `missing-browser-pre-edge,browser-post-edge`. Do not tune or promote this
  branch over the stable ready-edge host4 baseline.
- Stable-log static reducers now classify the front-most boundary as:
  `native_pre_stream_serviceable_state_browser_mapping=no-equivalent-browser-state-before-stream-idle`.
  Native services vector `0x30` before PFIFO stream-idle while waiting on
  `pcrtc/intr-clear`, with the watched word already accumulated to 136 ticks by
  the shared stream-idle read. Browser has no equivalent pre-stream vector
  service state, reaches PFIFO empty at `dma_get=dma_put=0x03881318`, then
  services vector `0x30` from `eip=0x8001b030`, and its first watched
  `0x0003a890` read remains 0 ticks.

Implication:

- Main-menu and game-launch work must first make browser dashboard execution
  real and deterministic enough to pass the strict marker. After that, visual
  menu recognition and game launch become the next gates.
- The next causal slice should start from the stable ready-edge host4 combined
  CPU-flow baseline, not from the restored-boundary proof artifact and not from
  the quarantined post-STI before-interrupt scheduler branch.
- The next design must explain how browser reaches, or deterministically
  replaces, the missing native pre-stream `pcrtc/intr-clear` serviceable state
  without reviving old generic pump/vblank/PIT/scheduler/precommit branches.
  Do not start another runtime, probe, or instrumentation branch until that
  design names the exact field it can change.

## Working Strategy

Do whatever code changes are necessary, but keep the architecture honest:

- Prefer deterministic emulated Xbox ordering over browser wall-clock behavior.
- Keep core emulation state owned by the emulator/main thread or an explicitly
  synchronized event scheduler.
- Do not fake `dashboard=xbe-executed` or game execution markers.
- It is acceptable to add diagnostic-only modes, deterministic boot modes, and
  temporary launch helpers if they are clearly gated and logged.
- It is acceptable to trade speed for determinism until main menu and game
  launch are proven.

## Milestones

### M0: Preserve The Current Browser Boot Harness

Purpose: keep the known B3/B4/B5 path from regressing while broadening the goal.

Required work:

- Keep `scripts/xbox-browser-runtime-smoke.sh` as the main browser-runtime
  proof harness.
- Keep Firefox BiDi fallback working.
- Keep real-asset validation, browser block storage, EEPROM persistence, and
  display capture evidence.
- Keep `scripts/xbox-b6-current-boundary.sh` usable as a regression helper until
  it is superseded by a main-menu/game-launch checker.

Evidence:

- Browser runtime evidence passes.
- Display capture evidence passes.
- Dashboard read/load/entry-ready/section-map evidence passes.

### M1: Deterministic Dashboard Execution

Purpose: make browser reach the same dashboard execution condition native
reaches, instead of arriving at the strict check too early or in the wrong
emulated timer/PFIFO/interrupt state.

Required work:

- Add an opt-in deterministic browser boot mode, for example
  `XEMU_BROWSER_BOOT_DETERMINISTIC=1`.
- First design the deterministic ordering against the current boundary:
  browser needs an emulated-state-owned way to reach or replace native's
  pre-stream `pcrtc/intr-clear` vector `0x30` service before the watched read
  of `0x0003a890`.
- Drive boot-critical timers, PFIFO work, interrupt delivery, and CPU resumes in
  a fixed order after that design preserves the stable ready-edge host4
  boundary.
- Add sequence-numbered logs for:
  - virtual time
  - current PC
  - dashboard image PC
  - guest physical address
  - image physical address
  - `phys_match`
  - watched word `0x0003a890`
  - interrupt state
  - PFIFO scheduler state
- Continue using the strict dashboard execution detector.

Evidence:

- Browser first watched read moves from 0 ticks toward native behavior, or the
  remaining reason it cannot move is explicitly identified.
- Browser emits strict `BOOT_MARK b6 dashboard=xbe-executed
  context=browser-runtime`.
- Existing B4/B5/read/load/entry-ready/section-map evidence still passes.

### M2: Main Menu Recognition

Purpose: prove the dashboard is not only executing, but has reached the visible
Xbox main menu.

Required work:

- Capture native reference frames for the main menu from the same firmware/HDD
  assets.
- Capture browser framebuffer frames after strict dashboard execution.
- Add a checker that classifies main-menu frames by hash, perceptual hash, or a
  small set of stable visual regions.
- Preserve the raw captured frames outside proprietary fixture paths.

Evidence:

- `BROWSER_MAIN_MENU_CAPTURE result=pass`
- Frame dimensions and source are logged.
- Browser frame match against native reference is logged.
- The checker rejects generic non-empty frames.

### M3: Browser Input To Dashboard

Purpose: make the main menu usable enough to choose the launch path.

Required work:

- Add browser keyboard/gamepad mapping to the Xbox controller path.
- Log input events at the browser boundary and at the emulated controller
  device boundary.
- Build a simple scripted input path for menu navigation.

Evidence:

- Browser input changes dashboard menu selection or triggers a known dashboard
  action.
- A scripted smoke can press a deterministic sequence and observe a changed
  frame or dashboard state.

### M4: Game Media Selection And Mount

Purpose: allow the browser user to provide game media without loading huge
images entirely into WASM memory.

Required work:

- Support selecting a local DVD ISO/XISO or a game directory/image through the
  browser page.
- Mount game media through the browser block backend with random reads.
- Add game media validation and clear failure logs.
- Add read markers that identify game media access without logging proprietary
  content.

Evidence:

- Browser emits game media asset metadata: size, type, and mount path.
- Random-read probes from the game image match expected byte ranges.
- Dashboard/game launch path causes game media reads.

### M5: Game XBE Load And Execute

Purpose: prove the selected game actually starts.

Required work:

- Add game-XBE read/load/entry-ready/execute markers separate from dashboard
  markers.
- Track dashboard-to-game handoff state:
  - dashboard running
  - game media mounted
  - launch requested
  - game XBE read
  - game XBE loaded
  - game XBE executed
- If dashboard-based launch is blocked, add a clearly gated direct-game launch
  diagnostic mode, but do not count it as dashboard menu launch unless the
  dashboard initiated it.

Evidence:

- `BOOT_MARK game=xbe-read context=browser-runtime`
- `BOOT_MARK game=xbe-loaded context=browser-runtime`
- `BOOT_MARK game=xbe-executed context=browser-runtime`
- Handoff source is logged as either `dashboard-menu` or explicit diagnostic
  mode.

### M6: First Game Screen

Purpose: prove game execution reaches visible output.

Required work:

- Capture browser frames after game execution.
- Add a first-game-screen checker using hash/perceptual hash/manual reference
  regions.
- Keep audio/network optional.

Evidence:

- `BROWSER_GAME_CAPTURE result=pass`
- Capture is after `game=xbe-executed`.
- Frame is not just dashboard/menu carryover.

### M7: One-Command Proof

Purpose: make the result repeatable.

Required work:

- Add a single script that runs the browser main-menu/game-launch proof with
  local fixtures.
- Bundle logs, browser transcript, captured frames, hashes, build metadata, and
  checker results.
- Return nonzero on missing main menu, missing game launch, missing game
  execution, or missing game frame.

Evidence:

- `XBOX_BROWSER_MENU_GAME_RESULT result=pass`
- Bundle path is printed.
- Failure mode names the first missing gate.

## Initial Implementation Plan

1. Add a deterministic browser boot mode rather than more ad hoc host pumps.
   Start by designing the missing pre-stream serviceable-state replacement from
   the stable ready-edge host4 boundary, not by moving the existing host pump
   earlier or adding another generic timer probe.
2. Convert the watched-word/timer/PFIFO/IRQ diagnostics into one compact
   timeline marker so the browser/native divergence can be read without
   stitching many helpers together.
3. Make strict browser `dashboard=xbe-executed` pass without weakening the
   detector.
4. Add `BROWSER_MAIN_MENU_CAPTURE` and a main-menu checker.
5. Add browser input mapping and a scripted menu action smoke.
6. Add game media picker/mount evidence and game-XBE read/load/execute markers.
7. Add first-game-screen capture and the final one-command checker.

## Loop Guard

Before a run, probe, or code change, name the one field it can change or
explain. For the new goal, useful fields are:

- `browser_dashboard_xbe_executed`
- `browser_first_watch_read_ticks`
- `native_pre_stream_serviceable_state_browser_mapping`
- `browser_pre_stream_vector_service_state`
- `browser_main_menu_capture`
- `browser_input_reaches_controller`
- `browser_game_media_mounted`
- `browser_game_xbe_read`
- `browser_game_xbe_loaded`
- `browser_game_xbe_executed`
- `browser_game_frame_capture`
- `browser_menu_game_result`

Do not run broad diagnostics that only reconfirm:

- B3/B4/B5 pass.
- Browser dashboard read/load/entry-ready passes.
- Browser strict dashboard execution still fails.
- Native strict dashboard execution passes.
- Browser non-empty display exists.

Current process adjustment:

- After two consecutive runs fail before dashboard read/load, quarantine the
  new perturbing branch first, then inspect. Do not spend additional runtime
  attempts tuning diagnostics that no longer reach the boundary they are meant
  to measure.
- Until a revised deterministic design exists, do not run or instrument again
  just to reconfirm `missing-xbe-executed-marker`, `browser-first-watch-read`
  at 0 ticks, or the absent browser pre-stream vector service. The next useful
  action is design/code inspection tied to the missing
  `pcrtc/intr-clear` serviceable state.

## History Requirement

After every experiment, run, or probe, write a numbered markdown summary in
`history/` using `history/<next-number>-<short-run-title>.md`.

Include:

- Purpose.
- Exact command(s).
- Inputs/artifacts.
- Expected field(s).
- Findings.
- Decision.
- Next step.

After writing a new numbered history file, run a bounded loop-check before the
next experiment/run/probe/code change. The only exemption is the loop-check
history entry itself.

Every sub-agent loop-check prompt must include a concise
`Progress-Method Critique`, even when the checkpoint is only the required
post-history loop check. It should report whether the current method is still
moving toward strict dashboard execution, visible main-menu proof, and game
launch; whether the work is becoming too diagnostic-heavy or rerun-heavy; and
one process adjustment for the next 2-3 turns.

## Critique Checkpoint

Use a bounded critique checkpoint when:

- Two consecutive experiments fail to improve or explain the active field.
- A proposed run repeats an old negative-control mode.
- Work broadens away from main-menu/game-launch proof.
- A change would weaken execution/capture evidence.
- The next action cannot name one field it changes or explains.

The critique must answer:

1. Are we looping?
2. What is the narrowest next fact that changes the current boundary?
3. Which hypothesis should be killed, kept, or revised?
4. Is the proposed next run justified by the loop guard?
5. What is one better experiment, if any, and what field would it change?

For independent critique checkpoints, the `Progress-Method Critique` section
must answer in more detail:

- Whether the current metrics still connect to strict dashboard execution,
  visible main-menu proof, and game launch.
- Whether the current work is over-weighted toward diagnostics, runtime
  reruns, or historical confirmation instead of changing/explaining a named
  field.
- Whether the history and loop-check process is helping or slowing the next
  2-3 turns.
- Whether code inspection, code change, runtime probing, or stopping is the
  right next mode.
- One concrete process adjustment for the next 2-3 turns.

End with one decision: continue, revise, or stop.

## Definitions

- Dashboard success means the real dashboard XBE executed in browser runtime and
  the main menu is visible.
- Game launch means a game selected through browser-hosted local assets is
  mounted and its XBE executes.
- Game visible means a browser capture after game execution shows a first game
  screen or game boot screen.
- Native-only proof is a baseline, not completion.
- Diagnostic direct-game launch can be useful, but it is not a substitute for
  dashboard menu launch unless clearly documented and accepted as a separate
  milestone.
