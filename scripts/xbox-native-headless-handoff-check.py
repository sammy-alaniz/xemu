#!/usr/bin/env python3
"""Summarize the native headless handoff state for B6 work."""

import argparse
import re
import sys
from collections import Counter
from dataclasses import dataclass, field


MARKER_RE = re.compile(r'(\S+)=(".*?"|\S+)')


def parse_value(value):
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    return value


def parse_marker(line):
    return {key: parse_value(value) for key, value in MARKER_RE.findall(line)}


def bool_word(value):
    return "yes" if value else "no"


def int_value(value, default=0):
    try:
        return int(value, 0)
    except (TypeError, ValueError):
        return default


def is_nonzero(value):
    return int_value(value) != 0


def edge_for(marker, start_key="start_pc", next_key="next_pc"):
    start_pc = marker.get(start_key, "none")
    next_pc = marker.get(next_key, "none")
    if start_pc == "none" and next_pc == "none":
        return "none"
    return f"{start_pc}->{next_pc}"


def b6_kind(marker):
    for key in (
        "dashboard",
        "pfifo",
        "pgraph",
        "cpu",
        "pic",
        "pit",
        "main-loop",
        "ac97",
        "pm",
        "nv2a",
    ):
        if key in marker:
            return f"{key}={marker[key]}"
    return "unknown"


def is_strict_xbe_executed(marker, context):
    if marker.get("dashboard") != "xbe-executed":
        return False
    if marker.get("context") != context:
        return False
    if marker.get("phys_match") != "yes":
        return False
    return bool(int_value(marker.get("section_flags")) & 0x4)


def is_pusher_empty(marker):
    if marker.get("pfifo") != "window":
        return False
    if marker.get("op") != "pusher-empty":
        return False
    dma_get = marker.get("dma_get", "none")
    dma_put = marker.get("dma_put", "none")
    return dma_get != "none" and dma_get == dma_put


