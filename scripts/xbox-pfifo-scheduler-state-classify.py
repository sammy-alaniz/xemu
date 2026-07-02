#!/usr/bin/env python3
"""Classify PFIFO scheduler/wake state before timer opportunities."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


FIELD_RE = re.compile(r'(\S+)=(".*?"|\S+)')


def parse_value(value: str) -> str:
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    return value


def parse_fields(line: str) -> dict[str, str]:
    return {key: parse_value(value) for key, value in FIELD_RE.findall(line)}


def context_matches(fields: dict[str, str], context: str) -> bool:
    return not context or fields.get("context") == context


def field(event: Event | None, key: str, default: str = "none") -> str:
    if event is None:
        return default
    return event.fields.get(key, default)


def event_line(event: Event | None) -> str:
    return str(event.line_no) if event is not None else "0"


def yes_no(value: bool) -> str:
    return "yes" if value else "no"


@dataclass
class Event:
    line_no: int
    kind: str
    fields: dict[str, str]


@dataclass
class ParsedLog:
    path: Path
    xbe_loaded: list[Event]
    entry_ready: list[Event]
    timer_opportunities: list[Event]
    scheduler: list[Event]
    pfifo_progress: list[Event]
    pusher_enter: list[Event]


def read_log(path: Path, context: str) -> ParsedLog:
    xbe_loaded: list[Event] = []
    entry_ready: list[Event] = []
    timer_opportunities: list[Event] = []
    scheduler: list[Event] = []
    pfifo_progress: list[Event] = []
    pusher_enter: list[Event] = []

    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_no, line in enumerate(handle, 1):
            if "BOOT_MARK b6 " not in line:
                continue
            fields = parse_fields(line)
            if not context_matches(fields, context):
                continue
            if fields.get("dashboard") == "xbe-loaded":
                xbe_loaded.append(Event(line_no, "xbe-loaded", fields))
                continue
            if (fields.get("dashboard") == "xbe-entry-probe" and
                    fields.get("status") == "ready"):
                entry_ready.append(Event(line_no, "xbe-entry-ready", fields))
                continue
            if fields.get("headless") == "timer-opportunity":
                timer_opportunities.append(
                    Event(line_no, "timer-opportunity", fields)
                )
                continue
            if fields.get("pfifo") == "scheduler":
                scheduler.append(Event(line_no, "pfifo-scheduler", fields))
                continue
            if fields.get("pfifo") == "progress":
                event = Event(line_no, "pfifo-progress", fields)
                pfifo_progress.append(event)
                if fields.get("op") == "pusher-enter":
                    pusher_enter.append(event)

    return ParsedLog(
        path=path,
        xbe_loaded=xbe_loaded,
        entry_ready=entry_ready,
        timer_opportunities=timer_opportunities,
        scheduler=scheduler,
        pfifo_progress=pfifo_progress,
        pusher_enter=pusher_enter,
    )


def next_event(events: list[Event], line_no: int) -> Event | None:
    for event in events:
        if event.line_no > line_no:
            return event
    return None


def events_between(events: list[Event], start_line: int, end_line: int) -> list[Event]:
    return [event for event in events if start_line < event.line_no < end_line]


def count_op(events: list[Event], op: str) -> int:
    return sum(1 for event in events if field(event, "op") == op)


def last_event(events: list[Event]) -> Event | None:
    return events[-1] if events else None


def unique_field_values(events: list[Event], key: str) -> str:
    values: list[str] = []
    for event in events:
        value = field(event, key)
        if value not in values:
            values.append(value)
    return ",".join(values) if values else "none"


def divergence(
    parsed: ParsedLog,
    first_loaded: Event | None,
    first_opportunity: Event | None,
    scheduler_after_load_before_first: list[Event],
    before_run_before_first: int,
    kick_before_first: int,
    wake_before_first: int,
    wait_before_first: int,
    skip_halt_before_first: int,
) -> tuple[str, str]:
    if first_opportunity is None:
        return "fail", "missing-timer-opportunity"
    if first_loaded is None:
        return "fail", "missing-xbe-loaded-marker"
    if not parsed.scheduler:
        return "skip", "missing-pfifo-scheduler-markers"
    if first_loaded.line_no > first_opportunity.line_no:
        return "fail", "timer-opportunity-before-xbe-loaded"
    if before_run_before_first:
        return "pass", "pusher-call-before-first-opportunity"
    if skip_halt_before_first:
        return "pass", "pfifo-thread-halted-before-first-opportunity"
    if kick_before_first and not wake_before_first:
        return "pass", "pfifo-kick-before-opportunity-without-thread-wake"
    if wake_before_first and not before_run_before_first:
        return "pass", "pfifo-woke-before-opportunity-without-pusher-call"
    if wait_before_first and not kick_before_first:
        return "pass", "pfifo-thread-asleep-before-first-opportunity"
    if not scheduler_after_load_before_first:
        return "pass", "no-pfifo-scheduler-event-before-first-opportunity"
    return "pass", "scheduler-active-without-pusher-call-before-first-opportunity"


def emit(parsed: ParsedLog) -> int:
    first_loaded = parsed.xbe_loaded[0] if parsed.xbe_loaded else None
    entry_ready = parsed.entry_ready[0] if parsed.entry_ready else None
    first_opportunity = (
        parsed.timer_opportunities[0] if parsed.timer_opportunities else None
    )
    last_opportunity = (
        parsed.timer_opportunities[-1] if parsed.timer_opportunities else None
    )

    loaded_line = first_loaded.line_no if first_loaded is not None else 0
    first_opportunity_line = (
        first_opportunity.line_no if first_opportunity is not None else 0
    )
    last_opportunity_line = (
        last_opportunity.line_no if last_opportunity is not None else 0
    )

    scheduler_after_load = [
        event for event in parsed.scheduler if event.line_no > loaded_line
    ]
    scheduler_after_load_before_first = (
        events_between(parsed.scheduler, loaded_line, first_opportunity_line)
        if first_opportunity is not None else []
    )
    last_before = last_event(scheduler_after_load_before_first)
    kick_events_before_first = [
        event for event in scheduler_after_load_before_first
        if field(event, "op") == "kick"
    ]
    first_after_last_opportunity = (
        next_event(parsed.scheduler, last_opportunity_line)
        if last_opportunity is not None else None
    )
    first_kick_after_last = (
        next(
            (event for event in parsed.scheduler
             if event.line_no > last_opportunity_line and
             field(event, "op") == "kick"),
            None,
        )
        if last_opportunity is not None else None
    )
    first_before_run_after_last = (
        next(
            (event for event in parsed.scheduler
             if event.line_no > last_opportunity_line and
             field(event, "op") == "before-run-pusher"),
            None,
        )
        if last_opportunity is not None else None
    )

    kick_before_first = len(kick_events_before_first)
    thread_before_first = sum(
        1 for event in scheduler_after_load_before_first
        if field(event, "op") != "kick"
    )
    wait_before_first = count_op(
        scheduler_after_load_before_first, "idle-wait-before"
    )
    wake_before_first = count_op(
        scheduler_after_load_before_first, "idle-wait-after"
    )
    before_run_before_first = count_op(
        scheduler_after_load_before_first, "before-run-pusher"
    )
    after_run_before_first = count_op(
        scheduler_after_load_before_first, "after-run-pusher"
    )
    skip_halt_before_first = count_op(
        scheduler_after_load_before_first, "skip-halt"
    )

    result, div = divergence(
        parsed,
        first_loaded,
        first_opportunity,
        scheduler_after_load_before_first,
        before_run_before_first,
        kick_before_first,
        wake_before_first,
        wait_before_first,
        skip_halt_before_first,
    )

    parts = [
        "PFIFO_SCHEDULER_STATE_CLASSIFY",
        f"result={result}",
        f"divergence={div}",
        "loop_guard_field=pfifo_scheduler_state_before_first_timer_opportunity",
        f"xbe_loaded_line={event_line(first_loaded)}",
        f"entry_ready_line={event_line(entry_ready)}",
        f"first_opportunity_line={event_line(first_opportunity)}",
        f"last_opportunity_line={event_line(last_opportunity)}",
        f"timer_opportunities={len(parsed.timer_opportunities)}",
        f"scheduler_events={len(parsed.scheduler)}",
        f"scheduler_events_after_load={len(scheduler_after_load)}",
        "scheduler_events_before_first_opportunity="
        f"{len(scheduler_after_load_before_first)}",
        f"kick_events_before_first_opportunity={kick_before_first}",
        f"thread_events_before_first_opportunity={thread_before_first}",
        f"wait_before_first_opportunity={wait_before_first}",
        f"wake_before_first_opportunity={wake_before_first}",
        "before_run_pusher_before_first_opportunity="
        f"{before_run_before_first}",
        "after_run_pusher_before_first_opportunity="
        f"{after_run_before_first}",
        f"skip_halt_before_first_opportunity={skip_halt_before_first}",
        f"last_scheduler_before_first_opportunity_line={event_line(last_before)}",
        f"last_scheduler_before_first_opportunity_op={field(last_before, 'op')}",
        "last_scheduler_before_first_opportunity_dma_get="
        f"{field(last_before, 'dma_get')}",
        "last_scheduler_before_first_opportunity_dma_put="
        f"{field(last_before, 'dma_put')}",
        "last_scheduler_before_first_opportunity_dma_to_put="
        f"{field(last_before, 'dma_to_put')}",
        "last_scheduler_before_first_opportunity_halt="
        f"{field(last_before, 'halt')}",
        "last_scheduler_before_first_opportunity_fifo_kick="
        f"{field(last_before, 'fifo_kick')}",
        "last_scheduler_before_first_opportunity_kick_source="
        f"{field(last_before, 'kick_source')}",
        "last_scheduler_before_first_opportunity_fifo_access="
        f"{field(last_before, 'fifo_access')}",
        "last_scheduler_before_first_opportunity_push_access="
        f"{field(last_before, 'push_access')}",
        "last_scheduler_before_first_opportunity_dma_push_access="
        f"{field(last_before, 'dma_push_access')}",
        "last_scheduler_before_first_opportunity_dma_push_status="
        f"{field(last_before, 'dma_push_status')}",
        "first_scheduler_after_last_opportunity_line="
        f"{event_line(first_after_last_opportunity)}",
        "first_scheduler_after_last_opportunity_op="
        f"{field(first_after_last_opportunity, 'op')}",
        "first_scheduler_after_last_opportunity_kick_source="
        f"{field(first_after_last_opportunity, 'kick_source')}",
        "first_scheduler_after_last_opportunity_dma_get="
        f"{field(first_after_last_opportunity, 'dma_get')}",
        "first_scheduler_after_last_opportunity_dma_put="
        f"{field(first_after_last_opportunity, 'dma_put')}",
        "first_scheduler_after_last_opportunity_dma_to_put="
        f"{field(first_after_last_opportunity, 'dma_to_put')}",
        "kick_sources_before_first_opportunity="
        f"{unique_field_values(kick_events_before_first, 'kick_source')}",
        "first_kick_after_last_opportunity_line="
        f"{event_line(first_kick_after_last)}",
        "first_kick_after_last_opportunity_source="
        f"{field(first_kick_after_last, 'kick_source')}",
        "first_kick_after_last_opportunity_delta="
        f"{(first_kick_after_last.line_no - last_opportunity.line_no) if first_kick_after_last is not None and last_opportunity is not None else 'none'}",
        "first_before_run_pusher_after_last_opportunity_line="
        f"{event_line(first_before_run_after_last)}",
        "first_before_run_pusher_after_last_opportunity_delta="
        f"{(first_before_run_after_last.line_no - last_opportunity.line_no) if first_before_run_after_last is not None and last_opportunity is not None else 'none'}",
        f"first_pusher_enter_line={event_line(parsed.pusher_enter[0] if parsed.pusher_enter else None)}",
        "scheduler_markers_present=" f"{yes_no(bool(parsed.scheduler))}",
    ]

    print(" ".join(parts))
    return 1 if result == "fail" else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser-log", required=True, type=Path)
    parser.add_argument("--context", default="browser-runtime")
    args = parser.parse_args()

    if not args.browser_log.is_file():
        print(
            "PFIFO_SCHEDULER_STATE_CLASSIFY result=fail "
            f"reason=missing-browser-log browser_log={args.browser_log}",
            file=sys.stderr,
        )
        return 2

    return emit(read_log(args.browser_log, args.context))


if __name__ == "__main__":
    sys.exit(main())
