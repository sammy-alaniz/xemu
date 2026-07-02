# Deterministic M1 Loop Check

1. Are we looping? If yes, which repeated action or assumption proves it?

Not yet. The deterministic run changed the primary metric from
`pre_service_browser_first_watch_read_ticks=0` to 2. It would become a loop to
rerun or raise deterministic timer steps while ignoring the new regression:
`POST_SERVICE_WATCH_EDGE_COMPARE result=fail
divergence=missing-browser-post-edge`.

2. What is the narrowest next fact that changes the current boundary?

Whether deterministic pumping can preserve the prior useful browser
post-service edge `0x80030e84->0x80030f31` while still moving
`pre_service_browser_first_watch_read_ticks` above 0.

3. Which hypothesis should be killed, kept, or revised?

Kill: raw deterministic timer stepping alone is sufficient for M1/B6.

Keep: deterministic mode is useful diagnostic evidence because it moved the
pre-service tick metric.

Revise: deterministic pumping must be gated or ordered so it advances the
watched timer word without disrupting post-idle/post-service CPU flow.

4. Is the proposed next step justified by the loop guard? Name the exact field
it can change or explain.

Yes, but only if the next step targets the regression. The loop-guard field is
`post_service_watch_edge`, specifically `missing-browser-post-edge`. It may also
explain whether the `pre_service_browser_first_watch_read_ticks=2` improvement
is compatible with the old post-service flow.

5. What is one better experiment or code slice, if any, and what field would it
change?

Add a narrow deterministic variant that preserves the previous ready-edge plus
host-fallback ordering but limits deterministic timer dispatch to the smallest
window before the first watched read, then compare
`pre_service_browser_first_watch_read_ticks` and `post_service_watch_edge`.

revise
