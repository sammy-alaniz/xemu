#!/usr/bin/env python3
"""Summarize browser post-service edge decisions across B6 logs."""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path


FIELD_RE = re.compile(r'(\S+)=(".*?"|\S+)')
DEFAULT_CONTEXT = "browser-runtime"
DEFAULT_WATCH_PHYS = "0x0003a890"
DEFAULT_BLOCK_START = "0x80030e84"
DEFAULT_BLOCK_NEXT = "0x80030f31"
DEFAULT_TICK_UNIT = 0x2710


def parse_value(value: str) -> str:
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    return value


def parse_fields(line: str) -> dict[str, str]:
    return {key: parse_value(value) for key, value in FIELD_RE.findall(line)}


def parse_int(value: str | None) -> int | None:
    if not value or value == "none":
        return None
    try:
        return int(value, 0)
    except ValueError:
        return None


def hex32(value: int | None) -> str:
    if value is None:
        return "none"
    return f"0x{value & 0xffffffff:08x}"


def tick_count(value: str | None, tick_unit: int) -> int | None:
    parsed = parse_int(value)
    if parsed is None or tick_unit <= 0 or parsed % tick_unit != 0:
        return None
    return parsed // tick_unit


def text(value) -> str:
    return "none" if value is None else str(value)


def bool_text(value: bool) -> str:
    return "yes" if value else "no"


def edge_key(fields: dict[str, str]) -> str:
    return f"{fields.get('start_pc', 'none')}->{fields.get('next_pc', 'none')}"


def event_line(event: Event | None) -> int:
    return event.line_no if event is not None else 0


def marker_field(event: Event | None, key: str, default: str = "none") -> str:
    if event is None:
        return default
    return event.fields.get(key, default)


def same_phys(value: str | None, watch_phys: str) -> bool:
    parsed = parse_int(value)
    target = parse_int(watch_phys)
    return parsed is not None and target is not None and parsed == target


def is_stream_idle_boundary(fields: dict[str, str]) -> bool:
    if fields.get("pfifo") == "stream-idle-boundary":
        return fields.get("wait_op") == "pusher-empty"
    if fields.get("pfifo") == "window" and fields.get("op") == "pusher-empty":
        dma_get = fields.get("dma_get", "none")
        dma_put = fields.get("dma_put", "none")
        return dma_get != "none" and dma_get == dma_put
    return False


def is_stream_idle_transition(fields: dict[str, str]) -> bool:
    return (
        fields.get("pfifo") == "stream-idle-transition"
        and fields.get("wait_op") == "pusher-empty-transition"
    )


def is_pfifo_empty_wait(fields: dict[str, str]) -> bool:
    return (
        fields.get("nv2a_wait_source") == "pfifo-window"
        and fields.get("nv2a_wait_op") == "pusher-empty"
    )


def memory_sig(fields: dict[str, str]) -> dict[str, str]:
    for side in ("next", "start"):
        if fields.get(f"{side}_mem_value_read") != "yes":
            continue
        return {
            "side": side,
            "kind": fields.get(f"{side}_mem_kind", "none"),
            "addr": fields.get(f"{side}_mem_addr", "none"),
            "phys": fields.get(f"{side}_mem_phys", "none"),
            "value": fields.get(f"{side}_mem_value", "none"),
        }
    return {
        "side": "none",
        "kind": "none",
        "addr": "none",
        "phys": "none",
        "value": "none",
    }


def watch_memory_sig(fields: dict[str, str], watch_phys: str) -> dict[str, str] | None:
    for side in ("next", "start"):
        if fields.get(f"{side}_mem_value_read") != "yes":
            continue
        if not same_phys(fields.get(f"{side}_mem_phys"), watch_phys):
            continue
        return {
            "side": side,
            "kind": fields.get(f"{side}_mem_kind", "none"),
            "addr": fields.get(f"{side}_mem_addr", "none"),
            "phys": hex32(parse_int(fields.get(f"{side}_mem_phys"))),
            "value": fields.get(f"{side}_mem_value", "none"),
        }
    return None


def timer_watch_ticks(event: Event | None, tick_unit: int) -> str:
    if event is None:
        return "none"
    if event.fields.get("memory_watch_value_read") != "yes":
        return "none"
    return text(tick_count(event.fields.get("memory_watch_value"), tick_unit))


def timer_watch_value(event: Event | None) -> str:
    if event is None:
        return "none"
    if event.fields.get("memory_watch_value_read") != "yes":
        return "none"
    return event.fields.get("memory_watch_value", "none")


