# Pre-First-Read Post-STI Setup Audit

## Purpose

- One new fact this run was supposed to produce: `post_sti_runtime_retry_or_setup_issue`, using no-emulation comparison after the failed post-STI runtime.

## Command(s)

```sh
rg -n 'BROWSER_LOCATION|BROWSER_RUN_MODE|BROWSER_ARTIFACT|BROWSER_ASSET|BROWSER_BLOCK_BACKING|BROWSER_DIAGNOSTIC name=|BROWSER_DIAGNOSTIC_APPLY|BOOT_SMOKE_RESULT|BROWSER_RUNTIME_TRANSCRIPT result|BROWSER_RUNTIME_SMOKE result' \
  build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log

rg -n 'BROWSER_LOCATION|BROWSER_RUN_MODE|BROWSER_ARTIFACT|BROWSER_ASSET|BROWSER_BLOCK_BACKING|BROWSER_DIAGNOSTIC name=|BROWSER_DIAGNOSTIC_APPLY|BOOT_SMOKE_RESULT|BROWSER_RUNTIME_TRANSCRIPT result|BROWSER_RUNTIME_SMOKE result' \
  build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log

rg -n 'ide=hdd|dashboard=xbe-read|dashboard=xbe-loaded|read_lba=4609024|read_lba=4609192|read_lba=4609200|bmdma=start_dma|ide_dma=submit-read|BROWSER_BLOCK_READ' \
  build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log

rg -n 'ide=hdd|dashboard=xbe-read|dashboard=xbe-loaded|read_lba=4609024|read_lba=4609192|read_lba=4609200|bmdma=start_dma|ide_dma=submit-read|BROWSER_BLOCK_READ' \
  build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log
```

## Inputs And Artifacts

- Restored-boundary browser log: `build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log`
- Failed post-STI browser log: `build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log`
- Fixture assumptions: no emulation run; setup/log comparison only.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `post_sti_runtime_retry_or_setup_issue`.

## Findings

- Result: no obvious fixture/setup mismatch; the failed run diverges as an early progress timeout after matching the early disk path.
- Both runs use selected assets, pass asset validation, and use `backend=opfs-sync` with the same 39714816-byte HDD.
- Both runs apply the same relevant diagnostics: PCRTC vblank off, memory watch `0x0003a890`, write access, ready-edge host pump mode, TCG timer pump interval 1, TCG mode `pit-pre-first-read-micro-scheduler`, and IRQ-after-PFIFO-empty.
- The failed run used port/origin `127.0.0.1:8849`; the restored-boundary run used `127.0.0.1:8846`.
- The failed run loaded the rebuilt wasm artifact with a larger byte count than the older restored-boundary run, as expected after code changes.
- The early storage path matches through `read_lba=3` and `read_lba=4609024`.
- The failed run stops after `read_lba=4609024` / `BROWSER_BLOCK_READ offset=2621440 bytes=4096` and times out at 375 lines without dashboard read markers.
- The restored-boundary run continues after the same `read_lba=4609024` through sequential 8-sector reads, reaches dashboard `read_lba=4609192`, emits `dashboard=xbe-read-progress`, then `dashboard=xbe-loaded`.
- No evidence in the failed log shows asset validation failure, block backing failure, HTTP artifact failure, or diagnostic fixture application failure.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No new runtime was run. The failed artifact did regress, but the setup audit indicates it did not reach the scheduler boundary.

## Decision

- Status: current
- Why: the failed post-STI runtime appears to be an early progress timeout rather than evidence against the post-STI scheduler change. The setup/log comparison supports a controlled retry, but the loop check must approve it because recent work has had multiple non-promotable runtime artifacts.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: `history/167` required setup/log inspection before any retry.

## Next Step

- Narrow follow-up: run the required loop check. Proposed next action: one controlled retry of the same post-STI runtime, preferably using the known-good browser runtime port/origin if available, judged first on reaching dashboard read/load and then on `scheduler=pre-first-read phase=start`.
