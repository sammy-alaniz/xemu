# 270 - Progress-Method Critique Process Check

## Purpose

Verify whether bounded sub-agent loop checks already require a critique of our
progress methods, as requested by the user.

## Commands

```sh
rg -n "loop check|Loop check|loop-check|critique|Progress-Method|progress method|exact prompt|sub-agent|subagent" goal.md AGENTS.md history/0-template.md
git status --short
```

## Inputs / Artifacts

- `AGENTS.md`
- `goal.md`
- `history/0-template.md`

## Loop-Guard Field

- `loop_check_progress_method_critique_required`

## Findings

- `AGENTS.md` already requires every sub-agent loop check to include a concise
  `Progress-Method Critique` section.
- `goal.md` already states that every sub-agent loop-check prompt must include
  that critique, including ordinary post-history loop checks.
- `history/0-template.md` already has fields for recording whether the critique
  was included and summarizing it.

## Decision

No additional edit is needed for this request. The process requirement is
already present in the active working tree.

## Next Step

Run the required bounded sub-agent loop check before any further experiment,
probe, run, or code change.
