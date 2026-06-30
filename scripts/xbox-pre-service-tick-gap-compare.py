#!/usr/bin/env python3
"""Compare the watched tick word before the post-service B6 handoff."""

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


def edge_key(fields: dict[str, str]) -> str:
    return f"{fields.get('start_pc', 'none')}->{fields.get('next_pc', 'none')}"


def last_edge_key(fields: dict[str, str]) -> str:
    return (
        f"{fields.get('last_transition_start_pc', 'none')}"
        f"->{fields.get('last_transition_next_pc', 'none')}"
    )


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
    timers: list[Event] = field(default_factory=list)
    watch_reads: list[Event] = field(default_factory=list)
    watch_writes: list[Event] = field(default_factory=list)
    services: list[Event] = field(default_factory=list)
    irets_after: list[Event] = field(default_factory=list)
    xbe_executed: list[Event] = field(default_factory=list)

    def first_progress_timer_after_transition(self) -> Event | None:
        return first_after(
            [event for event in self.timers
             if event.fields.get("timer_progress") == "yes"],
            line_no(self.transition),
        )

    def first_watch_read_after_transition(self) -> Event | None:
        return first_after(self.watch_reads, line_no(self.transition))

    def first_watch_write_after_transition(self) -> Event | None:
        return first_after(self.watch_writes, line_no(self.transition))

    def first_service_after_transition(self) -> Event | None:
        return first_after(self.services, line_no(self.transition))

    def first_iret_after_service(self) -> Event | None:
        service = self.first_service_after_transition()
        if service is not None:
            return first_after(self.irets_after, service.line_no)
        return first_after(self.irets_after, line_no(self.transition))


def line_no(event: Event | None) -> int:
    return event.line_no if event is not None else 0


def first_after(events: list[Event], after_line: int) -> Event | None:
    for event in events:
        if event.line_no > after_line:
            return event
    return None


def delta(anchor: Event | None, event: Event | None) -> str:
    if anchor is None or event is None:
        return "missing"
    return str(event.line_no - anchor.line_no)


def signed_delta(from_event: Event | None, to_event: Event | None) -> str:
    if from_event is None or to_event is None:
        return "missing"
    return str(to_event.line_no - from_event.line_no)


def event_line(event: Event | None) -> str:
    return str(event.line_no) if event is not None else "0"


def field(event: Event | None, key: str, default: str = "none") -> str:
    if event is None:
        return default
    return event.fields.get(key, default)


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

            if fields.get("main-loop") == "timers":
                parsed.timers.append(Event(line_no_value, "timer", fields))
                continue

            if (
                fields.get("dashboard") == "kernel-loop-probe"
                and (sig := memory_sig(fields, watch_phys)) is not None
            ):
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

            if (
                fields.get("cpu") == "hard-irq-service"
                and fields.get("phase") == "before"
            ):
                parsed.services.append(Event(line_no_value, "service", fields))
                continue

            if fields.get("cpu") == "iret" and fields.get("phase") == "after":
                parsed.irets_after.append(Event(line_no_value, "iret-after", fields))
                continue

    return parsed


def watch_value(event: Event | None) -> str:
    if event is None:
        return "none"
    if event.mem is not None:
        return event.mem.get("value", "none")
    return event.fields.get("value", "none")


def watch_ticks(event: Event | None, tick_unit: int) -> str:
    return text(tick_count(watch_value(event), tick_unit))


def timer_watch_value(event: Event | None) -> str:
    if event is None:
        return "none"
    if event.fields.get("memory_watch_value_read") != "yes":
        return "none"
    return event.fields.get("memory_watch_value", "none")


def timer_watch_ticks(event: Event | None, tick_unit: int) -> str:
    return text(tick_count(timer_watch_value(event), tick_unit))


def timer_virtual_advance(event: Event | None) -> str:
    if event is None:
        return "none"
    before = parse_int(event.fields.get("virtual_now_before"))
    after = parse_int(event.fields.get("virtual_now_after"))
    if before is None or after is None:
        return "none"
    return str(after - before)


def read_edge(event: Event | None) -> str:
    if event is None:
        return "none"
    return edge_key(event.fields)