@dataclass
class HandoffSummary:
    label: str
    path: str
    context: str
    qemu_launch_seen: bool = False
    short_animation: bool = False
    display_none: bool = False
    audio_none: bool = False
    boot_result_reason: str = "missing"
    boot_elapsed_ms: str = "missing"
    boot_exit: str = "missing"
    b6_markers: int = 0
    last_b6_line: int = 0
    last_b6_kind: str = "none"
    last_b6_eip: str = "none"
    entry: str = "unknown"
    entry_ready_line: int = 0
    detector_line: int = 0
    detector_proof: str = "missing"
    detector_cpu_eip: str = "none"
    strict_xbe_executed_count: int = 0
    first_strict_line: int = 0
    first_strict_pc: str = "none"
    native_reference: str = "missing"
    exec_probe_count: int = 0
    exec_probe_phys_match_yes: int = 0
    exec_edge_count: int = 0
    exec_edge_phys_match_yes: int = 0
    first_exec_edge_line: int = 0
    first_exec_edge: str = "none"
    direct_entry_pc_seen: bool = False
    direct_entry_next_seen: bool = False
    direct_entry_branch_seen: bool = False
    kernel_loop_count: int = 0
    after_idle_loop_count: int = 0
    after_idle_edges: Counter = field(default_factory=Counter)
    first_after_idle_line: int = 0
    first_after_idle_edge: str = "none"
    latest_after_idle_line: int = 0
    latest_after_idle_edge: str = "none"
    latest_after_idle_eip: str = "none"
    latest_after_idle_esp: str = "none"
    latest_after_idle_cpu_interrupt_request: str = "none"
    latest_after_idle_pending_interrupt: str = "unknown"
    after_idle_cpu_interrupt_nonzero: int = 0
    first_after_idle_cpu_interrupt_line: int = 0
    first_after_idle_cpu_interrupt: str = "none"
    pusher_empty_count: int = 0
    stream_idle_boundary_count: int = 0
    first_stream_idle_line: int = 0
    latest_stream_idle_line: int = 0
    latest_stream_idle_eip: str = "none"
    latest_stream_idle_esp: str = "none"
    latest_stream_idle_cpu_interrupt_request: str = "none"
    latest_stream_idle_pending_interrupt: str = "unknown"
    latest_stream_idle_irq_inhibited: str = "unknown"
    latest_stream_idle_last_transition: str = "none"
    ac97_callback_count: int = 0
    ac97_callback_after_stream_idle: int = 0
    pm_timer_count: int = 0
    pm_timer_after_stream_idle: int = 0

    def headless_launch(self):
        return self.display_none and self.audio_none

    def update_entry(self, marker):
        entry = (
            marker.get("entry")
            or marker.get("guest_entry")
            or marker.get("guest_pc")
            or "unknown"
        )
        if entry != "unknown":
            self.entry = entry

    def check_direct_entry(self, marker):
        if self.entry == "unknown":
            return
        if any(
            marker.get(field) == self.entry
            for field in ("guest_pc", "start_pc", "site_pc")
        ):
            self.direct_entry_pc_seen = True
        if marker.get("next_pc") == self.entry:
            self.direct_entry_next_seen = True
        if any(
            marker.get(field) == self.entry
            for field in ("branch_target", "next_branch_target", "start_branch_target")
        ):
            self.direct_entry_branch_seen = True

    def add_exec_edge(self, line_no, marker):
        self.exec_edge_count += 1
        if not self.first_exec_edge_line:
            self.first_exec_edge_line = line_no
            self.first_exec_edge = edge_for(marker)
        if (
            marker.get("start_phys_match") == "yes"
            or marker.get("next_phys_match") == "yes"
            or marker.get("next_branch_phys_match") == "yes"
        ):
            self.exec_edge_phys_match_yes += 1
        self.check_direct_entry(marker)

    def add_after_idle_loop(self, line_no, marker):
        self.after_idle_loop_count += 1
        edge = edge_for(marker)
        self.after_idle_edges[edge] += 1
        if not self.first_after_idle_line:
            self.first_after_idle_line = line_no
            self.first_after_idle_edge = edge
        self.latest_after_idle_line = line_no
        self.latest_after_idle_edge = edge
        self.latest_after_idle_eip = marker.get("eip", "none")
        self.latest_after_idle_esp = marker.get("esp", "none")
        self.latest_after_idle_cpu_interrupt_request = marker.get(
            "cpu_interrupt_request", "none"
        )
        self.latest_after_idle_pending_interrupt = marker.get(
            "pending_interrupt", "unknown"
        )

        cpu_interrupt = marker.get("cpu_interrupt_request", "0x00000000")
        if is_nonzero(cpu_interrupt):
            self.after_idle_cpu_interrupt_nonzero += 1
            if not self.first_after_idle_cpu_interrupt_line:
                self.first_after_idle_cpu_interrupt_line = line_no
                self.first_after_idle_cpu_interrupt = cpu_interrupt

    def add_stream_idle_boundary(self, line_no, marker):
        self.stream_idle_boundary_count += 1
        if not self.first_stream_idle_line:
            self.first_stream_idle_line = line_no
        self.latest_stream_idle_line = line_no
        self.latest_stream_idle_eip = marker.get("eip", "none")
        self.latest_stream_idle_esp = marker.get("esp", "none")
        self.latest_stream_idle_cpu_interrupt_request = marker.get(
            "cpu_interrupt_request", "none"
        )
        self.latest_stream_idle_pending_interrupt = marker.get(
            "pending_interrupt", "unknown"
        )
        self.latest_stream_idle_irq_inhibited = marker.get("irq_inhibited", "unknown")
        self.latest_stream_idle_last_transition = edge_for(
            marker, "last_transition_start_pc", "last_transition_next_pc"
        )

    def top_after_idle_edge(self):
        if not self.after_idle_edges:
            return "none", 0
        edge, count = self.after_idle_edges.most_common(1)[0]
        return edge, count

    def actual_execution(self):
        return self.strict_xbe_executed_count > 0

    def terminal_state(self):
        if self.actual_execution() and self.native_reference == "pass":
            return "dashboard-executed-with-native-reference"
        if self.actual_execution():
            return "dashboard-executed-no-native-reference"
        if (
            self.detector_proof == "pass"
            and self.boot_result_reason == "timeout"
            and self.stream_idle_boundary_count
            and self.after_idle_loop_count
        ):
            return "native-headless-timeout-after-stream-idle"
        if self.detector_proof == "pass" and self.boot_result_reason == "timeout":
            return "native-headless-timeout-before-stream-idle"
        if self.detector_proof == "pass":
            return "detector-proof-no-actual-execution"
        if self.b6_markers:
            return "native-headless-b6-without-detector-proof"
        return "no-b6-handoff-evidence"


