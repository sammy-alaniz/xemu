#!/usr/bin/env python3
"""Compare post-stream-idle guest producer state from existing B6 logs."""

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


def int_value(value):
    if value in ("", "none", "unknown"):
        return None
    try:
        return int(value, 0)
    except ValueError:
        return None


def bool_word(value):
    return "yes" if value else "no"


def first_token(parts, index, default="none"):
    return parts[index] if index < len(parts) else default


@dataclass(frozen=True)
class EdgeKey:
    start_pc: str
    next_pc: str
    tb_size: str
    tb_exit: str

    def text(self):
        return f"{self.start_pc}->{self.next_pc}/{self.tb_size}/{self.tb_exit}"


@dataclass(frozen=True)
class WaitKey:
    source: str
    op: str

    def text(self):
        return f"{self.source}/{self.op}"


@dataclass
class LogSummary:
    label: str
    context: str
    boundary: int
    lines: int = 0
    strict_xbe_executed: bool = False
    first_boundary_line: int = 0
    first_empty_boundary_line: int = 0
    latest_empty_boundary_line: int = 0
    first_dma_put_gt_boundary_line: int = 0
    first_dma_put_gt_boundary_dma_get: str = "none"
    first_dma_put_gt_boundary_dma_put: str = "none"
    first_dma_put_gt_boundary_kind: str = "none"
    first_dma_put_gt_boundary_op: str = "none"
    first_dma_put_gt_boundary_method: str = "none"
    first_dma_put_gt_boundary_available: str = "none"
    dma_put_gt_boundary_count: int = 0
    pfifo_continuation_count: int = 0
    pgraph_continuation_count: int = 0
    latest_dma_get: str = "none"
    latest_dma_put: str = "none"
    latest_method: str = "none"
    latest_wait_source: str = "none"
    latest_wait_op: str = "none"
    latest_cpu_interrupt_request: str = "none"
    latest_pmc_pending: str = "none"
    latest_pfifo_pending: str = "none"
    latest_pcrtc_pending: str = "none"
    latest_pgraph_pending: str = "none"
    post_loop_count: int = 0
    post_loop_edges: Counter = None
    post_loop_waits: Counter = None
    latest_post_loop_line: str = ""
    first_post_loop_line_no: int = 0
    latest_post_loop_line_no: int = 0

    def __post_init__(self):
        if self.post_loop_edges is None:
            self.post_loop_edges = Counter()
        if self.post_loop_waits is None:
            self.post_loop_waits = Counter()

    def post_start_line(self):
        if self.first_empty_boundary_line:
            return self.first_empty_boundary_line
        if self.first_boundary_line:
            return self.first_boundary_line
        return self.first_dma_put_gt_boundary_line

    def top_edge(self):
        if not self.post_loop_edges:
            return EdgeKey("none", "none", "none", "none"), 0
        return self.post_loop_edges.most_common(1)[0]

    def top_wait(self):
        if not self.post_loop_waits:
            return WaitKey("none", "none"), 0
        return self.post_loop_waits.most_common(1)[0]


def marker_kind(line):
    parts = line.split()
    return first_token(parts, 2)


def fail(reason, **fields):
    parts = [f"POST_STREAM_IDLE_GUEST_PRODUCER_COMPARE result=fail reason={reason}"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts), file=sys.stderr)
    return 1