def event_watch_value(event: Event | None) -> str:
    if event is None:
        return "none"
    sig = event.watch_mem or memory_sig(event.fields)
    return sig.get("value", "none")


def event_watch_ticks(event: Event | None, tick_unit: int) -> str:
    return text(tick_count(event_watch_value(event), tick_unit))


def timer_sources(events: list[Event]) -> str:
    values: list[str] = []
    for event in events:
        source = event.fields.get("source", "none")
        if source not in values:
            values.append(source)
    return ",".join(values) if values else "none"


def first_after(events: list[Event], line_no: int) -> Event | None:
    for event in events:
        if event.line_no > line_no:
            return event
    return None


def last_before(events: list[Event], line_no: int) -> Event | None:
    for event in reversed(events):
        if event.line_no < line_no:
            return event
    return None


def compact_event(event: Event | None, tick_unit: int) -> str:
    if event is None:
        return "none"
    sig = memory_sig(event.fields)
    ticks = text(tick_count(sig["value"], tick_unit))
    return (
        f"{event.line_no}:{edge_key(event.fields)}:"
        f"irq={event.fields.get('cpu_interrupt_request', 'none')}:"
        f"pending={event.fields.get('pending_interrupt', 'none')}:"
        f"wait={event.fields.get('nv2a_wait_source', 'none')}/"
        f"{event.fields.get('nv2a_wait_op', 'none')}:"
        f"mem={sig['side']}@{sig['phys']}={sig['value']}:ticks={ticks}"
    )


def compact_events(events: list[Event], tick_unit: int, limit: int) -> str:
    if not events:
        return "none"
    return ",".join(compact_event(event, tick_unit) for event in events[:limit])


@dataclass
class Event:
    line_no: int
    kind: str
    fields: dict[str, str]
    watch_mem: dict[str, str] | None = None


@dataclass
class ParsedLog:
    label: str
    path: Path
    stream_idle_transition: Event | None = None
    stream_idle_boundary: Event | None = None
    timers: list[Event] = field(default_factory=list)
    timer_progress: list[Event] = field(default_factory=list)
    loop_events: list[Event] = field(default_factory=list)
    watch_reads: list[Event] = field(default_factory=list)
    watch_writes: list[Event] = field(default_factory=list)
    services_before: list[Event] = field(default_factory=list)
    services_after: list[Event] = field(default_factory=list)
    irets_after: list[Event] = field(default_factory=list)
    hard_irqs: list[Event] = field(default_factory=list)
    pic_acks: list[Event] = field(default_factory=list)
    xbe_executed: list[Event] = field(default_factory=list)

    def focus_start_line(self) -> int:
        values = [
            event_line(self.stream_idle_boundary),
            event_line(self.preferred_iret()),
        ]
        return max(values)

    def focus_loops(self) -> list[Event]:
        start = self.focus_start_line()
        if start == 0:
            return list(self.loop_events)
        return [event for event in self.loop_events if event.line_no > start]

    def preferred_iret(self) -> Event | None:
        pfifo_empty = [
            event for event in self.irets_after
            if is_pfifo_empty_wait(event.fields)
        ]
        preferred = [
            event for event in pfifo_empty
            if event.fields.get("eip") == DEFAULT_BLOCK_START
        ]
        if preferred:
            return preferred[0]
        if pfifo_empty:
            return pfifo_empty[0]
        if self.irets_after:
            return self.irets_after[0]
        return None

    def first_focus_loop(self) -> Event | None:
        loops = self.focus_loops()
        return loops[0] if loops else None

    def top_edge(self) -> tuple[str, int, Event | None]:
        loops = self.focus_loops()
        counts = Counter(edge_key(event.fields) for event in loops)
        if not counts:
            return "none", 0, None
        edge, count = counts.most_common(1)[0]
        for event in reversed(loops):
            if edge_key(event.fields) == edge:
                return edge, count, event
        return edge, count, None

    def first_block_start(self, block_start: str) -> Event | None:
        for event in self.focus_loops():
            if event.fields.get("start_pc") == block_start:
                return event
        return None

    def first_expected_block(self, block_start: str, block_next: str) -> Event | None:
        for event in self.focus_loops():
            if (
                event.fields.get("start_pc") == block_start
                and event.fields.get("next_pc") == block_next
            ):
                return event
        return None

    def first_watch_read(self) -> Event | None:
        start = self.focus_start_line()
        return first_after(self.watch_reads, start)

    def first_watch_write(self) -> Event | None:
        start = self.focus_start_line()
        return first_after(self.watch_writes, start)