def parse_log(path, label, context):
    summary = HandoffSummary(label=label, path=path, context=context)

    try:
        with open(path, "r", encoding="utf-8", errors="replace") as log:
            for line_no, raw_line in enumerate(log, 1):
                line = raw_line.rstrip("\n")
                if "Created QEMU launch parameters:" in line:
                    summary.qemu_launch_seen = True
                    summary.short_animation = "short-animation=on" in line
                    summary.display_none = " -display none" in line
                    summary.audio_none = " -audio none" in line
                    continue

                if line.startswith("BOOT_SMOKE_RESULT "):
                    marker = parse_marker(line)
                    summary.boot_result_reason = marker.get("reason", "missing")
                    summary.boot_elapsed_ms = marker.get("elapsed_ms", "missing")
                    summary.boot_exit = marker.get("exit", "missing")
                    continue

                if line.startswith("NATIVE_DASHBOARD_REFERENCE "):
                    marker = parse_marker(line)
                    if marker.get("context") == context:
                        summary.native_reference = marker.get("result", "missing")
                    continue

                if "BOOT_MARK b6 " not in line:
                    continue

                marker = parse_marker(line)
                if marker.get("context") != context:
                    continue

                summary.b6_markers += 1
                summary.last_b6_line = line_no
                summary.last_b6_kind = b6_kind(marker)
                summary.last_b6_eip = marker.get("eip", summary.last_b6_eip)

                if is_pusher_empty(marker):
                    summary.pusher_empty_count += 1

                if marker.get("pfifo") == "stream-idle-boundary":
                    summary.add_stream_idle_boundary(line_no, marker)

                if marker.get("ac97") == "callback":
                    summary.ac97_callback_count += 1
                    if summary.stream_idle_boundary_count or summary.pusher_empty_count:
                        summary.ac97_callback_after_stream_idle += 1

                if marker.get("pit") == "irq-timer" or marker.get("pm") in (
                    "timer",
                    "pm-timer",
                    "pm1-update",
                ):
                    summary.pm_timer_count += 1
                    if summary.stream_idle_boundary_count or summary.pusher_empty_count:
                        summary.pm_timer_after_stream_idle += 1

                dashboard = marker.get("dashboard", "none")
                if dashboard == "xbe-entry-probe" and marker.get("status") == "ready":
                    summary.entry_ready_line = line_no
                    summary.update_entry(marker)
                elif dashboard == "xbe-executed-detector-proof":
                    summary.detector_line = line_no
                    summary.detector_proof = marker.get("result", "missing")
                    summary.detector_cpu_eip = marker.get("eip", "none")
                    summary.update_entry(marker)
                elif dashboard == "xbe-executed":
                    summary.check_direct_entry(marker)
                    if is_strict_xbe_executed(marker, context):
                        summary.strict_xbe_executed_count += 1
                        if not summary.first_strict_line:
                            summary.first_strict_line = line_no
                            summary.first_strict_pc = marker.get("guest_pc", "none")
                elif dashboard == "xbe-exec-probe":
                    summary.exec_probe_count += 1
                    if marker.get("phys_match") == "yes":
                        summary.exec_probe_phys_match_yes += 1
                    summary.check_direct_entry(marker)
                elif dashboard in ("xbe-exec-edge", "xbe-exec-transition"):
                    summary.add_exec_edge(line_no, marker)
                elif dashboard == "kernel-loop-probe":
                    summary.kernel_loop_count += 1
                    if (
                        summary.stream_idle_boundary_count > 0
                        or summary.pusher_empty_count > 0
                        or marker.get("stream_idle") == "yes"
                    ):
                        summary.add_after_idle_loop(line_no, marker)
    except OSError as exc:
        raise RuntimeError(f"log unreadable: {exc}") from exc

    return summary


