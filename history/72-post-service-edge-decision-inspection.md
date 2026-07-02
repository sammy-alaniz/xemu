# Post-Service Edge Decision Inspection

## Purpose

- One new fact this run was supposed to produce: whether existing code and log
  markers already identify why deterministic v1 exits the first focused
  `0x80030e84` block through `0x80030f45` instead of the useful baseline
  `0x80030f31`.

## Command(s)

```sh
sed -n '7000,7350p' xemu-xbe.c
rg -n "0x80030e84|80030e84|80030f31|80030f45|start_opcode|start_modrm|start_branch|tb_exit|kernel-loop-probe" xemu-xbe.c scripts
rg -n "(2733|2734|2735|2736|2738|2739|2741|2755|2569|2570|2572|2583|2585|2586):|0x80030e84|0x80030f31|0x80030f45" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log
rg -n "regs|env->regs|EAX|R_EAX|cpu_get|dump.*reg|x86_cpu" xemu-xbe.c include target/i386 hw ui scripts | head -200
sed -n '1,230p' xemu-xbe.c
sed -n '7350,7485p' xemu-xbe.c
rg -n "struct xemu_xbe_exec_context|computed_eflags|regs\\[|R_E[A-Z]|cpu_known|eflags_raw|xemu_xbe_exec_context" xemu-xbe.c
rg -n "start_pc=0x80030e84 next_pc=0x80030f(31|45)|start_pc=0x80030f31|start_pc=0x80030f43|start_pc=0x80030f45|start_pc=0x80030f60|start_pc=0x80030f82|start_pc=0x80030e4c next_pc=0x80014f32|start_pc=0x80014f32 next_pc=0x80030e84" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log: none.
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Additional browser log:
  `build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log`
- Output directory/log: terminal inspection output only.
- Fixture assumptions: existing logs only; no emulation was started.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `browser_post_service_top_edge`.

## Findings

- Result: existing markers explain the edge shape but not the exact branch
  input.
- Important marker/comparator lines:
  - Baseline useful path: `start_pc=0x80030e84 next_pc=0x80030f31
    tb_size=111 tb_exit=0`, with `start_mem_value=0x00004e20` at line 2572
    and again `start_mem_value=0x00007530` at line 2586.
  - Deterministic v1 divergent path: `start_pc=0x80030e84
    next_pc=0x80030f45 tb_size=111 tb_exit=1`, with
    `start_mem_value=0x00007530` at line 2736.
  - Therefore the watched tick word alone is not the deciding input: baseline
    reaches `0x80030f31` even with the same `0x00007530` watched value that
    deterministic v1 has when it exits to `0x80030f45`.
  - IRQ/NV2A wait state is also not obviously different at the divergent block:
    both useful baseline and deterministic v1 have `cpu_interrupt_request=0`,
    `pending_interrupt=no`, and `nv2a_wait_source=pfifo-window
    nv2a_wait_op=pusher-empty`.
  - The current `dashboard=kernel-loop-probe` marker logs flags and start/next
    decoded operands, but not general registers and not the internal branch
    site inside the `0x80030e84` TB.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not remeasured; this was static inspection of existing artifacts.

## Decision

- Status: current
- Why: the next useful fact is the branch-site input inside the
  `0x80030e84` block, not more timer-count tuning.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: history/71 directed this inspection before any
  scheduling patch; the inspection shows a narrow edge-decision trace is now
  justified.

## Next Step

- Narrow follow-up: run the required loop-check, then add an opt-in
  edge-decision trace for the first `0x80030e84` block that logs general
  registers, flags, watched word, the known `0x80035c34` comparison word, and
  raw code bytes/branch target for the block.