def parse_log(path, label, context, boundary):
    summary = LogSummary(label=label, context=context, boundary=boundary)

    try:
        with open(path, "r", encoding="utf-8", errors="replace") as log:
            for line_no, raw_line in enumerate(log, 1):
                line = raw_line.rstrip("\n")
                summary.lines = line_no
                if context and f"context={context}" not in line:
                    continue

                if line.startswith("BOOT_MARK b6 dashboard=xbe-executed "):
                    summary.strict_xbe_executed = True

                dma_get = int_value(line_value(line, "dma_get", ""))
                dma_put = int_value(line_value(line, "dma_put", ""))
                if dma_get is not None:
                    summary.latest_dma_get = f"0x{dma_get:08x}"
                if dma_put is not None:
                    summary.latest_dma_put = f"0x{dma_put:08x}"
                method = line_value(line, "method", "")
                if method:
                    summary.latest_method = method

                wait_source = line_value(line, "nv2a_wait_source", "")
                wait_op = line_value(line, "nv2a_wait_op", "")
                if wait_source:
                    summary.latest_wait_source = wait_source
                if wait_op:
                    summary.latest_wait_op = wait_op
                for key, attr in (
                    ("cpu_interrupt_request", "latest_cpu_interrupt_request"),
                    ("nv2a_pmc_pending", "latest_pmc_pending"),
                    ("nv2a_pfifo_pending", "latest_pfifo_pending"),
                    ("nv2a_pcrtc_pending", "latest_pcrtc_pending"),
                    ("nv2a_pgraph_pending", "latest_pgraph_pending"),
                    ("pmc_pending", "latest_pmc_pending"),
                    ("pfifo_pending", "latest_pfifo_pending"),
                    ("pcrtc_pending", "latest_pcrtc_pending"),
                    ("pgraph_pending", "latest_pgraph_pending"),
                ):
                    value = line_value(line, key, "")
                    if value:
                        setattr(summary, attr, value)

                if dma_get == boundary and not summary.first_boundary_line:
                    summary.first_boundary_line = line_no

                if (
                    line.startswith("BOOT_MARK b6 pfifo=window ")
                    and line_value(line, "op", "none") == "pusher-empty"
                    and dma_get == boundary
                    and dma_put == boundary
                ):
                    if not summary.first_empty_boundary_line:
                        summary.first_empty_boundary_line = line_no
                    summary.latest_empty_boundary_line = line_no

                if dma_put is not None and dma_put > boundary:
                    summary.dma_put_gt_boundary_count += 1
                    if line.startswith("BOOT_MARK b6 pfifo="):
                        summary.pfifo_continuation_count += 1
                    if line.startswith("BOOT_MARK b6 pgraph="):
                        summary.pgraph_continuation_count += 1
                    if not summary.first_dma_put_gt_boundary_line:
                        summary.first_dma_put_gt_boundary_line = line_no
                        summary.first_dma_put_gt_boundary_dma_get = (
                            f"0x{dma_get:08x}" if dma_get is not None else "none"
                        )
                        summary.first_dma_put_gt_boundary_dma_put = f"0x{dma_put:08x}"
                        summary.first_dma_put_gt_boundary_kind = marker_kind(line)
                        summary.first_dma_put_gt_boundary_op = line_value(
                            line, "op", "none"
                        )
                        summary.first_dma_put_gt_boundary_method = line_value(
                            line, "method", "none"
                        )
                        summary.first_dma_put_gt_boundary_available = line_value(
                            line, "available", "none"
                        )

                if line.startswith("BOOT_MARK b6 dashboard=kernel-loop-probe "):
                    start_line = summary.post_start_line()
                    if not start_line:
                        continue
                    if line_no < start_line and line_value(line, "stream_idle", "no") != "yes":
                        continue
                    edge = EdgeKey(
                        line_value(line, "start_pc", "none"),
                        line_value(line, "next_pc", "none"),
                        line_value(line, "tb_size", "none"),
                        line_value(line, "tb_exit", "none"),
                    )
                    wait = WaitKey(
                        line_value(line, "nv2a_wait_source", "none"),
                        line_value(line, "nv2a_wait_op", "none"),
                    )
                    summary.post_loop_count += 1
                    summary.post_loop_edges[edge] += 1
                    summary.post_loop_waits[wait] += 1
                    summary.latest_post_loop_line = line
                    if not summary.first_post_loop_line_no:
                        summary.first_post_loop_line_no = line_no
                    summary.latest_post_loop_line_no = line_no
    except OSError as exc:
        raise RuntimeError(f"{label} log unreadable: {exc}") from exc

    return summary


def divergence_for(native, browser):
    native_continues = native.first_dma_put_gt_boundary_line != 0
    browser_continues = browser.first_dma_put_gt_boundary_line != 0
    browser_wait, _ = browser.top_wait()

    if native_continues and not browser_continues:
        if browser_wait == WaitKey("pfifo-window", "pusher-empty"):
            return "browser-empty-pfifo-wait-native-continuation"
        return "browser-no-continuation-native-continuation"
    if browser_continues and not native_continues:
        return "browser-continuation-native-no-continuation"
    if not native_continues and not browser_continues:
        return "no-continuation-in-either"

    native_edge, _ = native.top_edge()
    browser_edge, _ = browser.top_edge()
    if native_edge != browser_edge:
        return "post-boundary-loop-edge-mismatch"
    return "none"


