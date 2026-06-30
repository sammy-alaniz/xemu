#!/usr/bin/env python3
"""Cluster native/browser B6 post-command kernel-loop diagnostics."""

import argparse
import sys
from collections import Counter
from dataclasses import dataclass


def line_value(line, key, default=""):
    prefix = f"{key}="
    for token in line.split():
        if token.startswith(prefix):
            return token[len(prefix):].strip('"')
    return default


def bool_word(value):
    return "yes" if value else "no"


def nonzero_value(value):
    if value in ("", "none", "unknown"):
        return False
    try:
        return int(value, 0) != 0
    except ValueError:
        return value not in ("0", "0x00000000")


@dataclass(frozen=True)
class LoopKey:
    start_pc: str
    next_pc: str
    tb_size: str
    tb_exit: str


@dataclass(frozen=True)
class WaitKey:
    source: str
    op: str


@dataclass
class LoopSummary:
    label: str
    lines: list
    edge_counts: Counter
    wait_counts: Counter
    latest_line: str = ""

    @classmethod
    def empty(cls, label):
        return cls(label=label, lines=[], edge_counts=Counter(), wait_counts=Counter())

    def add(self, line):
        edge = LoopKey(
            line_value(line, "start_pc", "none"),
            line_value(line, "next_pc", "none"),
            line_value(line, "tb_size", "none"),
            line_value(line, "tb_exit", "none"),
        )
        wait = WaitKey(
            line_value(line, "nv2a_wait_source", "none"),
            line_value(line, "nv2a_wait_op", "none"),
        )
        self.lines.append(line)
        self.edge_counts[edge] += 1
        self.wait_counts[wait] += 1
        self.latest_line = line

    def top_edge(self):
        if not self.edge_counts:
            return LoopKey("none", "none", "none", "none"), 0, ""
        key, count = self.edge_counts.most_common(1)[0]
        return key, count, self.latest_for_edge(key)

    def top_wait(self):
        if not self.wait_counts:
            return WaitKey("none", "none"), 0
        key, count = self.wait_counts.most_common(1)[0]
        return key, count

    def latest_for_edge(self, edge):
        for line in reversed(self.lines):
            if (
                line_value(line, "start_pc", "none") == edge.start_pc
                and line_value(line, "next_pc", "none") == edge.next_pc
                and line_value(line, "tb_size", "none") == edge.tb_size
                and line_value(line, "tb_exit", "none") == edge.tb_exit
            ):
                return line
        return ""

    def repeat_count(self):
        return sum(1 for count in self.edge_counts.values() if count > 1)

    def count_nonzero(self, key):
        return sum(1 for line in self.lines if nonzero_value(line_value(line, key)))

    def count_value(self, key, expected):
        return sum(1 for line in self.lines if line_value(line, key) == expected)

    def first_with_nonzero(self, key):
        for line in self.lines:
            if nonzero_value(line_value(line, key)):
                return line
        return ""

    def latest_with_nonzero(self, key):
        for line in reversed(self.lines):
            if nonzero_value(line_value(line, key)):
                return line
        return ""


@dataclass
class ParsedLoopLog:
    label: str
    all_loops: LoopSummary
    after_idle_loops: LoopSummary
    stream_idle_count: int = 0
    first_idle_line_no: int = 0
    latest_idle_line_no: int = 0

    @classmethod
    def empty(cls, label):
        return cls(
            label=label,
            all_loops=LoopSummary.empty(f"{label}-all"),
            after_idle_loops=LoopSummary.empty(f"{label}-after-idle"),
        )

    def stream_idle_seen(self):
        return self.stream_idle_count > 0


def fail(reason, **fields):
    parts = [f"POST_COMMAND_LOOP_CLUSTERS result=fail reason={reason}"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts), file=sys.stderr)
    return 1


def is_stream_idle_pfifo_window(line):
    if not line.startswith("BOOT_MARK b6 pfifo=window "):
        return False
    if line_value(line, "op", "none") != "pusher-empty":
        return False
    dma_get = line_value(line, "dma_get", "none")
    dma_put = line_value(line, "dma_put", "none")
    return dma_get != "none" and dma_get == dma_put


