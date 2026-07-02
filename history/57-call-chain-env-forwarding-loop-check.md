# Call Chain Env Forwarding Loop Check

1. Are we looping? If yes, which repeated action or assumption proves it?

No for the immediate user-requested call-chain experiment. The repeated bad
assumption was already corrected: local missing `ninja`/`meson` did not block
the build because the repo uses the Podman wrapper. The latest failure is a new
run-procedure issue: `scripts/xbox-boot-smoke.sh` forwards a fixed env allowlist
and did not pass `XEMU_BOOT_TRACE_CALL_CHAIN` to the rebuilt binary.

2. What is the narrowest next fact that would change the B6 boundary?

For the actual B6 boundary, the narrowest next fact remains
`first_kick_after_last_opportunity_source` from source-tagged PFIFO scheduler
markers. The call-chain smoke can only explain whether the rebuilt binary reaches
the attempted execution-marker path when the opt-in flag is really delivered.

3. Which hypothesis should be killed, kept, or revised?

Kill the hypothesis that call-chain markers prove B6 or move the primary tick
metric. Keep the hypothesis that they are useful explanatory instrumentation for
the broad path to `xemu_xbe_boot_trace_mark_executed()`. Revise the run method:
the flag must be passed through Docker/Podman explicitly or added to the smoke
wrapper allowlist.

4. Is the proposed next run justified by the loop guard? Name the exact field it can change or explain.

Yes, narrowly, because it tests a new failure cause from the previous runtime
attempt rather than repeating the same assumption. The exact field it can explain
is `call_chain_trace_reaches_mark_executed_attempt`.

5. What is one better experiment, if any, and what single loop-guard field would it change?

The better B6 experiment is still the source-tagged PFIFO scheduler runtime. Its
single loop-guard field is `first_kick_after_last_opportunity_source`.

Decision: continue
