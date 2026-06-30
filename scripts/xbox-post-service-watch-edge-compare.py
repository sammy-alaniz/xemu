#!/usr/bin/env python3
"""Compare watched-word values around the post-service 0x80030e84 edge."""

import argparse
import re
import sys
from dataclasses import dataclass, field


MARKER_RE = re.compile(r'(\S+)=(".*?"|\S+)')
DEFAULT_WATCH_ADDR = "0x8003a890"
DEFAULT_BLOCK_START = "0x80030e84"
DEFAULT_BLOCK_NEXT = "0x80030f31"
DEFAULT_TICK_UNIT = 0x2710


def parse_value(value):
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    return value


def parse_marker(line):
    return {key: parse_value(value) for key, value in MARKER_RE.findall(line)}


def parse_int(value):
    if not value or value == "none":
        return None
    try:
        return int(value, 0)
    except ValueError:
        return None


def hex32(value):
    if value is None:
        return "none"
    return f"0x{value & 0xffffffff:08x}"


def tick_count(value, tick_unit):
    parsed = parse_int(value)
    if parsed is None or tick_unit == 0 or parsed % tick_unit != 0:
        return None
    return parsed // tick_unit


def text(value):
    return "none" if value is None else str(value)


def bool_text(value):
    return "yes" if value else "no"


def tick_relation(native_ticks, browser_ticks):
    if native_ticks is None or browser_ticks is None:
        return "not-comparable"
    if native_ticks == browser_ticks:
        return "equal"
    if native_ticks > browser_ticks:
        return "browser-behind"
    return "browser-ahead"


def is_stream_idle(marker):
    if marker.get("pfifo") == "stream-idle-transition":
        return marker.get("wait_op") == "pusher-empty-transition"
    if marker.get("pfifo") == "stream-idle-boundary":
        return marker.get("wait_op") == "pusher-empty"
    if marker.get("pfifo") == "window" and marker.get("op") == "pusher-empty":
        dma_get = marker.get("dma_get", "none")
        dma_put = marker.get("dma_put", "none")
        return dma_get != "none" and dma_get == dma_put
    return False


def edge(marker):
    return f"{marker.get('start_pc', 'none')}->{marker.get('next_pc', 'none')}"


@dataclass
class EdgeEvent:
    line_no: int = 0
    marker: dict | None = None
    side: str = "none"

    @property
    def present(self):
        return self.marker is not None

    def value(self):
        if not self.marker or self.side == "none":
            return "none"
        return self.marker.get(f"{self.side}_mem_value", "none")

    def addr(self):
        if not self.marker or self.side == "none":
            return "none"
        return self.marker.get(f"{self.side}_mem_addr", "none")

    def edge(self):
        if not self.marker:
            return "none"
        return edge(self.marker)


@dataclass
class ParsedLog:
    label: str
    path: str
    stream_idle_count: int = 0
    first_stream_idle_line: int = 0
    pre_edge: EdgeEvent = field(default_factory=EdgeEvent)
    post_edge: EdgeEvent = field(default_factory=EdgeEvent)


def matching_mem_side(marker, side, watch_addr):
    return (
        marker.get(f"{side}_mem_value_read") == "yes"
        and marker.get(f"{side}_mem_addr") == watch_addr
    )


def parse_log(path, label, context, watch_addr, block_start, block_next):
    parsed = ParsedLog(label=label, path=path)
    try:
        fh = open(path, "r", encoding="utf-8", errors="replace")
    except OSError as exc:
        raise RuntimeError(f"{label}-log-open-failed:{exc}") from exc

    with fh:
        for line_no, line in enumerate(fh, 1):
            if "BOOT_MARK b6 " not in line:
                continue
            marker = parse_marker(line)
            if context and marker.get("context") != context:
                continue
            if is_stream_idle(marker):
                parsed.stream_idle_count += 1
                if parsed.first_stream_idle_line == 0:
                    parsed.first_stream_idle_line = line_no
                continue
            if marker.get("dashboard") != "kernel-loop-probe":
                continue
            if marker.get("stream_idle") != "yes" and (
                parsed.first_stream_idle_line == 0
                or line_no < parsed.first_stream_idle_line
            ):
                continue

            if (
                not parsed.pre_edge.present
                and marker.get("next_pc") == block_start
                and matching_mem_side(marker, "next", watch_addr)
            ):
                parsed.pre_edge = EdgeEvent(line_no, marker, "next")
                continue

            if (
                parsed.pre_edge.present
                and not parsed.post_edge.present
                and marker.get("start_pc") == block_start
                and marker.get("next_pc") == block_next
                and matching_mem_side(marker, "start", watch_addr)
            ):
                parsed.post_edge = EdgeEvent(line_no, marker, "start")

    return parsed


def value_delta(pre_value, post_value):
    pre = parse_int(pre_value)
    post = parse_int(post_value)
    if pre is None or post is None:
        return None
    return post - pre