def emit_summary(native, browser, native_log, browser_log):
    divergence = divergence_for(native, browser)
    result = "pass"
    native_edge, native_edge_count = native.top_edge()
    browser_edge, browser_edge_count = browser.top_edge()
    native_wait, native_wait_count = native.top_wait()
    browser_wait, browser_wait_count = browser.top_wait()

    parts = [
        "POST_STREAM_IDLE_GUEST_PRODUCER_COMPARE",
        f"result={result}",
        f"divergence={divergence}",
        f"boundary=0x{native.boundary:08x}",
        f"native_xbe_executed={bool_word(native.strict_xbe_executed)}",
        f"browser_xbe_executed={bool_word(browser.strict_xbe_executed)}",
        f"native_first_boundary_line={native.first_boundary_line}",
        f"browser_first_boundary_line={browser.first_boundary_line}",
        f"native_first_empty_boundary_line={native.first_empty_boundary_line}",
        f"browser_first_empty_boundary_line={browser.first_empty_boundary_line}",
        f"native_first_dma_put_gt_boundary_line={native.first_dma_put_gt_boundary_line}",
        f"browser_first_dma_put_gt_boundary_line={browser.first_dma_put_gt_boundary_line}",
        f"native_first_dma_put_gt_boundary_kind={native.first_dma_put_gt_boundary_kind}",
        f"browser_first_dma_put_gt_boundary_kind={browser.first_dma_put_gt_boundary_kind}",
        f"native_first_dma_put_gt_boundary_op={native.first_dma_put_gt_boundary_op}",
        f"browser_first_dma_put_gt_boundary_op={browser.first_dma_put_gt_boundary_op}",
        f"native_first_dma_put_gt_boundary_method={native.first_dma_put_gt_boundary_method}",
        f"browser_first_dma_put_gt_boundary_method={browser.first_dma_put_gt_boundary_method}",
        f"native_first_dma_put_gt_boundary_dma_get={native.first_dma_put_gt_boundary_dma_get}",
        f"browser_first_dma_put_gt_boundary_dma_get={browser.first_dma_put_gt_boundary_dma_get}",
        f"native_first_dma_put_gt_boundary_dma_put={native.first_dma_put_gt_boundary_dma_put}",
        f"browser_first_dma_put_gt_boundary_dma_put={browser.first_dma_put_gt_boundary_dma_put}",
        f"native_first_dma_put_gt_boundary_available={native.first_dma_put_gt_boundary_available}",
        f"browser_first_dma_put_gt_boundary_available={browser.first_dma_put_gt_boundary_available}",
        f"native_dma_put_gt_boundary_count={native.dma_put_gt_boundary_count}",
        f"browser_dma_put_gt_boundary_count={browser.dma_put_gt_boundary_count}",
        f"native_pfifo_continuation_count={native.pfifo_continuation_count}",
        f"browser_pfifo_continuation_count={browser.pfifo_continuation_count}",
        f"native_pgraph_continuation_count={native.pgraph_continuation_count}",
        f"browser_pgraph_continuation_count={browser.pgraph_continuation_count}",
        f"native_post_loop_count={native.post_loop_count}",
        f"browser_post_loop_count={browser.post_loop_count}",
        f"native_top_post_loop_edge={native_edge.text()}",
        f"browser_top_post_loop_edge={browser_edge.text()}",
        f"native_top_post_loop_edge_count={native_edge_count}",
        f"browser_top_post_loop_edge_count={browser_edge_count}",
        f"native_top_wait={native_wait.text()}",
        f"browser_top_wait={browser_wait.text()}",
        f"native_top_wait_count={native_wait_count}",
        f"browser_top_wait_count={browser_wait_count}",
        f"native_latest_dma_get={native.latest_dma_get}",
        f"browser_latest_dma_get={browser.latest_dma_get}",
        f"native_latest_dma_put={native.latest_dma_put}",
        f"browser_latest_dma_put={browser.latest_dma_put}",
        f"native_latest_method={native.latest_method}",
        f"browser_latest_method={browser.latest_method}",
        f"native_latest_wait={native.latest_wait_source}/{native.latest_wait_op}",
        f"browser_latest_wait={browser.latest_wait_source}/{browser.latest_wait_op}",
        f"native_latest_cpu_interrupt_request={native.latest_cpu_interrupt_request}",
        f"browser_latest_cpu_interrupt_request={browser.latest_cpu_interrupt_request}",
        f"native_latest_pmc_pending={native.latest_pmc_pending}",
        f"browser_latest_pmc_pending={browser.latest_pmc_pending}",
        f"native_latest_pfifo_pending={native.latest_pfifo_pending}",
        f"browser_latest_pfifo_pending={browser.latest_pfifo_pending}",
        f"native_latest_pcrtc_pending={native.latest_pcrtc_pending}",
        f"browser_latest_pcrtc_pending={browser.latest_pcrtc_pending}",
        f"native_latest_pgraph_pending={native.latest_pgraph_pending}",
        f"browser_latest_pgraph_pending={browser.latest_pgraph_pending}",
        f"native_first_post_loop_line={native.first_post_loop_line_no}",
        f"browser_first_post_loop_line={browser.first_post_loop_line_no}",
        f"native_latest_post_loop_line={native.latest_post_loop_line_no}",
        f"browser_latest_post_loop_line={browser.latest_post_loop_line_no}",
        f"native_log={native_log}",
        f"browser_log={browser_log}",
    ]
    print(" ".join(parts))
    return 0


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Compare native/browser guest CPU and wait state after the shared "
            "PFIFO stream-idle/DMA boundary using existing logs only."
        )
    )
    parser.add_argument("--native-log", required=True)
    parser.add_argument("--browser-log", required=True)
    parser.add_argument("--native-context", default="native-headless")
    parser.add_argument("--browser-context", default="browser-runtime")
    parser.add_argument("--boundary", default="0x03881318")
    args = parser.parse_args()

    boundary = int_value(args.boundary)
    if boundary is None:
        return fail("invalid-boundary", boundary=args.boundary)

    try:
        native = parse_log(
            args.native_log, "native", args.native_context, boundary
        )
        browser = parse_log(
            args.browser_log, "browser", args.browser_context, boundary
        )
    except RuntimeError as exc:
        return fail(str(exc))

    if not native.first_boundary_line and not native.first_dma_put_gt_boundary_line:
        return fail("missing-native-boundary", native_log=args.native_log)
    if not browser.first_boundary_line and not browser.first_empty_boundary_line:
        return fail("missing-browser-boundary", browser_log=args.browser_log)

    return emit_summary(native, browser, args.native_log, args.browser_log)


if __name__ == "__main__":
    sys.exit(main())