def parse_log(path: Path, label: str, context: str, watch_phys: str) -> ParsedLog:
    parsed = ParsedLog(label=label, path=path)
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_no, raw_line in enumerate(handle, 1):
            if "BOOT_MARK b6 " not in raw_line:
                continue
            fields = parse_fields(raw_line)
            if context and fields.get("context") != context:
                continue

            if is_stream_idle_transition(fields) and parsed.stream_idle_transition is None:
                parsed.stream_idle_transition = Event(line_no, "stream-idle-transition", fields)
                continue

            if is_stream_idle_boundary(fields) and parsed.stream_idle_boundary is None:
                parsed.stream_idle_boundary = Event(line_no, "stream-idle-boundary", fields)
                continue

            if fields.get("main-loop") == "timers":
                event = Event(line_no, "timer", fields)
                parsed.timers.append(event)
                if fields.get("timer_progress") == "yes":
                    parsed.timer_progress.append(event)
                continue

            if fields.get("dashboard") == "kernel-loop-probe":
                watch_mem = watch_memory_sig(fields, watch_phys)
                event = Event(line_no, "kernel-loop-probe", fields, watch_mem)
                parsed.loop_events.append(event)
                if watch_mem is not None:
                    parsed.watch_reads.append(event)
                continue

            if (
                " memory-watch " in raw_line
                and fields.get("access") == "write"
                and (
                    same_phys(fields.get("phys"), watch_phys)
                    or same_phys(fields.get("watch_phys"), watch_phys)
                )
            ):
                parsed.watch_writes.append(Event(line_no, "watch-write", fields))
                continue

            if fields.get("cpu") == "hard-irq-service":
                if fields.get("phase") == "before":
                    parsed.services_before.append(Event(line_no, "service-before", fields))
                elif fields.get("phase") == "after":
                    parsed.services_after.append(Event(line_no, "service-after", fields))
                continue

            if fields.get("cpu") == "iret" and fields.get("phase") == "after":
                parsed.irets_after.append(Event(line_no, "iret-after", fields))
                continue

            if fields.get("cpu") == "hard-irq":
                parsed.hard_irqs.append(Event(line_no, "hard-irq", fields))
                continue

            if fields.get("pic") == "irq-ack":
                parsed.pic_acks.append(Event(line_no, "pic-ack", fields))
                continue

            if fields.get("dashboard") == "xbe-executed":
                parsed.xbe_executed.append(Event(line_no, "xbe-executed", fields))

    return parsed


def classify(parsed: ParsedLog, block_start: str, block_next: str) -> str:
    if parsed.xbe_executed:
        return "dashboard-executed"
    if parsed.stream_idle_boundary is None:
        return "missing-stream-idle-boundary"
    top_edge, _, _ = parsed.top_edge()
    if top_edge == f"{block_start}->{block_next}":
        return "useful-post-service-edge"
    first_block = parsed.first_block_start(block_start)
    if first_block is not None and first_block.fields.get("next_pc") != block_next:
        return "block-start-branch-mismatch"
    if parsed.first_watch_read() is None:
        if parsed.first_watch_write() is not None:
            return "watch-write-without-focused-read"
        if top_edge == "0x8001b02f->0x8001b030":
            return "idle-loop-stall"
        return "missing-focused-watch-read"
    return "post-service-edge-diverged"