def parse_log(path, label, context):
    parsed = ParsedLoopLog.empty(label)

    try:
        with open(path, "r", encoding="utf-8", errors="replace") as log:
            for line_no, raw_line in enumerate(log, 1):
                line = raw_line.rstrip("\n")
                if context and f"context={context}" not in line:
                    continue
                if is_stream_idle_pfifo_window(line):
                    parsed.stream_idle_count += 1
                    if not parsed.first_idle_line_no:
                        parsed.first_idle_line_no = line_no
                    parsed.latest_idle_line_no = line_no
                if line.startswith("BOOT_MARK b6 dashboard=kernel-loop-probe "):
                    parsed.all_loops.add(line)
                    if (
                        parsed.stream_idle_seen()
                        or line_value(line, "stream_idle", "no") == "yes"
                    ):
                        parsed.after_idle_loops.add(line)
    except OSError as exc:
        raise RuntimeError(f"{label} log unreadable: {exc}") from exc

    return parsed


def divergence_for(native, browser):
    native_edge, _, native_line = native.top_edge()
    browser_edge, _, browser_line = browser.top_edge()
    if native_edge == browser_edge:
        return "same-top-edge"
    native_wait, _ = native.top_wait()
    browser_wait, _ = browser.top_wait()
    if native_wait != browser_wait:
        return "wait-source-mismatch"
    if line_value(native_line, "next_mem_region", "none") != line_value(
        browser_line, "next_mem_region", "none"
    ):
        return "memory-poll-mismatch"
    return "edge-mismatch"


def after_idle_divergence_for(native, browser):
    if not native.lines and not browser.lines:
        return "no-after-idle-loop-samples"
    if not native.lines:
        return "native-no-after-idle-loop-samples"
    if not browser.lines:
        return "browser-no-after-idle-loop-samples"
    return divergence_for(native, browser)


def after_idle_cpu_interrupt_divergence_for(native, browser):
    native_count = native.count_nonzero("cpu_interrupt_request")
    browser_count = browser.count_nonzero("cpu_interrupt_request")

    if native_count and not browser_count:
        return "native-only-after-idle-cpu-interrupt"
    if browser_count and not native_count:
        return "browser-only-after-idle-cpu-interrupt"
    if native_count and browser_count:
        return "both-after-idle-cpu-interrupt"
    return "no-after-idle-cpu-interrupt"


def shared_edge_fields(prefix, native, browser):
    native_edges = set(native.edge_counts)
    browser_edges = set(browser.edge_counts)
    shared_edges = native_edges & browser_edges
    shared_start_pcs = {
        edge.start_pc for edge in native_edges
    } & {edge.start_pc for edge in browser_edges}
    shared_next_pcs = {
        edge.next_pc for edge in native_edges
    } & {edge.next_pc for edge in browser_edges}

    return {
        f"{prefix}shared_edges": len(shared_edges),
        f"{prefix}shared_start_pcs": len(shared_start_pcs),
        f"{prefix}shared_next_pcs": len(shared_next_pcs),
        f"{prefix}same_top_edge": bool_word(native.top_edge()[0] == browser.top_edge()[0]),
    }


