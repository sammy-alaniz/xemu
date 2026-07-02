# 190. PFIFO Scheduler Source-Tag Scope Inspection

## Purpose

Inspect PFIFO scheduler marker and kick call sites to identify the smallest
non-perturbing marker-only patch needed to populate
`first_kick_after_last_opportunity_source`.

## Commands

```sh
rg -n "pfifo=scheduler|scheduler|fifo_kick|kick|pusher|run_pusher|pfifo" \
  hw/xbox nv2a* xemu-xbe.c scripts/xbox-pfifo-scheduler-state-classify.py

rg --files | rg 'nv2a|pfifo|xbox-pfifo|scheduler'

sed -n '1,260p' scripts/xbox-pfifo-scheduler-state-classify.py
sed -n '260,560p' scripts/xbox-pfifo-scheduler-state-classify.py

sed -n '620,760p' hw/xbox/nv2a/pfifo.c
sed -n '900,950p' hw/xbox/nv2a/pfifo.c
sed -n '1398,1446p' hw/xbox/nv2a/pfifo.c

rg -n "pfifo_kick\\(|pfifo_kick_with_source\\(|pfifo_boot_trace_scheduler_state\\(" \
  hw/xbox/nv2a

sed -n '180,280p' hw/xbox/nv2a/pfifo.c
sed -n '280,380p' hw/xbox/nv2a/pfifo.c

rg -n "SCHEDULER|scheduler|PFIFO.*LIMIT|pfifo.*limit|scheduler_state|XEMU_BOOT_TRACE.*PFIFO|xemu_boot_trace.*pfifo" \
  hw/xbox/nv2a/pfifo.c xemu-xbe.c scripts browser ui docker meson.build

git diff -- \
  hw/xbox/nv2a/pfifo.c \
  hw/xbox/nv2a/pgraph/pgraph.c \
  hw/xbox/nv2a/user.c \
  hw/xbox/nv2a/nv2a.c
```

Note: the first `rg` command returned exit code 2 because `nv2a*` did not match
a path in the shell command context. The later narrowed commands provided the
authoritative source inspection.

## Inputs / Artifacts

- `hw/xbox/nv2a/pfifo.c`
- `hw/xbox/nv2a/pgraph/pgraph.c`
- `hw/xbox/nv2a/user.c`
- `hw/xbox/nv2a/nv2a.c`
- `scripts/xbox-pfifo-scheduler-state-classify.py`

## Loop-Guard Field

- `pfifo_scheduler_kick_source_patch_scope`

## Findings

The marker-only source-tagging patch scope is already present in the current
worktree.

Relevant source facts:

- `pfifo_boot_trace_scheduler_state()` emits
  `BOOT_MARK b6 pfifo=scheduler ... op=<op> kick_source=<source> ...`.
- The scheduler marker is gated by boot tracing, dashboard loaded state, and
  `XEMU_BOOT_TRACE_NV2A_PFIFO_SCHEDULER_LIMIT`.
- The default scheduler marker limit is `128`, so a runtime should not need a
  new browser fixture knob just to emit the first bounded scheduler events.
- `pfifo_kick_with_source()` sets `fifo_kick`, emits
  `pfifo=scheduler op=kick kick_source=<source>`, and broadcasts the existing
  PFIFO condition. This is marker-only relative to `pfifo_kick()`.
- `pfifo_thread()` already emits scheduler state around thread loop,
  kick-cleared, pgraph pending, before/after pusher, halt skip, reports, idle
  wait, idle wake, and skip-wait-kicked.
- Call sites already converted to source-tagged kicks include:
  - `pfifo_write`: `pfifo-intr-clear`, `pfifo-intr-enable`,
    `pfifo-register-write`
  - `user_write`: `nv-user-dma-put`, `nv-user-dma-get`, `nv-user-ref`,
    `nv-user-write`
  - `nv2a_unlock_fifo`: `nv2a-unlock-fifo`
  - `pgraph_write`: `pgraph-intr-clear`, `pgraph-increment-read3d`,
    `pgraph-fifo-write`
  - renderer/surface wake paths such as `pgraph-renderer-switch`,
    `gl-display-sync`, `vk-display-sync`, and surface download/flush/resume
    sources
- `scripts/xbox-pfifo-scheduler-state-classify.py` already parses
  `kick_source` and reports `first_kick_after_last_opportunity_source`.

The `git diff` shows these PFIFO/PGRAPH/user/nv2a changes are uncommitted
worktree changes, not changes made during this inspection.

## Decision

No additional source-tagging code patch is needed for the selected field. The
next bounded action should be build-only verification of the existing
marker-only PFIFO scheduler source-tag changes before any runtime.

## Next Step

Run the required bounded loop check. If it agrees, run a Podman WASM build only
to ensure the existing marker-only PFIFO scheduler source-tag changes compile
into `build-wasm-pic`.