def side_fields(
    parsed: ParsedLog,
    context: str,
    watch_phys: str,
    block_start: str,
    block_next: str,
    tick_unit: int,
    edge_limit: int,
) -> list[str]:
    focus_loop = parsed.first_focus_loop()
    top_edge, top_count, top_event = parsed.top_edge()
    first_block = parsed.first_block_start(block_start)
    first_expected = parsed.first_expected_block(block_start, block_next)
    first_read = parsed.first_watch_read()
    first_write = parsed.first_watch_write()
    boundary = parsed.stream_idle_boundary
    transition = parsed.stream_idle_transition
    service = first_after(parsed.services_before, event_line(boundary))
    service_after = first_after(parsed.services_after, event_line(service))
    preferred_iret = parsed.preferred_iret()
    first_timer_after_boundary = first_after(parsed.timer_progress, event_line(boundary))
    last_timer_before_focus = last_before(
        parsed.timer_progress, event_line(focus_loop))
    last_timer_before_block = last_before(
        parsed.timer_progress, event_line(first_block))
    first_timer_after_block = first_after(
        parsed.timer_progress, event_line(first_block))
    timer_window_start = event_line(transition) or event_line(boundary)
    timer_window_end = event_line(first_block) or event_line(focus_loop)
    timers_before_focus = [
        event for event in parsed.timer_progress
        if timer_window_start < event.line_no < timer_window_end
    ]
    focus_edges = parsed.focus_loops()

    first_block_sig = memory_sig(first_block.fields) if first_block else memory_sig({})
    first_write_value = marker_field(first_write, "value")
    if first_write is not None and first_write.fields.get("value_read") != "yes":
        first_write_value = "none"

    return [
        f"POST_SERVICE_EDGE_DECISION label={parsed.label}",
        f"context={context}",
        f"classification={classify(parsed, block_start, block_next)}",
        f"watch_phys={watch_phys}",
        f"tick_unit=0x{tick_unit:08x}",
        f"xbe_executed={bool_text(bool(parsed.xbe_executed))}",
        f"transition_line={event_line(transition)}",
        f"transition_eip={marker_field(transition, 'eip')}",
        f"transition_irq={marker_field(transition, 'cpu_interrupt_request')}",
        f"transition_pending={marker_field(transition, 'pending_interrupt')}",
        f"boundary_line={event_line(boundary)}",
        f"boundary_eip={marker_field(boundary, 'eip')}",
        f"boundary_irq={marker_field(boundary, 'cpu_interrupt_request')}",
        f"boundary_pending={marker_field(boundary, 'pending_interrupt')}",
        f"boundary_irq_inhibited={marker_field(boundary, 'irq_inhibited')}",
        f"boundary_last_edge={marker_field(boundary, 'last_transition_start_pc')}->{marker_field(boundary, 'last_transition_next_pc')}",
        f"focus_start_line={parsed.focus_start_line()}",
        f"preferred_iret_line={event_line(preferred_iret)}",
        f"preferred_iret_eip={marker_field(preferred_iret, 'eip')}",
        f"preferred_iret_irq={marker_field(preferred_iret, 'cpu_interrupt_request')}",
        f"first_service_line={event_line(service)}",
        f"first_service_intno={marker_field(service, 'intno')}",
        f"first_service_eip={marker_field(service, 'eip')}",
        f"first_service_after_line={event_line(service_after)}",
        f"first_service_after_eip={marker_field(service_after, 'eip')}",
        f"focus_loop_count={len(focus_edges)}",
        f"first_focus_loop_line={event_line(focus_loop)}",
        f"first_focus_loop_edge={edge_key(focus_loop.fields) if focus_loop else 'none'}",
        f"first_focus_loop_irq={marker_field(focus_loop, 'cpu_interrupt_request')}",
        f"first_focus_loop_pending={marker_field(focus_loop, 'pending_interrupt')}",
        f"top_edge={top_edge}",
        f"top_edge_count={top_count}",
        f"top_edge_line={event_line(top_event)}",
        f"top_edge_irq={marker_field(top_event, 'cpu_interrupt_request')}",
        f"top_edge_pending={marker_field(top_event, 'pending_interrupt')}",
        f"top_edge_wait={marker_field(top_event, 'nv2a_wait_source')}/{marker_field(top_event, 'nv2a_wait_op')}",
        f"first_block_line={event_line(first_block)}",
        f"first_block_edge={edge_key(first_block.fields) if first_block else 'none'}",
        f"first_block_tb_exit={marker_field(first_block, 'tb_exit')}",
        f"first_block_irq={marker_field(first_block, 'cpu_interrupt_request')}",
        f"first_block_pending={marker_field(first_block, 'pending_interrupt')}",
        f"first_block_start_value={first_block_sig['value']}",
        f"first_block_start_ticks={event_watch_ticks(first_block, tick_unit)}",
        f"first_expected_block_line={event_line(first_expected)}",
        f"first_expected_block_edge={edge_key(first_expected.fields) if first_expected else 'none'}",
        f"first_watch_read_line={event_line(first_read)}",
        f"first_watch_read_edge={edge_key(first_read.fields) if first_read else 'none'}",
        f"first_watch_read_value={event_watch_value(first_read)}",
        f"first_watch_read_ticks={event_watch_ticks(first_read, tick_unit)}",
        f"first_watch_write_line={event_line(first_write)}",
        f"first_watch_write_eip={marker_field(first_write, 'eip')}",
        f"first_watch_write_value={first_write_value}",
        f"first_watch_write_ticks={text(tick_count(first_write_value, tick_unit))}",
        f"first_timer_after_boundary_line={event_line(first_timer_after_boundary)}",
        f"first_timer_after_boundary_source={marker_field(first_timer_after_boundary, 'source')}",
        f"first_timer_after_boundary_eip={marker_field(first_timer_after_boundary, 'eip')}",
        f"first_timer_after_boundary_irq={marker_field(first_timer_after_boundary, 'cpu_interrupt_request')}",
        f"first_timer_after_boundary_watch_value={timer_watch_value(first_timer_after_boundary)}",
        f"first_timer_after_boundary_watch_ticks={timer_watch_ticks(first_timer_after_boundary, tick_unit)}",
        f"last_timer_before_focus_line={event_line(last_timer_before_focus)}",
        f"last_timer_before_focus_source={marker_field(last_timer_before_focus, 'source')}",
        f"last_timer_before_focus_watch_ticks={timer_watch_ticks(last_timer_before_focus, tick_unit)}",
        f"last_timer_before_block_line={event_line(last_timer_before_block)}",
        f"last_timer_before_block_source={marker_field(last_timer_before_block, 'source')}",
        f"last_timer_before_block_watch_ticks={timer_watch_ticks(last_timer_before_block, tick_unit)}",
        f"first_timer_after_block_line={event_line(first_timer_after_block)}",
        f"first_timer_after_block_source={marker_field(first_timer_after_block, 'source')}",
        f"first_timer_after_block_watch_ticks={timer_watch_ticks(first_timer_after_block, tick_unit)}",
        f"pre_focus_timer_sources={timer_sources(timers_before_focus)}",
        f"post_boundary_timer_sources={timer_sources([event for event in parsed.timer_progress if event.line_no > event_line(boundary)])}",
        f"focus_edges={compact_events(focus_edges, tick_unit, edge_limit)}",
        f"log={parsed.path}",
    ]