def divergence(native: ParsedLog, browser: ParsedLog, tick_unit: int) -> str:
    if browser.xbe_executed:
        return "browser-dashboard-executed"
    if native.transition is None or browser.transition is None:
        return "missing-stream-idle-transition"
    native_read = native.first_watch_read_after_transition()
    browser_read = browser.first_watch_read_after_transition()
    if native_read is None or browser_read is None:
        return "missing-first-watch-read"
    native_ticks = tick_count(watch_value(native_read), tick_unit)
    browser_ticks = tick_count(watch_value(browser_read), tick_unit)
    if native_ticks is None or browser_ticks is None:
        if watch_value(native_read) != watch_value(browser_read):
            return "first-watch-read-value-mismatch"
        return "first-watch-read-equal"
    if browser_ticks < native_ticks:
        return "browser-first-watch-read-before-catchup"
    if browser_ticks > native_ticks:
        return "browser-first-watch-read-ahead"
    return "first-watch-read-equal"


def side_fields(prefix: str, parsed: ParsedLog, tick_unit: int) -> list[str]:
    timer = parsed.first_progress_timer_after_transition()
    read = parsed.first_watch_read_after_transition()
    write = parsed.first_watch_write_after_transition()
    service = parsed.first_service_after_transition()
    iret = parsed.first_iret_after_service()
    boundary = parsed.boundary
    transition = parsed.transition

    read_before_write = (
        read is not None
        and write is not None
        and read.line_no < write.line_no
    )
    timer_before_read = (
        timer is not None
        and read is not None
        and timer.line_no < read.line_no
    )
    service_before_read = (
        service is not None
        and read is not None
        and service.line_no < read.line_no
    )
    write_before_read = (
        write is not None
        and read is not None
        and write.line_no < read.line_no
    )

    return [
        f"{prefix}_xbe_executed={bool_text(bool(parsed.xbe_executed))}",
        f"{prefix}_transition_line={event_line(transition)}",
        f"{prefix}_transition_eip={field(transition, 'eip')}",
        f"{prefix}_transition_irq={field(transition, 'cpu_interrupt_request')}",
        f"{prefix}_transition_pending={field(transition, 'pending_interrupt')}",
        f"{prefix}_transition_pmc_pending={field(transition, 'pmc_pending')}",
        f"{prefix}_transition_pcrtc_pending={field(transition, 'pcrtc_pending')}",
        f"{prefix}_transition_last_edge={last_edge_key(transition.fields) if transition else 'none'}",
        f"{prefix}_boundary_line={event_line(boundary)}",
        f"{prefix}_boundary_eip={field(boundary, 'eip')}",
        f"{prefix}_boundary_irq={field(boundary, 'cpu_interrupt_request')}",
        f"{prefix}_first_timer_line={event_line(timer)}",
        f"{prefix}_first_timer_delta_from_transition={delta(transition, timer)}",
        f"{prefix}_first_timer_source={field(timer, 'source')}",
        f"{prefix}_first_timer_eip={field(timer, 'eip')}",
        f"{prefix}_first_timer_irq={field(timer, 'cpu_interrupt_request')}",
        f"{prefix}_first_timer_virtual_now_before={field(timer, 'virtual_now_before')}",
        f"{prefix}_first_timer_virtual_deadline_before={field(timer, 'virtual_deadline_before')}",
        f"{prefix}_first_timer_virtual_has_timers_before={field(timer, 'virtual_has_timers_before')}",
        f"{prefix}_first_timer_virtual_expired_before={field(timer, 'virtual_expired_before')}",
        f"{prefix}_first_timer_virtual_now_after={field(timer, 'virtual_now_after')}",
        f"{prefix}_first_timer_virtual_deadline_after={field(timer, 'virtual_deadline_after')}",
        f"{prefix}_first_timer_virtual_has_timers_after={field(timer, 'virtual_has_timers_after')}",
        f"{prefix}_first_timer_virtual_expired_after={field(timer, 'virtual_expired_after')}",
        f"{prefix}_first_timer_virtual_advance_ns={timer_virtual_advance(timer)}",
        f"{prefix}_first_timer_watch_value={timer_watch_value(timer)}",
        f"{prefix}_first_timer_watch_ticks={timer_watch_ticks(timer, tick_unit)}",
        f"{prefix}_first_timer_before_read={bool_text(timer_before_read)}",
        f"{prefix}_first_timer_delta_to_read={signed_delta(timer, read)}",
        f"{prefix}_first_timer_delta_to_write={signed_delta(timer, write)}",
        f"{prefix}_first_timer_delta_to_service={signed_delta(timer, service)}",
        f"{prefix}_first_watch_read_line={event_line(read)}",
        f"{prefix}_first_watch_read_delta_from_transition={delta(transition, read)}",
        f"{prefix}_first_watch_read_delta_from_boundary={delta(boundary, read)}",
        f"{prefix}_first_watch_read_edge={read_edge(read)}",
        f"{prefix}_first_watch_read_value={watch_value(read)}",
        f"{prefix}_first_watch_read_ticks={watch_ticks(read, tick_unit)}",
        f"{prefix}_first_watch_read_irq={field(read, 'cpu_interrupt_request')}",
        f"{prefix}_first_watch_read_pending={field(read, 'pending_interrupt')}",
        f"{prefix}_first_watch_read_wait_op={field(read, 'nv2a_wait_op')}",
        f"{prefix}_first_watch_read_pmc_pending={field(read, 'nv2a_pmc_pending')}",
        f"{prefix}_first_watch_read_pcrtc_pending={field(read, 'nv2a_pcrtc_pending')}",
        f"{prefix}_first_watch_write_line={event_line(write)}",
        f"{prefix}_first_watch_write_delta_from_read={delta(read, write)}",
        f"{prefix}_first_watch_write_eip={field(write, 'eip')}",
        f"{prefix}_first_watch_write_value={watch_value(write)}",
        f"{prefix}_first_watch_write_ticks={watch_ticks(write, tick_unit)}",
        f"{prefix}_first_watch_read_before_write={bool_text(read_before_write)}",
        f"{prefix}_first_watch_write_before_read={bool_text(write_before_read)}",
        f"{prefix}_first_service_line={event_line(service)}",
        f"{prefix}_first_service_delta_from_transition={delta(transition, service)}",
        f"{prefix}_first_service_before_read={bool_text(service_before_read)}",
        f"{prefix}_first_service_delta_to_read={signed_delta(service, read)}",
        f"{prefix}_first_service_intno={field(service, 'intno')}",
        f"{prefix}_first_service_eip={field(service, 'eip')}",
        f"{prefix}_first_iret_after_service_line={event_line(iret)}",
        f"{prefix}_first_iret_after_service_eip={field(iret, 'eip')}",
    ]


