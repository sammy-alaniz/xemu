# Timer Opportunity Static Selftest

## Purpose

- One new fact this run was supposed to produce: whether the new browser timer-opportunity marker fields can be parsed and summarized by the pre-stream comparator without changing the B6 evidence contract.

## Command(s)

```sh
python3 -m py_compile scripts/xbox-pre-stream-tick-source-compare.py

scripts/xbox-pre-stream-tick-source-compare-selftest.sh

bash -n scripts/xbox-pre-stream-tick-source-compare-selftest.sh scripts/xbox-b6-current-boundary.sh

git diff --check
```

## Inputs And Artifacts

- `scripts/xbox-pre-stream-tick-source-compare.py`
- `scripts/xbox-pre-stream-tick-source-compare-selftest.sh`
- `scripts/xbox-b6-current-boundary.sh`
- Changed diagnostic code in `xemu-xbe.c`, `xemu-xbe.h`, `ui/xemu-headless.c`, and `util/main-loop.c`
- Output: command stdout only; no emulation run.

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`

## Findings

- Result: pass.
- Python bytecode compilation passed for `scripts/xbox-pre-stream-tick-source-compare.py`.
- `PRE_STREAM_TICK_SOURCE_COMPARE_SELFTEST_RESULT result=pass cases=3`.
- Shell syntax passed for the selftest and boundary helper.
- `git diff --check` reported no whitespace errors.
- The comparator now summarizes pre-stream timer-opportunity fields such as count, ready count, expired count, reasons, first/last opportunity line, virtual-expired state, deadline delta, wait op, IRQ state, and watched-word ticks.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No emulation or build run was performed; this was parser/static validation only.

## Decision

- Status: current support
- Why: the parser side of the new diagnostic is validated. The next risk is C compilation and then one current-baseline browser run.
- Independent critique used: yes

## Next Step

- Run the required post-history sub-agent loop check, then build-check the C diagnostic changes and wire the new opportunity summary into the boundary helper if the critique still says continue.
