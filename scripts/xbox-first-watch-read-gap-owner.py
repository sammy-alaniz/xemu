#!/usr/bin/env python3
"""Classify the owner of the native/browser first watched-read tick gap."""

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
    if not value or value in {"none", "missing"}:
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


def bool_text(value: bool) -> str:
    return "yes" if value else "no"


def context_matches(fields: dict[str, str], context: str) -> bool:
    return not context or fields.get("context") == context


def same_phys(value: str | None, watch_phys: str) -> bool:
    parsed = parse_int(value)
    target = parse_int(watch_phys)
    return parsed is not None and target is not None and parsed == target


def same_int(value: str | None, expected: int) -> bool:
    parsed = parse_int(value)
    return parsed is not None and parsed == expected


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
    boundary: Event | None = None
    xbe_executed: list[Event] = field(default_factory=list)
    watch_reads: list[Event] = field(default_factory=list)
    watch_writes: list[Event] = field(default_factory=list)
    tick_blocks: list[Event] = field(default_factory=list)
    main_loop_progress: list[Event] = field(default_factory=list)
    timer_opportunities: list[Event] = field(default_factory=list)
    pit_rising: list[Event] = field(default_factory=list)
    pit_events: list[Event] = field(default_factory=list)
    hard_irq_set: list[Event] = field(default_factory=list)
    hard_irq_reset: list[Event] = field(default_factory=list)
    pic_ack: list[Event] = field(default_factory=list)
    pic_ack30: list[Event] = field(default_factory=list)
    pic_lines: list[Event] = field(default_factory=list)
    service: list[Event] = field(default_factory=list)
    service30: list[Event] = field(default_factory=list)
    iret_after: list[Event] = field(default_factory=list)
    pmc_access: list[Event] = field(default_factory=list)
    irq_source: list[Event] = field(default_factory=list)

    def first_watch_read_after_transition(self) -> Event | None:
        anchor = line_no(self.transition)
        for event in self.watch_reads:
            if event.line_no > anchor:
                return event
        return None

    def last_watch_read_before_transition(self) -> Event | None:
        anchor = line_no(self.transition)
        before = [event for event in self.watch_reads if anchor and event.line_no < anchor]
        return before[-1] if before else None


def line_no(event: Event | None) -> int:
    return event.line_no if event is not None else 0


def event_line(event: Event | None) -> str:
    return str(line_no(event))


def field(event: Event | None, key: str, default: str = "none") -> str:
    if event is None:
        return default
    return event.fields.get(key, default)


def first_before(events: list[Event], line: int) -> Event | None:
    for event in events:
        if event.line_no < line:
            return event
    return None


def last_before(events: list[Event], line: int) -> Event | None:
    before = [event for event in events if event.line_no < line]
    return before[-1] if before else None


def first_between(events: list[Event], start: int, end: int) -> Event | None:
    for event in events:
        if event.line_no > start and event.line_no < end:
            return event
    return None


def last_between(events: list[Event], start: int, end: int) -> Event | None:
    between = [event for event in events if event.line_no > start and event.line_no < end]
    return between[-1] if between else None


def count_before(events: list[Event], line: int) -> int:
    return sum(1 for event in events if event.line_no < line)


def count_between(events: list[Event], start: int, end: int) -> int:
    return sum(1 for event in events if event.line_no > start and event.line_no < end)


def count_pre_stream(parsed: ParsedLog, events: list[Event]) -> int:
    return count_before(events, line_no(parsed.transition))


def edge_key(event: Event | None) -> str:
    if event is None:
        return "none"
    return (
        f"{event.fields.get('start_pc', 'none')}"
        f"->{event.fields.get('next_pc', 'none')}"
    )


def watch_value(event: Event | None) -> str:
    if event is None:
        return "none"
    if event.mem is not None:
        return event.mem.get("value", "none")
    return event.fields.get("value", "none")


def watch_ticks(event: Event | None, tick_unit: int) -> str:
    return text(tick_count(watch_value(event), tick_unit))


def timer_watch_value(event: Event | None) -> str:
    if event is None or event.fields.get("memory_watch_value_read") != "yes":
        return "none"
    return event.fields.get("memory_watch_value", "none")


def timer_watch_ticks(event: Event | None, tick_unit: int) -> str:
    return text(tick_count(timer_watch_value(event), tick_unit))


def tick_block_post_value(event: Event | None) -> str:
    if event is None:
        return "none"
    return event.fields.get("post_watch_value", "none")


