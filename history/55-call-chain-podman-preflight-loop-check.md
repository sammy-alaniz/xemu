# Call Chain Podman Preflight Loop Check

1. Are we looping? If yes, which repeated action or assumption proves it?

No for the user-requested explanatory call-chain experiment. The repeated
mistake was assuming the local shell build tools were the only build path after
the repo instructions pointed to `/tmp/xemu-podman-wrapper`. The latest preflight
does not repeat a B3/B4/B5, native-reference, visual-comparison, pump-placement,
vblank, or precommit run; it failed before emulation because fixture env vars
were omitted.

2. What is the narrowest next fact that would change the B6 boundary?

For the real B6 boundary, the narrowest next fact remains
`first_kick_after_last_opportunity_source` from source-tagged PFIFO scheduler
markers. The call-chain smoke can only explain whether the rebuilt binary reaches
the attempted execution-marker path.

3. Which hypothesis should be killed, kept, or revised?

Kill the hypothesis that call-chain markers prove B6 or move the tick metric.
Keep the hypothesis that they are useful explanatory instrumentation for the
broad path from `main()` to `xemu_xbe_boot_trace_mark_executed()`. Revise the run
procedure to use the documented Podman wrapper plus fixture env values.

4. Is the proposed next run justified by the loop guard? Name the exact field it can change or explain.

Yes, narrowly, because it completes the user-requested explanatory experiment
that already had a successful Podman build and a fixture-only preflight failure.
The exact field it can explain is
`call_chain_trace_reaches_mark_executed_attempt`.

5. What is one better experiment, if any, and what single loop-guard field would it change?

The better B6 experiment is the source-tagged PFIFO scheduler run. Its single
loop-guard field is `first_kick_after_last_opportunity_source`.

Decision: continue