def emit_summary(summary):
    top_after_idle_edge, top_after_idle_count = summary.top_after_idle_edge()
    result = "pass" if summary.b6_markers else "fail"
    reason = (
        "native-headless-handoff-summarized"
        if summary.b6_markers
        else "missing-native-headless-b6-markers"
    )
    fields = {
        "result": result,
        "reason": reason,
        "label": summary.label,
        "context": summary.context,
        "terminal_state": summary.terminal_state(),
        "actual_xbe_executed": bool_word(summary.actual_execution()),
        "detector_proof": summary.detector_proof,
        "native_reference": summary.native_reference,
        "entry": summary.entry,
        "entry_ready_line": summary.entry_ready_line,
        "detector_line": summary.detector_line,
        "detector_cpu_eip": summary.detector_cpu_eip,
        "strict_xbe_executed_count": summary.strict_xbe_executed_count,
        "first_strict_line": summary.first_strict_line,
        "first_strict_pc": summary.first_strict_pc,
        "direct_entry_pc": bool_word(summary.direct_entry_pc_seen),
        "direct_entry_next": bool_word(summary.direct_entry_next_seen),
        "direct_entry_branch": bool_word(summary.direct_entry_branch_seen),
        "exec_probe_count": summary.exec_probe_count,
        "exec_probe_phys_match_yes": summary.exec_probe_phys_match_yes,
        "exec_edge_count": summary.exec_edge_count,
        "exec_edge_phys_match_yes": summary.exec_edge_phys_match_yes,
        "first_exec_edge_line": summary.first_exec_edge_line,
        "first_exec_edge": summary.first_exec_edge,
        "kernel_loop_count": summary.kernel_loop_count,
        "after_idle_loop_count": summary.after_idle_loop_count,
        "after_idle_top_edge": top_after_idle_edge,
        "after_idle_top_edge_count": top_after_idle_count,
        "first_after_idle_line": summary.first_after_idle_line,
        "first_after_idle_edge": summary.first_after_idle_edge,
        "latest_after_idle_line": summary.latest_after_idle_line,
        "latest_after_idle_edge": summary.latest_after_idle_edge,
        "latest_after_idle_eip": summary.latest_after_idle_eip,
        "latest_after_idle_esp": summary.latest_after_idle_esp,
        "latest_after_idle_cpu_interrupt_request": (
            summary.latest_after_idle_cpu_interrupt_request
        ),
        "latest_after_idle_pending_interrupt": (
            summary.latest_after_idle_pending_interrupt
        ),
        "after_idle_cpu_interrupt_nonzero": (
            summary.after_idle_cpu_interrupt_nonzero
        ),
        "first_after_idle_cpu_interrupt_line": (
            summary.first_after_idle_cpu_interrupt_line
        ),
        "first_after_idle_cpu_interrupt": summary.first_after_idle_cpu_interrupt,
        "pusher_empty_count": summary.pusher_empty_count,
        "stream_idle_boundary_count": summary.stream_idle_boundary_count,
        "first_stream_idle_line": summary.first_stream_idle_line,
        "latest_stream_idle_line": summary.latest_stream_idle_line,
        "latest_stream_idle_eip": summary.latest_stream_idle_eip,
        "latest_stream_idle_esp": summary.latest_stream_idle_esp,
        "latest_stream_idle_cpu_interrupt_request": (
            summary.latest_stream_idle_cpu_interrupt_request
        ),
        "latest_stream_idle_pending_interrupt": (
            summary.latest_stream_idle_pending_interrupt
        ),
        "latest_stream_idle_irq_inhibited": (
            summary.latest_stream_idle_irq_inhibited
        ),
        "latest_stream_idle_last_transition": (
            summary.latest_stream_idle_last_transition
        ),
        "ac97_callback_count": summary.ac97_callback_count,
        "ac97_callback_after_stream_idle": (
            summary.ac97_callback_after_stream_idle
        ),
        "pm_timer_count": summary.pm_timer_count,
        "pm_timer_after_stream_idle": summary.pm_timer_after_stream_idle,
        "qemu_launch_seen": bool_word(summary.qemu_launch_seen),
        "headless_launch": bool_word(summary.headless_launch()),
        "short_animation": bool_word(summary.short_animation),
        "display_none": bool_word(summary.display_none),
        "audio_none": bool_word(summary.audio_none),
        "boot_result_reason": summary.boot_result_reason,
        "boot_elapsed_ms": summary.boot_elapsed_ms,
        "boot_exit": summary.boot_exit,
        "last_b6_line": summary.last_b6_line,
        "last_b6_kind": summary.last_b6_kind,
        "last_b6_eip": summary.last_b6_eip,
        "log": summary.path,
    }
    print(
        "NATIVE_HEADLESS_HANDOFF "
        + " ".join(f"{key}={value}" for key, value in fields.items())
    )
    return 0 if result == "pass" else 1


