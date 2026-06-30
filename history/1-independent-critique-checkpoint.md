# Independent Critique Checkpoint

## Purpose

- One new fact this run was supposed to produce: whether adding a high-reasoning
  sub-agent critique checkpoint is feasible and how to structure it so it
  prevents B6 loops without becoming another loop.

## Command(s)

```text
tool_search: multi-agent spawn subagent model reasoning critique
multi_agent_v1.spawn_agent:
  agent_type=explorer
  model=gpt-5.5
  reasoning_effort=xhigh
  service_tier=priority
  task=review AGENTS.md, goal.md, and xbox-browser-boot-plan.md; recommend where
       to place the checkpoint, triggers, exact questions/prompt, and meta-loop
       guardrails; do not edit files
multi_agent_v1.wait_agent:
  target=019f1891-3008-7803-adb0-ae301befe52a
```

## Inputs And Artifacts

- Baseline native log: not applicable.
- Baseline browser log: not applicable.
- Output directory/log: this history entry and the updated docs.
- Fixture assumptions: none.
- Reviewed docs: `AGENTS.md`, `goal.md`, `xbox-browser-boot-plan.md`.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: none of the emulator
  evidence fields. This was a process checkpoint to reduce repeated unproductive
  runs before future evidence work.

## Findings

- Result: pass.
- Important reviewer findings:
  - Put the checkpoint in `goal.md` immediately after the loop guard.
  - Treat the checkpoint as a pre-run gate, not a B6 evidence gate.
  - Trigger it after two non-progress experiments, before repeating
    historical/negative-control territory, before weakening strict B6, when
    scope broadens away from browser-side pre-service tick accumulation, or when
    artifact roles/next actions contradict each other.
  - Use a bounded prompt that asks whether we are looping, the narrowest next
    fact that changes B6, which hypothesis to kill/keep/revise, whether the
    proposed run passes the loop guard, and one better experiment if any.
  - Make the checkpoint single-shot per trigger; do not recursively spawn
    critique agents.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No
  emulator run was performed.

## Decision

- Status: current.
- Why: the checkpoint was added to `goal.md`, summarized in `AGENTS.md`, and
  referenced from `xbox-browser-boot-plan.md`.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: add a GPT-5.5/xhigh checkpoint as a bounded pre-run
  anti-loop gate, with exact trigger conditions and a single-shot rule.

## Next Step

- Narrow follow-up: use the checkpoint only when its trigger conditions occur;
  otherwise continue with the current B6 metric, moving
  `pre_service_browser_first_watch_read_ticks` from browser 0 toward native 136.
