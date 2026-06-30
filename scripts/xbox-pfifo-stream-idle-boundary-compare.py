#!/usr/bin/env python3
"""Compare native/browser CPU state at the PFIFO stream-idle boundary."""

import argparse
import re
import sys
from dataclasses import dataclass, field


MARKER_RE = re.compile(r'(\S+)=(".*?"|\S+)')


def parse_value(value):
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    return value


def parse_marker(line):
    return {key: parse_value(value) for key, value in MARKER_RE.findall(line)}


def marker_context_matches(marker, context):
    return not context or marker.get("context") == context


def bool_word(value):
    return "yes" if value else "no"


def is_pfifo_stream_idle_window(marker):
    if marker.get("pfifo") != "window":
        return False
    if marker.get("op") != "pusher-empty":
        return False
    dma_get = marker.get("dma_get")
    return bool(dma_get) and dma_get == marker.get("dma_put")


def is_stream_idle_loop(marker):
    if marker.get("dashboard") != "kernel-loop-probe":
        return False
    if marker.get("stream_idle") == "yes":
        return True
    return (
        marker.get("nv2a_wait_source") == "pfifo-window"
        and marker.get("nv2a_wait_op") == "pusher-empty"
        and marker.get("nv2a_dma_get")
        and marker.get("nv2a_dma_get") == marker.get("nv2a_dma_put")
    )


def loop_key(marker):
    if not marker:
        return "missing"
    return (
        f"{marker.get('start_pc', 'none')}->{marker.get('next_pc', 'none')}"
        f":{marker.get('loop_kind', 'none')}"
        f":if={marker.get('interrupts_enabled', 'unknown')}"
        f":inh={marker.get('irq_inhibited', 'unknown')}"
        f":irq={marker.get('cpu_interrupt_request', 'none')}"
        f":pending={marker.get('pending_interrupt', 'unknown')}"
    )


def boundary_key(marker):
    if not marker:
        return "missing"
    return (
        f"eip={marker.get('eip', 'none')}"
        f":if={marker.get('interrupts_enabled', 'unknown')}"
        f":inh={marker.get('irq_inhibited', 'unknown')}"
        f":irq={marker.get('cpu_interrupt_request', 'none')}"
        f":last={marker.get('last_transition_start_pc', 'none')}"
        f"->{marker.get('last_transition_next_pc', 'none')}"
        f":last_known={marker.get('last_transition_next_pc_known', 'unknown')}"
    )


def transition_key(marker):
    if not marker:
        return "missing"
    return (
        f"get={marker.get('dma_get_before', 'none')}"
        f"->{marker.get('dma_get_after', 'none')}"
        f":put={marker.get('dma_put', 'none')}"
        f":method={marker.get('method', 'none')}"
        f":processed={marker.get('processed', 'none')}"
        f":eip={marker.get('eip', 'none')}"
        f":if={marker.get('interrupts_enabled', 'unknown')}"
        f":inh={marker.get('irq_inhibited', 'unknown')}"
        f":irq={marker.get('cpu_interrupt_request', 'none')}"
        f":last={marker.get('last_transition_start_pc', 'none')}"
        f"->{marker.get('last_transition_next_pc', 'none')}"
        f":last_known={marker.get('last_transition_next_pc_known', 'unknown')}"
    )


def marker_line(marker):
    return marker.get("_line", "0") if marker else "0"


@dataclass
class BoundarySummary:
    label: str
    path: str
    idle_window_count: int = 0
    stream_idle_loop_count: int = 0
    first_idle_window: dict = field(default_factory=dict)
    first_transition: dict = field(default_factory=dict)
    first_boundary: dict = field(default_factory=dict)
    first_stream_idle_loop: dict = field(default_factory=dict)


def parse_log(path, label, context):
    summary = BoundarySummary(label=label, path=path)

    try:
        with open(path, "r", encoding="utf-8", errors="replace") as log:
            for line_no, raw_line in enumerate(log, 1):
                if "BOOT_MARK b6 " not in raw_line:
                    continue
                marker = parse_marker(raw_line)
                if not marker_context_matches(marker, context):
                    continue
                marker["_line"] = str(line_no)

                if is_pfifo_stream_idle_window(marker):
                    summary.idle_window_count += 1
                    if not summary.first_idle_window:
                        summary.first_idle_window = marker
                    continue

                if marker.get("pfifo") == "stream-idle-transition":
                    if not summary.first_transition:
                        summary.first_transition = marker
                    continue

                if marker.get("pfifo") == "stream-idle-boundary":
                    if not summary.first_boundary:
                        summary.first_boundary = marker
                    continue

                if is_stream_idle_loop(marker):
                    summary.stream_idle_loop_count += 1
                    if not summary.first_stream_idle_loop:
                        summary.first_stream_idle_loop = marker
                    continue
    except OSError as exc:
        raise RuntimeError(f"{label} log unreadable: {exc}") from exc

    return summary


