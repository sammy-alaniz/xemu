#!/usr/bin/env python3
"""Compare native/browser tick-producing events before PFIFO stream-idle."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path


FIELD_RE = re.compile(r'(\S+)=(".*?"|\S+)')
DEFAULT_WATCH_PHYS = "0x0003a890"
DEFAULT_TICK_UNIT = 0x2710


def parse_value(value: str) -> str:
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    return value


def parse_fields(line: str) -> dict[str, str]:
    return {key: parse_value(value) for key, value in FIELD_RE.findall(line)}


def parse_int(value: str | None) -> int | None:
    if not value or value == "none" or value == "missing":
        return None
    try:
        return int(value, 0)
    except ValueError:
        return None


def hex32(value: int | None) -> str:
    if value is None:
        return "none"
    return f"0x{value & 0xffffffff:08x}"


def text(value) -> str:
    if value is None:
        return "none"
    return str(value)


def context_matches(fields: dict[str, str], context: str) -> bool:
    return not context or fields.get("context") == context


def same_int(value: str | None, expected: int) -> bool:
    parsed = parse_int(value)
    return parsed is not None and parsed == expected


def same_phys(value: str | None, watch_phys: str) -> bool:
    parsed = parse_int(value)
    target = parse_int(watch_phys)
    return parsed is not None and target is not None and parsed == target


def tick_count(value: str | None, tick_unit: int) -> int | None:
    parsed = parse_int(value)
    if parsed is None or tick_unit <= 0 or parsed % tick_unit != 0:
        return None
    return parsed // tick_unit


def memory_sig(fields: dict[str, str], watch_phys: str) -> dict[str, str] | None:
    for side in ("next", "start"):
        if fields.get(f"{side}_mem_value_read") != "yes":
            continue
        if not same_phys(fields.get(f"{side}_mem_phys"), watch_phys):
            continue
        return {
            "side": side,
            "addr": fields.get(f"{side}_mem_addr", "none"),
            "phys": fields.get(f"{side}_mem_phys", "none"),
            "value": fields.get(f"{side}_mem_value", "none"),
            "kind": fields.get(f"{side}_mem_kind", "none"),
        }
    return None


@dataclass
class Event:
    line_no: int
    kind: str
    fields: dict[str, str]
    mem: dict[str, str] | None = None


@dataclass
class ParsedLog:
    label: str
    path: Path
    transition: Event | None = None
    pit_rising: list[Event] = field(default_factory=list)
    main_loop_progress: list[Event] = field(default_factory=list)
    pic_ack30: list[Event] = field(default_factory=list)
    hard_irq_set: list[Event] = field(default_factory=list)
    service30: list[Event] = field(default_factory=list)
    iret_after: list[Event] = field(default_factory=list)
    watch_reads: list[Event] = field(default_factory=list)
    timer_opportunities: list[Event] = field(default_factory=list)
    xbe_executed: list[Event] = field(default_factory=list)

    def pre_events(self, events: list[Event]) -> list[Event]:
        boundary = line_no(self.transition)
        return [event for event in events if boundary and event.line_no < boundary]

    def post_events(self, events: list[Event]) -> list[Event]:
        boundary = line_no(self.transition)
        return [event for event in events if boundary and event.line_no > boundary]

    def first_watch_read_after_transition(self) -> Event | None:
        post_reads = self.post_events(self.watch_reads)
        return post_reads[0] if post_reads else None

    def last_watch_read_before_transition(self) -> Event | None:
        pre_reads = self.pre_events(self.watch_reads)
        return pre_reads[-1] if pre_reads else None


def line_no(event: Event | None) -> int:
    return event.line_no if event is not None else 0


def event_line(event: Event | None) -> str:
    return str(event.line_no) if event is not None else "0"


def field(event: Event | None, key: str, default: str = "none") -> str:
    if event is None:
        return default
    return event.fields.get(key, default)


def edge_key(event: Event | None) -> str:
    if event is None:
        return "none"
    fields = event.fields
    return f"{fields.get('start_pc', 'none')}->{fields.get('next_pc', 'none')}"


def watch_value(event: Event | None) -> str:
    if event is None:
        return "none"
    if event.mem is not None:
        return event.mem.get("value", "none")
    return event.fields.get("value", "none")


def watch_ticks(event: Event | None, tick_unit: int) -> str:
    return text(tick_count(watch_value(event), tick_unit))


def timer_sources(events: list[Event]) -> str:
    sources: list[str] = []
    for event in events:
        source = event.fields.get("source", "unknown")
        if source not in sources:
            sources.append(source)
    return ",".join(sources) if sources else "none"


def compact_values(events: list[Event], key: str) -> str:
    values: list[str] = []
    for event in events:
        value = event.fields.get(key, "none")
        if value not in values:
            values.append(value)
    return ",".join(values) if values else "none"


def timer_watch_value(event: Event | None) -> str:
    if event is None:
        return "none"
    if event.fields.get("memory_watch_value_read") != "yes":
        return "none"
    return event.fields.get("memory_watch_value", "none")


def timer_watch_ticks(event: Event | None, tick_unit: int) -> str:
    return text(tick_count(timer_watch_value(event), tick_unit))


def read_log(path: Path, label: str, context: str, watch_phys: str) -> ParsedLog:
    parsed = ParsedLog(label=label, path=path)
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_no_value, line in enumerate(handle, 1):
            if "BOOT_MARK b6 " not in line:
                continue
            fields = parse_fields(line)
            if not context_matches(fields, context):
                continue

            if fields.get("dashboard") == "xbe-executed":
                parsed.xbe_executed.append(
                    Event(line_no_value, "xbe-executed", fields))
                continue

            if fields.get("headless") == "timer-opportunity":
                parsed.timer_opportunities.append(
                    Event(line_no_value, "timer-opportunity", fields))
                continue

            if fields.get("pfifo") == "stream-idle-transition":
                if parsed.transition is None:
                    parsed.transition = Event(line_no_value, "transition", fields)
                continue

            if fields.get("pit") == "irq-timer" and fields.get("irq_level") == "1":
                parsed.pit_rising.append(Event(line_no_value, "pit-rising", fields))
                continue

            if (
                fields.get("main-loop") == "timers"
                and fields.get("timer_progress") == "yes"
            ):
                parsed.main_loop_progress.append(
                    Event(line_no_value, "main-loop-progress", fields))
                continue

            if fields.get("pic") == "irq-ack" and same_int(fields.get("intno"), 0x30):
                parsed.pic_ack30.append(Event(line_no_value, "pic-ack30", fields))
                continue

            if fields.get("cpu") == "hard-irq" and fields.get("op") == "set":
                parsed.hard_irq_set.append(Event(line_no_value, "hard-irq-set", fields))
                continue

            if (
                fields.get("cpu") == "hard-irq-service"
                and fields.get("phase") == "before"
                and same_int(fields.get("intno"), 0x30)
            ):
                parsed.service30.append(Event(line_no_value, "service30", fields))
                continue

            if fields.get("cpu") == "iret" and fields.get("phase") == "after":
                parsed.iret_after.append(Event(line_no_value, "iret-after", fields))
                continue

            if (
                fields.get("dashboard") == "kernel-loop-probe"
                and (sig := memory_sig(fields, watch_phys)) is not None
            ):
                parsed.watch_reads.append(
                    Event(line_no_value, "watch-read", fields, sig))
                continue

    return parsed


def count_pre(parsed: ParsedLog, events: list[Event]) -> int:
    return len(parsed.pre_events(events))


def count_post(parsed: ParsedLog, events: list[Event]) -> int:
    return len(parsed.post_events(events))


def count_where(events: list[Event], key: str, expected: str) -> int:
    return sum(1 for event in events if event.fields.get(key) == expected)


def last_pre(parsed: ParsedLog, events: list[Event]) -> Event | None:
    pre = parsed.pre_events(events)
    return pre[-1] if pre else None


def first_pre(parsed: ParsedLog, events: list[Event]) -> Event | None:
    pre = parsed.pre_events(events)
    return pre[0] if pre else None


def first_post(parsed: ParsedLog, events: list[Event]) -> Event | None:
    post = parsed.post_events(events)
    return post[0] if post else None


def first_watch_ticks(parsed: ParsedLog, tick_unit: int) -> int | None:
    return tick_count(
        watch_value(parsed.first_watch_read_after_transition()),
        tick_unit,
    )


def divergence(native: ParsedLog, browser: ParsedLog, tick_unit: int) -> str:
    if browser.xbe_executed:
        return "browser-dashboard-executed"
    if native.transition is None or browser.transition is None:
        return "missing-stream-idle-transition"

    native_read = native.first_watch_read_after_transition()
    browser_read = browser.first_watch_read_after_transition()
    if native_read is None or browser_read is None:
        return "missing-first-watch-read"

    native_ticks = first_watch_ticks(native, tick_unit)
    browser_ticks = first_watch_ticks(browser, tick_unit)
    if native_ticks is None or browser_ticks is None:
        if watch_value(native_read) == watch_value(browser_read):
            return "pre-stream-tick-source-aligned"
        return "first-watch-read-value-mismatch"

    if browser_ticks >= native_ticks:
        if browser_ticks == native_ticks:
            return "pre-stream-tick-source-aligned"
        return "browser-first-watch-read-ahead"

    native_service30 = count_pre(native, native.service30)
    browser_service30 = count_pre(browser, browser.service30)
    if native_service30 > browser_service30:
        return "browser-lacks-pre-stream-vector-service"

    native_pic30 = count_pre(native, native.pic_ack30)
    browser_pic30 = count_pre(browser, browser.pic_ack30)
    if native_pic30 > browser_pic30:
        return "browser-lacks-pre-stream-pic-ack"

    native_timers = count_pre(native, native.main_loop_progress)
    browser_timers = count_pre(browser, browser.main_loop_progress)
    if native_timers > browser_timers:
        return "browser-lacks-pre-stream-timer-progress"

    native_pit = count_pre(native, native.pit_rising)
    browser_pit = count_pre(browser, browser.pit_rising)
    if native_pit > browser_pit:
        return "browser-lacks-pre-stream-pit-rising"

    return "pre-stream-tick-source-unexplained"


def side_fields(prefix: str, parsed: ParsedLog, tick_unit: int) -> list[str]:
    pre_timers = parsed.pre_events(parsed.main_loop_progress)
    first_pre_timer = first_pre(parsed, parsed.main_loop_progress)
    last_pre_timer = last_pre(parsed, parsed.main_loop_progress)
    pre_opportunities = parsed.pre_events(parsed.timer_opportunities)
    first_pre_opportunity = first_pre(parsed, parsed.timer_opportunities)
    last_pre_opportunity = last_pre(parsed, parsed.timer_opportunities)
    first_pre_service = first_pre(parsed, parsed.service30)
    last_pre_service = last_pre(parsed, parsed.service30)
    first_post_service = first_post(parsed, parsed.service30)
    first_read = parsed.first_watch_read_after_transition()
    last_pre_read = parsed.last_watch_read_before_transition()

    return [
        f"{prefix}_transition_line={event_line(parsed.transition)}",
        f"{prefix}_transition_eip={field(parsed.transition, 'eip')}",
        f"{prefix}_transition_irq={field(parsed.transition, 'cpu_interrupt_request')}",
        f"{prefix}_transition_pending={field(parsed.transition, 'pending_interrupt')}",
        f"{prefix}_pre_stream_pit_rising={count_pre(parsed, parsed.pit_rising)}",
        f"{prefix}_pre_stream_timer_progress={count_pre(parsed, parsed.main_loop_progress)}",
        f"{prefix}_pre_stream_timer_sources={timer_sources(pre_timers)}",
        f"{prefix}_pre_stream_timer_opportunities={len(pre_opportunities)}",
        f"{prefix}_pre_stream_timer_opportunity_ready={count_where(pre_opportunities, 'ready', 'yes')}",
        f"{prefix}_pre_stream_timer_opportunity_expired={count_where(pre_opportunities, 'virtual_expired', 'yes')}",
        f"{prefix}_pre_stream_timer_opportunity_reasons={compact_values(pre_opportunities, 'reason')}",
        f"{prefix}_pre_stream_timer_opportunity_pfifo_empty_blockers={compact_values(pre_opportunities, 'pfifo_empty_blocker')}",
        f"{prefix}_pre_stream_hard_irq_set={count_pre(parsed, parsed.hard_irq_set)}",
        f"{prefix}_pre_stream_pic_ack30={count_pre(parsed, parsed.pic_ack30)}",
        f"{prefix}_pre_stream_service30={count_pre(parsed, parsed.service30)}",
        f"{prefix}_pre_stream_iret_after={count_pre(parsed, parsed.iret_after)}",
        f"{prefix}_post_stream_service30={count_post(parsed, parsed.service30)}",
        f"{prefix}_first_pre_timer_line={event_line(first_pre_timer)}",
        f"{prefix}_first_pre_timer_eip={field(first_pre_timer, 'eip')}",
        f"{prefix}_first_pre_timer_source={field(first_pre_timer, 'source')}",
        f"{prefix}_first_pre_timer_watch_ticks={timer_watch_ticks(first_pre_timer, tick_unit)}",
        f"{prefix}_last_pre_timer_line={event_line(last_pre_timer)}",
        f"{prefix}_last_pre_timer_eip={field(last_pre_timer, 'eip')}",
        f"{prefix}_last_pre_timer_source={field(last_pre_timer, 'source')}",
        f"{prefix}_last_pre_timer_irq={field(last_pre_timer, 'cpu_interrupt_request')}",
        f"{prefix}_last_pre_timer_watch_ticks={timer_watch_ticks(last_pre_timer, tick_unit)}",
        f"{prefix}_first_pre_opportunity_line={event_line(first_pre_opportunity)}",
        f"{prefix}_first_pre_opportunity_ready={field(first_pre_opportunity, 'ready')}",
        f"{prefix}_first_pre_opportunity_reason={field(first_pre_opportunity, 'reason')}",
        f"{prefix}_first_pre_opportunity_eip={field(first_pre_opportunity, 'eip')}",
        f"{prefix}_first_pre_opportunity_irq={field(first_pre_opportunity, 'cpu_interrupt_request')}",
        f"{prefix}_first_pre_opportunity_wait_source={field(first_pre_opportunity, 'wait_source')}",
        f"{prefix}_first_pre_opportunity_wait_op={field(first_pre_opportunity, 'wait_op')}",
        f"{prefix}_first_pre_opportunity_pfifo_empty_blocker={field(first_pre_opportunity, 'pfifo_empty_blocker')}",
        f"{prefix}_first_pre_opportunity_virtual_expired={field(first_pre_opportunity, 'virtual_expired')}",
        f"{prefix}_first_pre_opportunity_deadline_delta={field(first_pre_opportunity, 'virtual_deadline_delta')}",
        f"{prefix}_first_pre_opportunity_watch_ticks={timer_watch_ticks(first_pre_opportunity, tick_unit)}",
        f"{prefix}_last_pre_opportunity_line={event_line(last_pre_opportunity)}",
        f"{prefix}_last_pre_opportunity_ready={field(last_pre_opportunity, 'ready')}",
        f"{prefix}_last_pre_opportunity_reason={field(last_pre_opportunity, 'reason')}",
        f"{prefix}_last_pre_opportunity_eip={field(last_pre_opportunity, 'eip')}",
        f"{prefix}_last_pre_opportunity_irq={field(last_pre_opportunity, 'cpu_interrupt_request')}",
        f"{prefix}_last_pre_opportunity_wait_source={field(last_pre_opportunity, 'wait_source')}",
        f"{prefix}_last_pre_opportunity_wait_op={field(last_pre_opportunity, 'wait_op')}",
        f"{prefix}_last_pre_opportunity_pfifo_empty_blocker={field(last_pre_opportunity, 'pfifo_empty_blocker')}",
        f"{prefix}_last_pre_opportunity_virtual_expired={field(last_pre_opportunity, 'virtual_expired')}",
        f"{prefix}_last_pre_opportunity_deadline_delta={field(last_pre_opportunity, 'virtual_deadline_delta')}",
        f"{prefix}_last_pre_opportunity_watch_ticks={timer_watch_ticks(last_pre_opportunity, tick_unit)}",
        f"{prefix}_first_pre_service_line={event_line(first_pre_service)}",
        f"{prefix}_first_pre_service_eip={field(first_pre_service, 'eip')}",
        f"{prefix}_last_pre_service_line={event_line(last_pre_service)}",
        f"{prefix}_last_pre_service_eip={field(last_pre_service, 'eip')}",
        f"{prefix}_first_post_service_line={event_line(first_post_service)}",
        f"{prefix}_first_post_service_eip={field(first_post_service, 'eip')}",
        f"{prefix}_last_pre_watch_read_line={event_line(last_pre_read)}",
        f"{prefix}_last_pre_watch_read_edge={edge_key(last_pre_read)}",
        f"{prefix}_last_pre_watch_read_ticks={watch_ticks(last_pre_read, tick_unit)}",
        f"{prefix}_first_watch_read_line={event_line(first_read)}",
        f"{prefix}_first_watch_read_edge={edge_key(first_read)}",
        f"{prefix}_first_watch_read_value={watch_value(first_read)}",
        f"{prefix}_first_watch_read_ticks={watch_ticks(first_read, tick_unit)}",
        f"{prefix}_log={parsed.path}",
    ]


def emit(native: ParsedLog, browser: ParsedLog, watch_phys: str, tick_unit: int) -> int:
    div = divergence(native, browser, tick_unit)
    result = "fail" if div.startswith("missing-") else "pass"
    native_ticks = first_watch_ticks(native, tick_unit)
    browser_ticks = first_watch_ticks(browser, tick_unit)
    tick_delta = (
        None if native_ticks is None or browser_ticks is None
        else native_ticks - browser_ticks
    )

    parts = [
        "PRE_STREAM_TICK_SOURCE_COMPARE",
        f"result={result}",
        f"divergence={div}",
        f"watch_phys={watch_phys}",
        f"tick_unit=0x{tick_unit:08x}",
        f"first_watch_read_tick_delta={text(tick_delta)}",
    ]
    parts.extend(side_fields("native", native, tick_unit))
    parts.extend(side_fields("browser", browser, tick_unit))
    print(" ".join(parts))
    return 1 if result == "fail" else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Summarize native/browser PIT, timer, PIC, and vector 0x30 service "
            "before PFIFO stream-idle, then relate those counts to the watched "
            "tick word read after stream-idle."
        )
    )
    parser.add_argument("--native-log", required=True, type=Path)
    parser.add_argument("--browser-log", required=True, type=Path)
    parser.add_argument("--native-context", default="")
    parser.add_argument("--browser-context", default="")
    parser.add_argument("--watch-phys", default=DEFAULT_WATCH_PHYS)
    parser.add_argument("--tick-unit", default=hex(DEFAULT_TICK_UNIT))
    args = parser.parse_args()

    tick_unit = parse_int(args.tick_unit)
    if tick_unit is None or tick_unit <= 0:
        print(
            "PRE_STREAM_TICK_SOURCE_COMPARE result=fail "
            f"reason=invalid-tick-unit tick_unit={args.tick_unit}",
            file=sys.stderr,
        )
        return 1
    if parse_int(args.watch_phys) is None:
        print(
            "PRE_STREAM_TICK_SOURCE_COMPARE result=fail "
            f"reason=invalid-watch-phys watch_phys={args.watch_phys}",
            file=sys.stderr,
        )
        return 1
    watch_phys = hex32(parse_int(args.watch_phys))

    for label, path in (("native", args.native_log), ("browser", args.browser_log)):
        if not path.is_file():
            print(
                "PRE_STREAM_TICK_SOURCE_COMPARE result=fail "
                f"reason=missing-{label}-log path={path}",
                file=sys.stderr,
            )
            return 1

    native = read_log(args.native_log, "native", args.native_context, watch_phys)
    browser = read_log(args.browser_log, "browser", args.browser_context, watch_phys)
    return emit(native, browser, watch_phys, tick_unit)


if __name__ == "__main__":
    raise SystemExit(main())