def tick_block_post_ticks(event: Event | None, tick_unit: int) -> str:
    return text(tick_count(tick_block_post_value(event), tick_unit))


def event_summary(event: Event | None) -> str:
    if event is None:
        return "none"
    fields = event.fields
    if event.kind == "pmc-access":
        return (
            f"{fields.get('op', 'none')}:{fields.get('reg', 'none')}:"
            f"{fields.get('value', 'none')}"
        )
    if event.kind == "irq-source":
        return (
            f"{fields.get('source', 'none')}:{fields.get('op', 'none')}:"
            f"{fields.get('value', 'none')}"
        )
    if event.kind == "pic-line":
        return (
            f"{fields.get('guest_irq', 'none')}:{fields.get('level', 'none')}:"
            f"out={fields.get('output_irq', 'none')}"
        )
    if event.kind == "pic-ack":
        return (
            f"{fields.get('intno', 'none')}:{fields.get('guest_irq', 'none')}:"
            f"isr={fields.get('master_isr_after', 'none')}"
        )
    if event.kind == "pit":
        return (
            f"level={fields.get('irq_level', 'none')}:"
            f"eip={fields.get('eip', 'none')}"
        )
    return event.kind


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

            if fields.get("pfifo") == "stream-idle-transition":
                if parsed.transition is None:
                    parsed.transition = Event(line_no_value, "transition", fields)
                continue

            if fields.get("pfifo") == "stream-idle-boundary":
                if parsed.boundary is None:
                    parsed.boundary = Event(line_no_value, "boundary", fields)
                continue

            if fields.get("dashboard") == "kernel-loop-probe":
                sig = memory_sig(fields, watch_phys)
                if sig is not None:
                    parsed.watch_reads.append(
                        Event(line_no_value, "watch-read", fields, sig))
                continue

            if (
                " memory-watch " in line
                and fields.get("access") == "write"
                and (
                    same_phys(fields.get("phys"), watch_phys)
                    or same_phys(fields.get("watch_phys"), watch_phys)
                )
            ):
                parsed.watch_writes.append(
                    Event(line_no_value, "watch-write", fields))
                continue

            if fields.get("tick-block") == "complete":
                parsed.tick_blocks.append(
                    Event(line_no_value, "tick-block", fields))
                continue

            if (
                fields.get("main-loop") == "timers"
                and fields.get("timer_progress") == "yes"
            ):
                parsed.main_loop_progress.append(
                    Event(line_no_value, "main-loop-progress", fields))
                continue

            if fields.get("headless") == "timer-opportunity":
                parsed.timer_opportunities.append(
                    Event(line_no_value, "timer-opportunity", fields))
                continue

            if fields.get("pit") == "irq-timer":
                event = Event(line_no_value, "pit", fields)
                parsed.pit_events.append(event)
                if fields.get("irq_level") == "1":
                    parsed.pit_rising.append(event)
                continue

            if fields.get("cpu") == "hard-irq":
                if fields.get("op") == "set":
                    parsed.hard_irq_set.append(
                        Event(line_no_value, "hard-irq-set", fields))
                elif fields.get("op") == "reset":
                    parsed.hard_irq_reset.append(
                        Event(line_no_value, "hard-irq-reset", fields))
                continue

            if fields.get("pic") == "irq-ack":
                event = Event(line_no_value, "pic-ack", fields)
                parsed.pic_ack.append(event)
                if same_int(fields.get("intno"), 0x30):
                    parsed.pic_ack30.append(event)
                continue

            if fields.get("pic") == "irq-line":
                parsed.pic_lines.append(Event(line_no_value, "pic-line", fields))
                continue

            if (
                fields.get("cpu") == "hard-irq-service"
                and fields.get("phase") == "before"
            ):
                event = Event(line_no_value, "service", fields)
                parsed.service.append(event)
                if same_int(fields.get("intno"), 0x30):
                    parsed.service30.append(event)
                continue

            if fields.get("cpu") == "iret" and fields.get("phase") == "after":
                parsed.iret_after.append(Event(line_no_value, "iret-after", fields))
                continue

            if fields.get("nv2a") == "pmc-access":
                parsed.pmc_access.append(Event(line_no_value, "pmc-access", fields))
                continue

            if fields.get("nv2a") == "irq-source":
                parsed.irq_source.append(Event(line_no_value, "irq-source", fields))
                continue

    return parsed


def first_watch_ticks(parsed: ParsedLog, tick_unit: int) -> int | None:
    return tick_count(
        watch_value(parsed.first_watch_read_after_transition()),
        tick_unit,
    )


