#!/usr/bin/env python3
"""Summarize whether a native B6 log proves actual dashboard XBE execution."""

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


def bool_word(value):
    return "yes" if value else "no"


def int_value(value, default=0):
    try:
        return int(value, 0)
    except (TypeError, ValueError):
        return default


def is_nonzero(value):
    return int_value(value) != 0


def is_strict_xbe_executed(marker, context):
    if marker.get("dashboard") != "xbe-executed":
        return False
    if marker.get("context") != context:
        return False
    if marker.get("phys_match") != "yes":
        return False
    return bool(int_value(marker.get("section_flags")) & 0x4)


def edge_for(marker):
    start_pc = marker.get("start_pc", "none")
    next_pc = marker.get("next_pc", "none")
    if start_pc == "none" and next_pc == "none":
        return "none"
    return f"{start_pc}->{next_pc}"


def marker_context_matches(marker, context):
    return marker.get("context") == context


def is_stream_idle_pfifo_window(marker):
    if marker.get("pfifo") != "window":
        return False
    if marker.get("op") != "pusher-empty":
        return False
    dma_get = marker.get("dma_get", "none")
    dma_put = marker.get("dma_put", "none")
    return dma_get != "none" and dma_get == dma_put


@dataclass
class Summary:
    context: str
    path: str
    entry: str = "unknown"
    entry_ready_line: int = 0
    detector_line: int = 0
    detector_proof: str = "missing"
    detector_cpu_eip: str = "none"
    strict_xbe_executed_count: int = 0
    first_strict_line: int = 0
    first_strict_pc: str = "none"
    exec_probe_count: int = 0
    exec_probe_phys_match_yes: int = 0
    exec_probe_not_applicable: int = 0
    exec_probe_high_alias_mismatch: int = 0
    exec_edge_count: int = 0
    exec_edge_start_phys_match_yes: int = 0
    exec_edge_next_phys_match_yes: int = 0
    exec_edge_branch_phys_match_yes: int = 0
    exec_transition_count: int = 0
    exec_transition_start_phys_match_yes: int = 0
    exec_transition_next_phys_match_yes: int = 0
    exec_transition_branch_phys_match_yes: int = 0
    entry_target_count: int = 0
    entry_target_phys_match_yes: int = 0
    dispatch_count: int = 0
    dispatch_reg_phys_match_positive: int = 0
    dispatch_stack_phys_match_positive: int = 0
    direct_entry_pc_seen: bool = False
    direct_entry_next_seen: bool = False
    direct_entry_branch_seen: bool = False
    first_exec_probe_pc: str = "none"
    first_exec_probe_line: int = 0
    first_exec_edge: str = "none"
    first_exec_edge_line: int = 0
    first_exec_transition: str = "none"
    first_exec_transition_line: int = 0
    first_after_idle_edge: str = "none"
    first_after_idle_line: int = 0
    latest_after_idle_edge: str = "none"
    latest_after_idle_line: int = 0
    after_idle_edges: int = 0
    after_idle_cpu_interrupt_nonzero: int = 0
    first_after_idle_cpu_interrupt: str = "none"
    first_after_idle_cpu_interrupt_line: int = 0
    stream_idle_count: int = 0
    first_stream_idle_line: int = 0
    latest_stream_idle_line: int = 0
    reasons: list = field(default_factory=list)

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
        pc_fields = ("guest_pc", "start_pc", "site_pc")
        next_fields = ("next_pc",)
        branch_fields = ("branch_target", "next_branch_target", "start_branch_target")

        if any(marker.get(field) == self.entry for field in pc_fields):
            self.direct_entry_pc_seen = True
        if any(marker.get(field) == self.entry for field in next_fields):
            self.direct_entry_next_seen = True
        if any(marker.get(field) == self.entry for field in branch_fields):
            self.direct_entry_branch_seen = True

    def add_exec_probe(self, line_no, marker):
        self.exec_probe_count += 1
        if not self.first_exec_probe_line:
            self.first_exec_probe_line = line_no
            self.first_exec_probe_pc = marker.get("guest_pc", "none")
        if marker.get("phys_match") == "yes":
            self.exec_probe_phys_match_yes += 1
        if marker.get("phys_match") == "not-applicable":
            self.exec_probe_not_applicable += 1
        if marker.get("address_mode") == "high-alias-mismatch":
            self.exec_probe_high_alias_mismatch += 1
        self.check_direct_entry(marker)

    def add_exec_edge(self, line_no, marker):
        self.exec_edge_count += 1
        if not self.first_exec_edge_line:
            self.first_exec_edge_line = line_no
            self.first_exec_edge = edge_for(marker)
        if marker.get("start_phys_match") == "yes":
            self.exec_edge_start_phys_match_yes += 1
        if marker.get("next_phys_match") == "yes":
            self.exec_edge_next_phys_match_yes += 1
        if marker.get("next_branch_phys_match") == "yes":
            self.exec_edge_branch_phys_match_yes += 1
        self.check_direct_entry(marker)

    def add_exec_transition(self, line_no, marker):
        self.exec_transition_count += 1
        if not self.first_exec_transition_line:
            self.first_exec_transition_line = line_no
            self.first_exec_transition = edge_for(marker)
        if marker.get("start_phys_match") == "yes":
            self.exec_transition_start_phys_match_yes += 1
        if marker.get("next_phys_match") == "yes":
            self.exec_transition_next_phys_match_yes += 1
        if marker.get("next_branch_phys_match") == "yes":
            self.exec_transition_branch_phys_match_yes += 1
        self.check_direct_entry(marker)

    def add_entry_target(self, marker):
        self.entry_target_count += 1
        if marker.get("target_phys_match") == "yes":
            self.entry_target_phys_match_yes += 1
        self.check_direct_entry(marker)

    def add_dispatch(self, marker):
        self.dispatch_count += 1
        if int_value(marker.get("reg_phys_match_count")) > 0:
            self.dispatch_reg_phys_match_positive += 1
        if int_value(marker.get("stack_phys_match_count")) > 0:
            self.dispatch_stack_phys_match_positive += 1
        self.check_direct_entry(marker)

    def add_after_idle_loop(self, line_no, marker):
        self.after_idle_edges += 1
        edge = edge_for(marker)
        if not self.first_after_idle_line:
            self.first_after_idle_line = line_no
            self.first_after_idle_edge = edge
        self.latest_after_idle_line = line_no
        self.latest_after_idle_edge = edge

        cpu_interrupt = marker.get("cpu_interrupt_request", "0x00000000")
        if is_nonzero(cpu_interrupt):
            self.after_idle_cpu_interrupt_nonzero += 1
            if not self.first_after_idle_cpu_interrupt_line:
                self.first_after_idle_cpu_interrupt_line = line_no
                self.first_after_idle_cpu_interrupt = cpu_interrupt

    def result(self):
        if self.strict_xbe_executed_count:
            return "pass", "strict-dashboard-executed"
        if self.detector_proof != "pass":
            return "fail", "missing-detector-proof"
        return "fail", "no-strict-dashboard-executed-marker"