def add_side_fields(fields, prefix, summary):
    top_edge, top_count, top_line = summary.top_edge()
    top_wait, top_wait_count = summary.top_wait()
    latest_line = summary.latest_line
    first_cpu_interrupt_line = summary.first_with_nonzero("cpu_interrupt_request")
    latest_cpu_interrupt_line = summary.latest_with_nonzero("cpu_interrupt_request")

    fields.update(
        {
            f"{prefix}_samples": len(summary.lines),
            f"{prefix}_unique_edges": len(summary.edge_counts),
            f"{prefix}_repeating_edges": summary.repeat_count(),
            f"{prefix}_top_edge_count": top_count,
            f"{prefix}_top_start": top_edge.start_pc,
            f"{prefix}_top_next": top_edge.next_pc,
            f"{prefix}_top_tb_size": top_edge.tb_size,
            f"{prefix}_top_tb_exit": top_edge.tb_exit,
            f"{prefix}_top_loop_kind": line_value(top_line, "loop_kind", "none"),
            f"{prefix}_top_start_hash": line_value(
                top_line, "start_code_hash", "none"
            ),
            f"{prefix}_top_start_opcode": line_value(
                top_line, "start_opcode", "none"
            ),
            f"{prefix}_top_next_hash": line_value(top_line, "next_code_hash", "none"),
            f"{prefix}_top_next_opcode": line_value(top_line, "next_opcode", "none"),
            f"{prefix}_top_next_mem_region": line_value(
                top_line, "next_mem_region", "none"
            ),
            f"{prefix}_top_next_mem_value_read": line_value(
                top_line, "next_mem_value_read", "unknown"
            ),
            f"{prefix}_top_wait_source": line_value(
                top_line, "nv2a_wait_source", "none"
            ),
            f"{prefix}_top_wait_op": line_value(top_line, "nv2a_wait_op", "none"),
            f"{prefix}_top_cpu_mode": line_value(top_line, "cpu_mode", "none"),
            f"{prefix}_top_cpl": line_value(top_line, "cpl", "none"),
            f"{prefix}_top_cs": line_value(top_line, "cs", "none"),
            f"{prefix}_top_esp": line_value(top_line, "esp", "none"),
            f"{prefix}_top_eflags": line_value(top_line, "eflags", "none"),
            f"{prefix}_top_interrupts_enabled": line_value(
                top_line, "interrupts_enabled", "unknown"
            ),
            f"{prefix}_top_irq_inhibited": line_value(
                top_line, "irq_inhibited", "unknown"
            ),
            f"{prefix}_top_cpu_interrupt_request": line_value(
                top_line, "cpu_interrupt_request", "none"
            ),
            f"{prefix}_top_pending_interrupt": line_value(
                top_line, "pending_interrupt", "unknown"
            ),
            f"{prefix}_top_cpu_exit_request": line_value(
                top_line, "cpu_exit_request", "unknown"
            ),
            f"{prefix}_dominant_wait_source": top_wait.source,
            f"{prefix}_dominant_wait_op": top_wait.op,
            f"{prefix}_dominant_wait_count": top_wait_count,
            f"{prefix}_latest_start": line_value(latest_line, "start_pc", "none"),
            f"{prefix}_latest_next": line_value(latest_line, "next_pc", "none"),
            f"{prefix}_latest_loop_kind": line_value(
                latest_line, "loop_kind", "none"
            ),
            f"{prefix}_latest_wait_source": line_value(
                latest_line, "nv2a_wait_source", "none"
            ),
            f"{prefix}_latest_wait_op": line_value(
                latest_line, "nv2a_wait_op", "none"
            ),
            f"{prefix}_latest_esp": line_value(latest_line, "esp", "none"),
            f"{prefix}_latest_eflags": line_value(latest_line, "eflags", "none"),
            f"{prefix}_latest_interrupts_enabled": line_value(
                latest_line, "interrupts_enabled", "unknown"
            ),
            f"{prefix}_latest_irq_inhibited": line_value(
                latest_line, "irq_inhibited", "unknown"
            ),
            f"{prefix}_latest_cpu_interrupt_request": line_value(
                latest_line, "cpu_interrupt_request", "none"
            ),
            f"{prefix}_latest_pending_interrupt": line_value(
                latest_line, "pending_interrupt", "unknown"
            ),
            f"{prefix}_latest_cpu_exit_request": line_value(
                latest_line, "cpu_exit_request", "unknown"
            ),
            f"{prefix}_latest_next_mem_region": line_value(
                latest_line, "next_mem_region", "none"
            ),
            f"{prefix}_latest_next_mem_value_read": line_value(
                latest_line, "next_mem_value_read", "unknown"
            ),
            f"{prefix}_cpu_interrupt_nonzero": summary.count_nonzero(
                "cpu_interrupt_request"
            ),
            f"{prefix}_pending_interrupt_yes": summary.count_value(
                "pending_interrupt", "yes"
            ),
            f"{prefix}_cpu_exit_request_yes": summary.count_value(
                "cpu_exit_request", "yes"
            ),
            f"{prefix}_irq_inhibited_yes": summary.count_value(
                "irq_inhibited", "yes"
            ),
            f"{prefix}_interrupts_disabled": summary.count_value(
                "interrupts_enabled", "no"
            ),
            f"{prefix}_first_cpu_interrupt_request": line_value(
                first_cpu_interrupt_line, "cpu_interrupt_request", "none"
            ),
            f"{prefix}_first_cpu_interrupt_start": line_value(
                first_cpu_interrupt_line, "start_pc", "none"
            ),
            f"{prefix}_first_cpu_interrupt_next": line_value(
                first_cpu_interrupt_line, "next_pc", "none"
            ),
            f"{prefix}_first_cpu_interrupt_tbs": line_value(
                first_cpu_interrupt_line, "observed_tbs", "none"
            ),
            f"{prefix}_latest_cpu_interrupt_nonzero_request": line_value(
                latest_cpu_interrupt_line, "cpu_interrupt_request", "none"
            ),
            f"{prefix}_latest_cpu_interrupt_nonzero_start": line_value(
                latest_cpu_interrupt_line, "start_pc", "none"
            ),
            f"{prefix}_latest_cpu_interrupt_nonzero_next": line_value(
                latest_cpu_interrupt_line, "next_pc", "none"
            ),
            f"{prefix}_latest_cpu_interrupt_nonzero_tbs": line_value(
                latest_cpu_interrupt_line, "observed_tbs", "none"
            ),
        }
    )