def classify_owner(native: ParsedLog, browser: ParsedLog, tick_unit: int) -> str:
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
            return "first-watch-read-aligned"
        return "first-watch-read-value-not-tick-comparable"
    if browser_ticks == native_ticks:
        return "first-watch-read-aligned"
    if browser_ticks > native_ticks:
        return "browser-first-watch-read-ahead"

    native_pre_services = count_pre_stream(native, native.service30)
    browser_pre_services = count_pre_stream(browser, browser.service30)
    native_pre_acks = count_pre_stream(native, native.pic_ack30)
    browser_pre_acks = count_pre_stream(browser, browser.pic_ack30)
    native_pre_timers = count_pre_stream(native, native.main_loop_progress)
    browser_pre_timers = count_pre_stream(browser, browser.main_loop_progress)
    native_pre_pit = count_pre_stream(native, native.pit_rising)
    browser_pre_pit = count_pre_stream(browser, browser.pit_rising)

    if (
        native_pre_services > browser_pre_services
        and native_pre_timers > browser_pre_timers
    ):
        return "browser-lacks-native-pre-stream-vector-timer-production"
    if native_pre_services > browser_pre_services:
        return "browser-lacks-native-pre-stream-vector-service"
    if native_pre_acks > browser_pre_acks:
        return "browser-lacks-native-pre-stream-pic-ack"
    if native_pre_timers > browser_pre_timers:
        return "browser-lacks-native-pre-stream-timer-progress"
    if native_pre_pit > browser_pre_pit:
        return "browser-lacks-native-pre-stream-pit-rising"

    browser_first_write = first_between(
        browser.watch_writes,
        line_no(browser.transition),
        line_no(browser_read),
    )
    if browser_first_write is None and browser.watch_writes:
        first_write = browser.watch_writes[0]
        if first_write.line_no > browser_read.line_no:
            return "browser-first-watch-read-before-own-tick-write"

    native_last_read = native.last_watch_read_before_transition()
    browser_last_read = browser.last_watch_read_before_transition()
    native_last_ticks = tick_count(watch_value(native_last_read), tick_unit)
    browser_last_ticks = tick_count(watch_value(browser_last_read), tick_unit)
    if native_last_ticks is not None and browser_last_ticks is None:
        return "browser-lacks-pre-stream-watch-tick-observation"
    if (
        native_last_ticks is not None
        and browser_last_ticks is not None
        and browser_last_ticks < native_last_ticks
    ):
        return "browser-pre-stream-watch-tick-observation-behind"

    return "first-watch-read-tick-gap-unclassified"