def emit(native: ParsedLog, browser: ParsedLog, watch_phys: str, tick_unit: int) -> int:
    div = divergence(native, browser, tick_unit)
    result = "fail" if div.startswith("missing-") else "pass"
    native_read = native.first_watch_read_after_transition()
    browser_read = browser.first_watch_read_after_transition()
    native_ticks = tick_count(watch_value(native_read), tick_unit)
    browser_ticks = tick_count(watch_value(browser_read), tick_unit)
    tick_delta = (
        None if native_ticks is None or browser_ticks is None
        else native_ticks - browser_ticks
    )

    parts = [
        "PRE_SERVICE_TICK_GAP_COMPARE",
        f"result={result}",
        f"divergence={div}",
        f"watch_phys={watch_phys}",
        f"tick_unit=0x{tick_unit:08x}",
        f"first_watch_read_tick_delta={text(tick_delta)}",
    ]
    parts.extend(side_fields("native", native, tick_unit))
    parts.extend(side_fields("browser", browser, tick_unit))
    parts.extend([
        f"native_log={native.path}",
        f"browser_log={browser.path}",
    ])
    print(" ".join(parts))
    return 1 if result == "fail" else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Summarize the native/browser watched tick-word gap between PFIFO "
            "stream-idle and the first post-service memory poll."
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
            "PRE_SERVICE_TICK_GAP_COMPARE result=fail "
            f"reason=invalid-tick-unit tick_unit={args.tick_unit}",
            file=sys.stderr,
        )
        return 1
    if parse_int(args.watch_phys) is None:
        print(
            "PRE_SERVICE_TICK_GAP_COMPARE result=fail "
            f"reason=invalid-watch-phys watch_phys={args.watch_phys}",
            file=sys.stderr,
        )
        return 1
    watch_phys = hex32(parse_int(args.watch_phys))

    for label, path in (("native", args.native_log), ("browser", args.browser_log)):
        if not path.is_file():
            print(
                "PRE_SERVICE_TICK_GAP_COMPARE result=fail "
                f"reason=missing-{label}-log path={path}",
                file=sys.stderr,
            )
            return 1

    native = read_log(args.native_log, "native", args.native_context, watch_phys)
    browser = read_log(args.browser_log, "browser", args.browser_context, watch_phys)
    return emit(native, browser, watch_phys, tick_unit)


if __name__ == "__main__":
    raise SystemExit(main())
