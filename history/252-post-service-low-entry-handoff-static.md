# Post Service Low Entry Handoff Static

## Purpose

- One new fact this run was supposed to produce: `post_service_low_entry_handoff_absence_cause`.

## Command(s)

```sh
sed -n '2560,2705p' \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

sed -n '3740,3770p;6158,6182p' \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

rg -n "dashboard=xbe-exec-transition|dashboard=xbe-exec-probe|dashboard=xbe-entry-target-probe|dashboard=xbe-dispatch-probe|dashboard=kernel-loop-probe|cpu=iret|pic=irq-ack|memory-watch" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log | tail -n 100

rg -n "dashboard=xbe-executed|dashboard=xbe-exec-transition|dashboard=xbe-exec-probe|dashboard=xbe-entry-target-probe|dashboard=xbe-dispatch-probe|dashboard=kernel-loop-probe|cpu=iret|pic=irq-ack|memory-watch" \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log | tail -n 120
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: existing logs only.
- Fixture assumptions: static inspection only; no code change and no runtime.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  - `post_service_low_entry_handoff_absence_cause`

## Findings

- Result: `post_service_low_entry_handoff_absence_cause=browser-times-out-in-post-service-high-alias-idle-loop-before-native-late-pgraph-notify-clear-handoff`.
- Stable browser preserves the early post-service path, including hard IRQ service, PIC ack, IRET, and the useful watched-word block:
  - `0x80014f32->0x80030e84`
  - `0x80030e4c->0x80030e84`
  - `0x80030e84->0x80030f31`
- The browser is still behind at that path. Its watched word is only `0x00002710` or `0x00004e20` around the comparable post-service area, while native reaches the same broad area with `0x0014c080` and then `0x0014e790`.
- After the preserved post-service path, browser control flow returns into high-alias kernel loops and later repeats `0x8001b02f/0x8001b030` style high-alias mismatch probes. It never emits an actual direct low-entry `dashboard=xbe-executed`.
- Native also shows high-alias mismatch probes after entry-ready, but later progresses through a different late state and reaches actual low XBE execution:
  - `dashboard=xbe-executed ... guest_pc=0x00017d60 ... image_pc=0x00017d60 ... address_mode=direct ... phys_match=yes ... source=tcg-tb-post`
- The native strict marker appears after later GPU/PGRAPH-ish wait state, including visible `pgraph-notify-clear` / `notify-error-clear` context near the handoff region. That suggests the first post-service edge is necessary evidence but not the final dashboard-entry handoff.
- Classification: the missing browser strict marker is not explained by a bad strict detector and not by failure to reach the first useful post-service edge. The sharper absence is the later native handoff from post-service/high-alias execution into direct low XBE execution.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run.

## Decision

- Status: current
- Why: the next work should explain or restore the late handoff state that native reaches before `guest_pc=0x00017d60`, without weakening the strict `dashboard=xbe-executed` marker or rerunning broad B3/B4/B5 diagnostics.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/251-post-service-low-entry-loop-check.md` requested static handoff inspection as the narrowest next target after strict-exec causality classification.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the prior loop check redirected away from repeated timer/PIT branches and toward actual low-entry handoff, which is closer to the strict dashboard execution contract.
- If yes, process adjustment for next 2-3 turns: require the next action to name a late-handoff field, not a broad timer or display proxy.

## Next Step

- Narrow follow-up: run the required post-history loop check. Ask whether the next field should be `native_late_handoff_state_required_for_low_entry`, `browser_missing_late_pgraph_notify_clear_handoff_state`, or a stricter static comparison of final native/browser high-alias loop exits.