def side_fields(prefix: str, parsed: ParsedLog, tick_unit: int) -> list[str]:
    read = parsed.first_watch_read_after_transition()
    read_line = line_no(read)
    transition_line = line_no(parsed.transition)
    last_pre_read_write = last_before(parsed.watch_writes, read_line)
    last_pre_read_tick_block = last_before(parsed.tick_blocks, read_line)
    last_pre_read_timer = last_before(parsed.main_loop_progress, read_line)
    last_pre_read_pit = last_before(parsed.pit_events, read_line)
    last_pre_read_pmc = last_before(parsed.pmc_access, read_line)
    last_pre_read_irq_source = last_before(parsed.irq_source, read_line)
    last_pre_read_pic_line = last_before(parsed.pic_lines, read_line)
    last_pre_read_pic_ack = last_before(parsed.pic_ack, read_line)
    last_pre_read_service = last_before(parsed.service, read_line)
    last_pre_read_iret = last_before(parsed.iret_after, read_line)
    first_post_transition_service = first_between(
        parsed.service, transition_line, read_line)
    first_post_transition_ack = first_between(parsed.pic_ack, transition_line, read_line)
    first_post_transition_timer = first_between(
        parsed.main_loop_progress, transition_line, read_line)
    last_pre_transition_read = parsed.last_watch_read_before_transition()

    return [
        f"{prefix}_xbe_executed={bool_text(bool(parsed.xbe_executed))}",
        f"{prefix}_transition_line={event_line(parsed.transition)}",
        f"{prefix}_transition_eip={field(parsed.transition, 'eip')}",
        f"{prefix}_transition_irq={field(parsed.transition, 'cpu_interrupt_request')}",
        f"{prefix}_transition_pending={field(parsed.transition, 'pending_interrupt')}",
        f"{prefix}_transition_pmc_pending={field(parsed.transition, 'pmc_pending')}",
        f"{prefix}_transition_pcrtc_pending={field(parsed.transition, 'pcrtc_pending')}",
        f"{prefix}_boundary_line={event_line(parsed.boundary)}",
        f"{prefix}_first_watch_read_line={event_line(read)}",
        f"{prefix}_first_watch_read_delta_from_transition={text(None if not read_line or not transition_line else read_line - transition_line)}",
        f"{prefix}_first_watch_read_edge={edge_key(read)}",
        f"{prefix}_first_watch_read_value={watch_value(read)}",
        f"{prefix}_first_watch_read_ticks={watch_ticks(read, tick_unit)}",
        f"{prefix}_first_watch_read_irq={field(read, 'cpu_interrupt_request')}",
        f"{prefix}_first_watch_read_pending={field(read, 'pending_interrupt')}",
        f"{prefix}_first_watch_read_wait_source={field(read, 'nv2a_wait_source')}",
        f"{prefix}_first_watch_read_wait_op={field(read, 'nv2a_wait_op')}",
        f"{prefix}_first_watch_read_pmc_pending={field(read, 'nv2a_pmc_pending')}",
        f"{prefix}_first_watch_read_pcrtc_pending={field(read, 'nv2a_pcrtc_pending')}",
        f"{prefix}_pre_stream_timer_progress={count_pre_stream(parsed, parsed.main_loop_progress)}",
        f"{prefix}_pre_stream_pit_rising={count_pre_stream(parsed, parsed.pit_rising)}",
        f"{prefix}_pre_stream_hard_irq_set={count_pre_stream(parsed, parsed.hard_irq_set)}",
        f"{prefix}_pre_stream_hard_irq_reset={count_pre_stream(parsed, parsed.hard_irq_reset)}",
        f"{prefix}_pre_stream_pic_ack30={count_pre_stream(parsed, parsed.pic_ack30)}",
        f"{prefix}_pre_stream_service30={count_pre_stream(parsed, parsed.service30)}",
        f"{prefix}_pre_stream_iret_after={count_pre_stream(parsed, parsed.iret_after)}",
        f"{prefix}_pre_stream_watch_writes={count_pre_stream(parsed, parsed.watch_writes)}",
        f"{prefix}_pre_stream_tick_blocks={count_pre_stream(parsed, parsed.tick_blocks)}",
        f"{prefix}_post_transition_pre_read_timer_progress={count_between(parsed.main_loop_progress, transition_line, read_line)}",
        f"{prefix}_post_transition_pre_read_pit_rising={count_between(parsed.pit_rising, transition_line, read_line)}",
        f"{prefix}_post_transition_pre_read_pic_ack={count_between(parsed.pic_ack, transition_line, read_line)}",
        f"{prefix}_post_transition_pre_read_pic_ack30={count_between(parsed.pic_ack30, transition_line, read_line)}",
        f"{prefix}_post_transition_pre_read_service={count_between(parsed.service, transition_line, read_line)}",
        f"{prefix}_post_transition_pre_read_service30={count_between(parsed.service30, transition_line, read_line)}",
        f"{prefix}_post_transition_pre_read_iret_after={count_between(parsed.iret_after, transition_line, read_line)}",
        f"{prefix}_post_transition_pre_read_watch_writes={count_between(parsed.watch_writes, transition_line, read_line)}",
        f"{prefix}_post_transition_pre_read_tick_blocks={count_between(parsed.tick_blocks, transition_line, read_line)}",
        f"{prefix}_first_post_transition_service_line={event_line(first_post_transition_service)}",
        f"{prefix}_first_post_transition_service_intno={field(first_post_transition_service, 'intno')}",
        f"{prefix}_first_post_transition_service_eip={field(first_post_transition_service, 'eip')}",
        f"{prefix}_first_post_transition_ack_line={event_line(first_post_transition_ack)}",
        f"{prefix}_first_post_transition_ack_intno={field(first_post_transition_ack, 'intno')}",
        f"{prefix}_first_post_transition_timer_line={event_line(first_post_transition_timer)}",
        f"{prefix}_first_post_transition_timer_source={field(first_post_transition_timer, 'source')}",
        f"{prefix}_first_post_transition_timer_watch_ticks={timer_watch_ticks(first_post_transition_timer, tick_unit)}",
        f"{prefix}_last_pre_transition_watch_read_line={event_line(last_pre_transition_read)}",
        f"{prefix}_last_pre_transition_watch_read_edge={edge_key(last_pre_transition_read)}",
        f"{prefix}_last_pre_transition_watch_read_ticks={watch_ticks(last_pre_transition_read, tick_unit)}",
        f"{prefix}_last_pre_read_watch_write_line={event_line(last_pre_read_write)}",
        f"{prefix}_last_pre_read_watch_write_eip={field(last_pre_read_write, 'eip')}",
        f"{prefix}_last_pre_read_watch_write_ticks={watch_ticks(last_pre_read_write, tick_unit)}",
        f"{prefix}_last_pre_read_tick_block_line={event_line(last_pre_read_tick_block)}",
        f"{prefix}_last_pre_read_tick_block_start={field(last_pre_read_tick_block, 'start_pc')}",
        f"{prefix}_last_pre_read_tick_block_post_ticks={tick_block_post_ticks(last_pre_read_tick_block, tick_unit)}",
        f"{prefix}_last_pre_read_timer_line={event_line(last_pre_read_timer)}",
        f"{prefix}_last_pre_read_timer_source={field(last_pre_read_timer, 'source')}",
        f"{prefix}_last_pre_read_timer_eip={field(last_pre_read_timer, 'eip')}",
        f"{prefix}_last_pre_read_timer_watch_ticks={timer_watch_ticks(last_pre_read_timer, tick_unit)}",
        f"{prefix}_last_pre_read_pit_line={event_line(last_pre_read_pit)}",
        f"{prefix}_last_pre_read_pit={event_summary(last_pre_read_pit)}",
        f"{prefix}_last_pre_read_pmc_line={event_line(last_pre_read_pmc)}",
        f"{prefix}_last_pre_read_pmc={event_summary(last_pre_read_pmc)}",
        f"{prefix}_last_pre_read_irq_source_line={event_line(last_pre_read_irq_source)}",
        f"{prefix}_last_pre_read_irq_source={event_summary(last_pre_read_irq_source)}",
        f"{prefix}_last_pre_read_pic_line_line={event_line(last_pre_read_pic_line)}",
        f"{prefix}_last_pre_read_pic_line={event_summary(last_pre_read_pic_line)}",
        f"{prefix}_last_pre_read_pic_ack_line={event_line(last_pre_read_pic_ack)}",
        f"{prefix}_last_pre_read_pic_ack={event_summary(last_pre_read_pic_ack)}",
        f"{prefix}_last_pre_read_service_line={event_line(last_pre_read_service)}",
        f"{prefix}_last_pre_read_service_intno={field(last_pre_read_service, 'intno')}",
        f"{prefix}_last_pre_read_service_eip={field(last_pre_read_service, 'eip')}",
        f"{prefix}_last_pre_read_iret_line={event_line(last_pre_read_iret)}",
        f"{prefix}_last_pre_read_iret_eip={field(last_pre_read_iret, 'eip')}",
        f"{prefix}_log={parsed.path}",
    ]