def parse_log(path, context):
    summary = Summary(context=context, path=path)

    try:
        with open(path, "r", encoding="utf-8", errors="replace") as log:
            for line_no, raw_line in enumerate(log, 1):
                if "BOOT_MARK b6 " not in raw_line:
                    continue
                marker = parse_marker(raw_line)
                if not marker_context_matches(marker, context):
                    continue

                if is_stream_idle_pfifo_window(marker):
                    summary.stream_idle_count += 1
                    if not summary.first_stream_idle_line:
                        summary.first_stream_idle_line = line_no
                    summary.latest_stream_idle_line = line_no

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
                    summary.add_exec_probe(line_no, marker)
                elif dashboard == "xbe-exec-edge":
                    summary.add_exec_edge(line_no, marker)
                elif dashboard == "xbe-exec-transition":
                    summary.add_exec_transition(line_no, marker)
                elif dashboard == "xbe-entry-target-probe":
                    summary.add_entry_target(marker)
                elif dashboard == "xbe-dispatch-probe":
                    summary.add_dispatch(marker)
                elif dashboard == "kernel-loop-probe" and (
                    summary.stream_idle_count > 0 or marker.get("stream_idle") == "yes"
                ):
                    summary.add_after_idle_loop(line_no, marker)
    except OSError as exc:
        raise RuntimeError(f"log unreadable: {exc}") from exc

    return summary