def emit_compare(primary, compare):
    same_terminal = primary.terminal_state() == compare.terminal_state()
    both_actual = primary.actual_execution() and compare.actual_execution()
    either_actual = primary.actual_execution() or compare.actual_execution()
    fields = {
        "result": "pass",
        "reason": "native-headless-handoff-compared",
        "primary_label": primary.label,
        "compare_label": compare.label,
        "primary_terminal_state": primary.terminal_state(),
        "compare_terminal_state": compare.terminal_state(),
        "same_terminal_state": bool_word(same_terminal),
        "primary_actual_xbe_executed": bool_word(primary.actual_execution()),
        "compare_actual_xbe_executed": bool_word(compare.actual_execution()),
        "both_actual_xbe_executed": bool_word(both_actual),
        "either_actual_xbe_executed": bool_word(either_actual),
        "primary_short_animation": bool_word(primary.short_animation),
        "compare_short_animation": bool_word(compare.short_animation),
        "short_animation_changed": bool_word(
            primary.short_animation != compare.short_animation
        ),
        "primary_detector_cpu_eip": primary.detector_cpu_eip,
        "compare_detector_cpu_eip": compare.detector_cpu_eip,
        "primary_first_exec_edge": primary.first_exec_edge,
        "compare_first_exec_edge": compare.first_exec_edge,
        "primary_latest_stream_idle_eip": primary.latest_stream_idle_eip,
        "compare_latest_stream_idle_eip": compare.latest_stream_idle_eip,
        "primary_latest_stream_idle_cpu_interrupt_request": (
            primary.latest_stream_idle_cpu_interrupt_request
        ),
        "compare_latest_stream_idle_cpu_interrupt_request": (
            compare.latest_stream_idle_cpu_interrupt_request
        ),
        "primary_log": primary.path,
        "compare_log": compare.path,
    }
    print(
        "NATIVE_HEADLESS_HANDOFF_COMPARE "
        + " ".join(f"{key}={value}" for key, value in fields.items())
    )
    return 0


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Summarize native headless B6 handoff evidence without reading "
            "proprietary asset bytes."
        )
    )
    parser.add_argument("log", help="native boot-smoke log to inspect")
    parser.add_argument("--context", default="native-headless")
    parser.add_argument("--label", default="primary")
    parser.add_argument("--compare-log", default="")
    parser.add_argument("--compare-label", default="compare")
    args = parser.parse_args()

    try:
        primary = parse_log(args.log, args.label, args.context)
        primary_status = emit_summary(primary)
        compare_status = 0
        if args.compare_log:
            compare = parse_log(args.compare_log, args.compare_label, args.context)
            compare_status = emit_summary(compare)
            emit_compare(primary, compare)
    except RuntimeError as exc:
        print(
            "NATIVE_HEADLESS_HANDOFF "
            f"result=fail reason=unreadable-log context={args.context} "
            f"error={str(exc).replace(' ', '_')} log={args.log}",
            file=sys.stderr,
        )
        return 2

    if primary_status != 0 or compare_status != 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