def emit(native: ParsedLog, browser: ParsedLog, watch_phys: str, tick_unit: int) -> int:
    owner = classify_owner(native, browser, tick_unit)
    result = "fail" if owner.startswith("missing-") else "pass"
    native_ticks = first_watch_ticks(native, tick_unit)
    browser_ticks = first_watch_ticks(browser, tick_unit)
    tick_delta = (
        None if native_ticks is None or browser_ticks is None
        else native_ticks - browser_ticks
    )

    parts = [
        "FIRST_WATCH_READ_GAP_OWNER",
        f"result={result}",
        f"first_watch_read_tick_gap_owner={owner}",
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
            "Classify which native/browser event family owns the tick gap at "
            "the first watched 0x0003a890 read."
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
            "FIRST_WATCH_READ_GAP_OWNER result=fail "
            f"reason=invalid-tick-unit tick_unit={args.tick_unit}",
            file=sys.stderr,
        )
        return 1
    if parse_int(args.watch_phys) is None:
        print(
            "FIRST_WATCH_READ_GAP_OWNER result=fail "
            f"reason=invalid-watch-phys watch_phys={args.watch_phys}",
            file=sys.stderr,
        )
        return 1
    watch_phys = hex32(parse_int(args.watch_phys))

    for label, path in (("native", args.native_log), ("browser", args.browser_log)):
        if not path.is_file():
            print(
                "FIRST_WATCH_READ_GAP_OWNER result=fail "
                f"reason=missing-{label}-log path={path}",
                file=sys.stderr,
            )
            return 1

    native = read_log(args.native_log, "native", args.native_context, watch_phys)
    browser = read_log(args.browser_log, "browser", args.browser_context, watch_phys)
    return emit(native, browser, watch_phys, tick_unit)


if __name__ == "__main__":
    raise SystemExit(main())
