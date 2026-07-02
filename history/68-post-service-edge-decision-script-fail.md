# Post-Service Edge Decision Script Fail

## Purpose

- One new fact this run was supposed to produce: whether the existing browser
  artifacts explain the `browser_post_service_top_edge` regression by showing
  the first focused post-service edges, timer sources, and watched-word values.

## Command(s)

```sh
python3 -m py_compile scripts/xbox-post-service-edge-decision-compare.py
chmod +x scripts/xbox-post-service-edge-decision-compare.py
scripts/xbox-post-service-edge-decision-compare.py --log baseline=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log --log det2=build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log --log warmup1=build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log: none; this was browser-artifact-only static reduction.
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: none.
- Fixture assumptions: existing browser logs only; no emulation was started.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `browser_post_service_top_edge`.

## Findings

- Result: failed before producing a comparator result.
- Important marker/comparator lines:
  `TypeError: field() got an unexpected keyword argument 'default_factory'`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; this was a static helper failure and did not run emulation.

## Decision

- Status: failed run
- Why: the new script defines a helper named `field`, shadowing
  `dataclasses.field` before the dataclass default factories are evaluated.
- Independent critique used: no

## Next Step

- Narrow follow-up: rename the local marker-field helper, rerun the static
  reducer on the same three logs, and keep the target field
  `browser_post_service_top_edge`.
