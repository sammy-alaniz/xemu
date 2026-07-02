# Call Chain Trace Loop Check

1. Are we looping? If yes, which repeated action or assumption proves it?

No. The call-chain trace is a user-requested explanatory probe, not another
B3/B4/B5, native-reference, visual-comparison, pump-placement, vblank, or
precommit rerun. It does not claim B6 progress by itself.

2. What is the narrowest next fact that would change the B6 boundary?

The narrowest next fact is whether a current build with
`XEMU_BOOT_TRACE_CALL_CHAIN=1` shows the expected ordered path reaching
`xemu_xbe_boot_trace_observe_exec()` and then attempting
`xemu_xbe_boot_trace_mark_executed()` after dashboard XBE load.

3. Which hypothesis should be killed, kept, or revised?

Keep the hypothesis that call-chain markers are useful explanatory context for
humans reading the B6 execution path. Kill any hypothesis that these markers
prove B6, dashboard execution, or movement in the primary tick metric. Revise
the implementation scope if unrelated timer-opportunity changes are part of the
same diff; the call-chain experiment should stay isolated from B6 causal
instrumentation.

4. Is the proposed next run justified by the loop guard? Name the exact field it can change or explain.

Only partly. A short build/run is justified for the user-requested call-chain
experiment, but it is outside the current B6 loop-guard fields unless treated as
an explanatory field: `call_chain_trace_reaches_mark_executed_attempt`. It
cannot change `pre_service_browser_first_watch_read_ticks`,
`browser_shared_memory_poll_ticks`, `browser_post_service_top_edge`,
`browser_xbe_executed`, `kick_sources_before_first_opportunity`, or
`first_kick_after_last_opportunity_source`.

5. What is one better experiment, if any, and what single loop-guard field would it change?

The better B6 experiment is still the focused source-tagged PFIFO scheduler run,
not the call-chain smoke. Its single loop-guard field is
`first_kick_after_last_opportunity_source`.

Decision: revise