def parse_log_spec(value: str) -> tuple[str, Path]:
    if "=" not in value:
        path = Path(value)
        return path.stem, path
    label, path = value.split("=", 1)
    if not label or not path:
        raise argparse.ArgumentTypeError(
            "--log must be either path or label=path")
    return label, Path(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--log",
        action="append",
        required=True,
        type=parse_log_spec,
        help="Browser log to summarize, either path or label=path.",
    )
    parser.add_argument("--context", default=DEFAULT_CONTEXT)
    parser.add_argument("--watch-phys", default=DEFAULT_WATCH_PHYS)
    parser.add_argument("--block-start", default=DEFAULT_BLOCK_START)
    parser.add_argument("--block-next", default=DEFAULT_BLOCK_NEXT)
    parser.add_argument("--tick-unit", default=hex(DEFAULT_TICK_UNIT))
    parser.add_argument("--edge-limit", type=int, default=8)
    args = parser.parse_args()

    tick_unit = parse_int(args.tick_unit)
    if tick_unit is None or tick_unit <= 0:
        print(
            "POST_SERVICE_EDGE_DECISION_COMPARE result=fail "
            f"reason=invalid-tick-unit tick_unit={args.tick_unit}",
            file=sys.stderr,
        )
        return 2
    watch_phys = hex32(parse_int(args.watch_phys))
    if watch_phys == "none":
        print(
            "POST_SERVICE_EDGE_DECISION_COMPARE result=fail "
            f"reason=invalid-watch-phys watch_phys={args.watch_phys}",
            file=sys.stderr,
        )
        return 2

    parsed_logs: list[ParsedLog] = []
    for label, path in args.log:
        if not path.is_file():
            print(
                "POST_SERVICE_EDGE_DECISION_COMPARE result=fail "
                f"reason=missing-log label={label} path={path}",
                file=sys.stderr,
            )
            return 2
        parsed_logs.append(parse_log(path, label, args.context, watch_phys))

    classifications = [
        f"{parsed.label}:{classify(parsed, args.block_start, args.block_next)}"
        for parsed in parsed_logs
    ]
    top_edges = [
        f"{parsed.label}:{parsed.top_edge()[0]}"
        for parsed in parsed_logs
    ]
    print(
        "POST_SERVICE_EDGE_DECISION_COMPARE "
        "result=pass "
        "field=browser_post_service_top_edge "
        f"context={args.context} "
        f"classifications={','.join(classifications)} "
        f"top_edges={','.join(top_edges)} "
        f"watch_phys={watch_phys} "
        f"block_start={args.block_start} "
        f"block_next={args.block_next}"
    )

    for parsed in parsed_logs:
        print(
            " ".join(
                side_fields(
                    parsed,
                    args.context,
                    watch_phys,
                    args.block_start,
                    args.block_next,
                    tick_unit,
                    args.edge_limit,
                )
            )
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