def result_line(native, browser, watch_addr, tick_unit):
    native_pre_value = native.pre_edge.value()
    browser_pre_value = browser.pre_edge.value()
    native_post_value = native.post_edge.value()
    browser_post_value = browser.post_edge.value()

    native_pre_ticks = tick_count(native_pre_value, tick_unit)
    browser_pre_ticks = tick_count(browser_pre_value, tick_unit)
    native_post_ticks = tick_count(native_post_value, tick_unit)
    browser_post_ticks = tick_count(browser_post_value, tick_unit)

    native_delta = value_delta(native_pre_value, native_post_value)
    browser_delta = value_delta(browser_pre_value, browser_post_value)
    native_delta_ticks = None if native_delta is None else tick_count(hex32(native_delta), tick_unit)
    browser_delta_ticks = None if browser_delta is None else tick_count(hex32(browser_delta), tick_unit)
    block_delta_match = (
        native_delta is not None
        and browser_delta is not None
        and native_delta == browser_delta
    )

    missing = []
    for parsed in (native, browser):
        if not parsed.pre_edge.present:
            missing.append(f"{parsed.label}-pre-edge")
        if not parsed.post_edge.present:
            missing.append(f"{parsed.label}-post-edge")
    if missing:
        result = "fail"
        divergence = "missing-" + ",".join(missing)
    elif native_delta != browser_delta:
        result = "pass"
        divergence = "block-watch-delta-mismatch"
    elif native_pre_value != browser_pre_value:
        result = "pass"
        divergence = "pre-block-watch-value-mismatch"
    elif native_post_value != browser_post_value:
        result = "pass"
        divergence = "post-block-watch-value-mismatch"
    else:
        result = "pass"
        divergence = "none"

    pre_tick_delta = (
        None
        if native_pre_ticks is None or browser_pre_ticks is None
        else abs(native_pre_ticks - browser_pre_ticks)
    )
    post_tick_delta = (
        None
        if native_post_ticks is None or browser_post_ticks is None
        else abs(native_post_ticks - browser_post_ticks)
    )

    fields = [
        "POST_SERVICE_WATCH_EDGE_COMPARE",
        f"result={result}",
        f"divergence={divergence}",
        f"watch_addr={watch_addr}",
        f"tick_unit=0x{tick_unit:08x}",
        f"pre_tick_relation={tick_relation(native_pre_ticks, browser_pre_ticks)}",
        f"pre_tick_delta={text(pre_tick_delta)}",
        f"post_tick_relation={tick_relation(native_post_ticks, browser_post_ticks)}",
        f"post_tick_delta={text(post_tick_delta)}",
        f"block_delta_match={bool_text(block_delta_match)}",
        f"native_pre_line={native.pre_edge.line_no}",
        f"native_pre_edge={native.pre_edge.edge()}",
        f"native_pre_value={native_pre_value}",
        f"native_pre_ticks={text(native_pre_ticks)}",
        f"native_post_line={native.post_edge.line_no}",
        f"native_post_edge={native.post_edge.edge()}",
        f"native_post_value={native_post_value}",
        f"native_post_ticks={text(native_post_ticks)}",
        f"native_block_delta={hex32(native_delta)}",
        f"native_block_delta_ticks={text(native_delta_ticks)}",
        f"native_stream_idle_count={native.stream_idle_count}",
        f"browser_pre_line={browser.pre_edge.line_no}",
        f"browser_pre_edge={browser.pre_edge.edge()}",
        f"browser_pre_value={browser_pre_value}",
        f"browser_pre_ticks={text(browser_pre_ticks)}",
        f"browser_post_line={browser.post_edge.line_no}",
        f"browser_post_edge={browser.post_edge.edge()}",
        f"browser_post_value={browser_post_value}",
        f"browser_post_ticks={text(browser_post_ticks)}",
        f"browser_block_delta={hex32(browser_delta)}",
        f"browser_block_delta_ticks={text(browser_delta_ticks)}",
        f"browser_stream_idle_count={browser.stream_idle_count}",
        f"native_log={native.path}",
        f"browser_log={browser.path}",
    ]
    return result, " ".join(fields)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-log", required=True)
    parser.add_argument("--browser-log", required=True)
    parser.add_argument("--watch-addr", default=DEFAULT_WATCH_ADDR)
    parser.add_argument("--block-start", default=DEFAULT_BLOCK_START)
    parser.add_argument("--block-next", default=DEFAULT_BLOCK_NEXT)
    parser.add_argument("--tick-unit", default=hex(DEFAULT_TICK_UNIT))
    args = parser.parse_args()

    tick_unit = parse_int(args.tick_unit)
    if tick_unit is None or tick_unit <= 0:
        print(
            "POST_SERVICE_WATCH_EDGE_COMPARE result=fail "
            f"reason=invalid-tick-unit tick_unit={args.tick_unit}"
        )
        return 2

    try:
        native = parse_log(
            args.native_log,
            "native",
            "native-headless",
            args.watch_addr,
            args.block_start,
            args.block_next,
        )
        browser = parse_log(
            args.browser_log,
            "browser",
            "browser-runtime",
            args.watch_addr,
            args.block_start,
            args.block_next,
        )
    except RuntimeError as exc:
        print(f"POST_SERVICE_WATCH_EDGE_COMPARE result=fail reason={exc}")
        return 2

    result, line = result_line(native, browser, args.watch_addr, tick_unit)
    print(line)
    return 0 if result == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