def divergence_for(native, browser):
    if not native.first_idle_window or not browser.first_idle_window:
        return "missing-pfifo-idle-window"
    if native.first_transition and browser.first_transition:
        if transition_key(native.first_transition) == transition_key(
            browser.first_transition
        ):
            return "transition-match"
        return "transition-cpu-state-mismatch"
    if native.first_transition or browser.first_transition:
        return "transition-marker-presence-mismatch"
    if native.first_boundary and browser.first_boundary:
        if boundary_key(native.first_boundary) == boundary_key(browser.first_boundary):
            return "boundary-match"
        return "boundary-cpu-state-mismatch"
    if native.first_boundary or browser.first_boundary:
        return "boundary-marker-presence-mismatch"
    if not native.first_stream_idle_loop or not browser.first_stream_idle_loop:
        return "missing-stream-idle-loop"
    if loop_key(native.first_stream_idle_loop) == loop_key(
        browser.first_stream_idle_loop
    ):
        return "first-stream-idle-loop-match"
    return "first-stream-idle-loop-mismatch"


def emit(native, browser):
    divergence = divergence_for(native, browser)
    hard_fail = divergence in {
        "missing-pfifo-idle-window",
        "missing-stream-idle-loop",
        "transition-marker-presence-mismatch",
        "boundary-marker-presence-mismatch",
    }
    result = "fail" if hard_fail else "pass"
    native_idle_seq = native.first_idle_window.get("seq", "none")
    browser_idle_seq = browser.first_idle_window.get("seq", "none")
    native_boundary = "present" if native.first_boundary else "missing"
    browser_boundary = "present" if browser.first_boundary else "missing"
    native_transition = "present" if native.first_transition else "missing"
    browser_transition = "present" if browser.first_transition else "missing"
    native_transition_match = (
        native.first_transition
        and browser.first_transition
        and transition_key(native.first_transition)
        == transition_key(browser.first_transition)
    )
    native_boundary_match = (
        native.first_boundary
        and browser.first_boundary
        and boundary_key(native.first_boundary) == boundary_key(browser.first_boundary)
    )
    loop_phase_match = (
        native.first_stream_idle_loop
        and browser.first_stream_idle_loop
        and loop_key(native.first_stream_idle_loop)
        == loop_key(browser.first_stream_idle_loop)
    )

    print(
        "PFIFO_STREAM_IDLE_BOUNDARY_COMPARE"
        f" result={result}"
        f" divergence={divergence}"
        f" native_idle_windows={native.idle_window_count}"
        f" browser_idle_windows={browser.idle_window_count}"
        f" native_idle_seq={native_idle_seq}"
        f" browser_idle_seq={browser_idle_seq}"
        f" native_transition={native_transition}"
        f" browser_transition={browser_transition}"
        f" transition_cpu_match={bool_word(native_transition_match)}"
        f" native_transition_line={marker_line(native.first_transition)}"
        f" browser_transition_line={marker_line(browser.first_transition)}"
        f" native_transition_key={transition_key(native.first_transition)}"
        f" browser_transition_key={transition_key(browser.first_transition)}"
        f" native_boundary={native_boundary}"
        f" browser_boundary={browser_boundary}"
        f" boundary_cpu_match={bool_word(native_boundary_match)}"
        f" native_boundary_line={marker_line(native.first_boundary)}"
        f" browser_boundary_line={marker_line(browser.first_boundary)}"
        f" native_boundary_key={boundary_key(native.first_boundary)}"
        f" browser_boundary_key={boundary_key(browser.first_boundary)}"
        f" native_stream_idle_loops={native.stream_idle_loop_count}"
        f" browser_stream_idle_loops={browser.stream_idle_loop_count}"
        f" loop_phase_match={bool_word(loop_phase_match)}"
        f" native_first_loop_line={marker_line(native.first_stream_idle_loop)}"
        f" browser_first_loop_line={marker_line(browser.first_stream_idle_loop)}"
        f" native_first_loop={loop_key(native.first_stream_idle_loop)}"
        f" browser_first_loop={loop_key(browser.first_stream_idle_loop)}"
    )
    return 1 if hard_fail else 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=(
            "Compare native/browser CPU state at PFIFO pusher-empty stream-idle."
        )
    )
    parser.add_argument("--native-log", required=True)
    parser.add_argument("--browser-log", required=True)
    parser.add_argument("--native-context", default="")
    parser.add_argument("--browser-context", default="")
    args = parser.parse_args(argv)

    try:
        native = parse_log(args.native_log, "native", args.native_context)
        browser = parse_log(args.browser_log, "browser", args.browser_context)
    except RuntimeError as exc:
        print(
            "PFIFO_STREAM_IDLE_BOUNDARY_COMPARE"
            f" result=fail reason={str(exc).replace(' ', '-')}"
        )
        return 1

    return emit(native, browser)


if __name__ == "__main__":
    sys.exit(main())