def add_parsed_side_fields(fields, prefix, parsed):
    fields.update(
        {
            f"{prefix}_stream_idle_seen": bool_word(parsed.stream_idle_seen()),
            f"{prefix}_stream_idle_count": parsed.stream_idle_count,
            f"{prefix}_first_idle_line": parsed.first_idle_line_no or "none",
            f"{prefix}_latest_idle_line": parsed.latest_idle_line_no or "none",
        }
    )
    add_side_fields(fields, prefix, parsed.all_loops)
    add_side_fields(fields, f"{prefix}_after_idle", parsed.after_idle_loops)


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Cluster native/browser B6 kernel-loop probes without reading or "
            "dumping proprietary asset bytes."
        )
    )
    parser.add_argument("--native-log", required=True)
    parser.add_argument("--browser-log", required=True)
    parser.add_argument("--native-context", default="native-headless")
    parser.add_argument("--browser-context", default="browser-runtime")
    args = parser.parse_args()

    try:
        native_log = parse_log(args.native_log, "native", args.native_context)
        browser_log = parse_log(args.browser_log, "browser", args.browser_context)
    except RuntimeError as exc:
        return fail(str(exc).replace(" ", "-"))

    native = native_log.all_loops
    browser = browser_log.all_loops
    if not native.lines:
        return fail("missing-native-kernel-loop", native_log=args.native_log)
    if not browser.lines:
        return fail("missing-browser-kernel-loop", browser_log=args.browser_log)

    fields = {
        "divergence": divergence_for(native, browser),
        "after_idle_divergence": after_idle_divergence_for(
            native_log.after_idle_loops,
            browser_log.after_idle_loops,
        ),
        "after_idle_cpu_interrupt_divergence": (
            after_idle_cpu_interrupt_divergence_for(
                native_log.after_idle_loops,
                browser_log.after_idle_loops,
            )
        ),
    }
    fields.update(shared_edge_fields("", native, browser))
    fields.update(
        shared_edge_fields(
            "after_idle_",
            native_log.after_idle_loops,
            browser_log.after_idle_loops,
        )
    )
    add_parsed_side_fields(fields, "native", native_log)
    add_parsed_side_fields(fields, "browser", browser_log)
    fields.update(
        {
            "native_log": args.native_log,
            "browser_log": args.browser_log,
        }
    )

    parts = ["POST_COMMAND_LOOP_CLUSTERS result=pass"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