def emit(summary):
    result, reason = summary.result()
    fields = {
        "result": result,
        "reason": reason,
        "context": summary.context,
        "detector_proof": summary.detector_proof,
        "strict_xbe_executed": bool_word(summary.strict_xbe_executed_count > 0),
        "strict_xbe_executed_count": summary.strict_xbe_executed_count,
        "entry": summary.entry,
        "entry_ready_line": summary.entry_ready_line,
        "detector_line": summary.detector_line,
        "detector_cpu_eip": summary.detector_cpu_eip,
        "first_strict_line": summary.first_strict_line,
        "first_strict_pc": summary.first_strict_pc,
        "exec_probe_count": summary.exec_probe_count,
        "exec_probe_phys_match_yes": summary.exec_probe_phys_match_yes,
        "exec_probe_high_alias_mismatch": summary.exec_probe_high_alias_mismatch,
        "exec_probe_not_applicable": summary.exec_probe_not_applicable,
        "exec_edge_count": summary.exec_edge_count,
        "exec_edge_start_phys_match_yes": summary.exec_edge_start_phys_match_yes,
        "exec_edge_next_phys_match_yes": summary.exec_edge_next_phys_match_yes,
        "exec_edge_branch_phys_match_yes": summary.exec_edge_branch_phys_match_yes,
        "exec_transition_count": summary.exec_transition_count,
        "exec_transition_start_phys_match_yes": summary.exec_transition_start_phys_match_yes,
        "exec_transition_next_phys_match_yes": summary.exec_transition_next_phys_match_yes,
        "exec_transition_branch_phys_match_yes": summary.exec_transition_branch_phys_match_yes,
        "entry_target_count": summary.entry_target_count,
        "entry_target_phys_match_yes": summary.entry_target_phys_match_yes,
        "dispatch_count": summary.dispatch_count,
        "dispatch_reg_phys_match_positive": summary.dispatch_reg_phys_match_positive,
        "dispatch_stack_phys_match_positive": summary.dispatch_stack_phys_match_positive,
        "direct_entry_pc": bool_word(summary.direct_entry_pc_seen),
        "direct_entry_next": bool_word(summary.direct_entry_next_seen),
        "direct_entry_branch": bool_word(summary.direct_entry_branch_seen),
        "first_exec_probe_line": summary.first_exec_probe_line,
        "first_exec_probe_pc": summary.first_exec_probe_pc,
        "first_exec_edge_line": summary.first_exec_edge_line,
        "first_exec_edge": summary.first_exec_edge,
        "first_exec_transition_line": summary.first_exec_transition_line,
        "first_exec_transition": summary.first_exec_transition,
        "stream_idle_count": summary.stream_idle_count,
        "first_stream_idle_line": summary.first_stream_idle_line,
        "latest_stream_idle_line": summary.latest_stream_idle_line,
        "after_idle_edges": summary.after_idle_edges,
        "after_idle_cpu_interrupt_nonzero": summary.after_idle_cpu_interrupt_nonzero,
        "first_after_idle_cpu_interrupt_line": summary.first_after_idle_cpu_interrupt_line,
        "first_after_idle_cpu_interrupt": summary.first_after_idle_cpu_interrupt,
        "first_after_idle_line": summary.first_after_idle_line,
        "first_after_idle_edge": summary.first_after_idle_edge,
        "latest_after_idle_line": summary.latest_after_idle_line,
        "latest_after_idle_edge": summary.latest_after_idle_edge,
        "log": summary.path,
    }
    print(
        "NATIVE_ACTUAL_XBE_EXECUTION "
        + " ".join(f"{key}={value}" for key, value in fields.items())
    )
    return 0 if result == "pass" else 1


def main():
    parser = argparse.ArgumentParser(
        description="Check whether a B6 log has accepted native dashboard XBE execution."
    )
    parser.add_argument("log", help="B6 boot-smoke log to inspect")
    parser.add_argument(
        "--context",
        default="native-headless",
        help="marker context to inspect (default: native-headless)",
    )
    args = parser.parse_args()

    try:
        summary = parse_log(args.log, args.context)
    except RuntimeError as exc:
        print(
            "NATIVE_ACTUAL_XBE_EXECUTION "
            f"result=fail reason=unreadable-log context={args.context} "
            f"error={str(exc).replace(' ', '_')} log={args.log}",
            file=sys.stderr,
        )
        return 2

    return emit(summary)


if __name__ == "__main__":
    sys.exit(main())
