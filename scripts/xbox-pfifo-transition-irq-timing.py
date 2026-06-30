#!/usr/bin/env python3
"""Compare IRQ/timer timing around the final PFIFO stream-idle transition."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


FIELD_RE = re.compile(r'(\S+)=(".*?"|\S+)')


@dataclass
class Event:
    line_no: int
    kind: str
    fields: dict[str, str]


@dataclass
class Summary:
    label: str
    path: Path
    transition: Event | None
    previous_timer_before: Event | None
    previous_hard_irq_set: Event | None
    first_pit_after: Event | None
    first_timer_after: Event | None
    first_hard_irq_set_after: Event | None
    first_hard_irq_reset_after: Event | None
    first_pic_ack_after: Event | None
    first_service_before_after: Event | None


def parse_value(value: str) -> str:
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    return value


def parse_fields(line: str) -> dict[str, str]:
    return {key: parse_value(value) for key, value in FIELD_RE.findall(line)}


def context_matches(fields: dict[str, str], context: str) -> bool:
    return not context or fields.get("context") == context


def classify(fields: dict[str, str]) -> str:
    if fields.get("pfifo") == "stream-idle-transition":
        return "transition"
    if fields.get("pit") == "irq-timer":
        return "pit"
    if fields.get("tcg") == "timer-pump":
        return "tcg-timer"
    if fields.get("pfifo") == "pre-commit-timer-pump":
        return "pfifo-timer"
    if fields.get("main-loop") == "timers":
        return "main-loop-timer"
    if fields.get("cpu") == "hard-irq":
        return f"hard-irq-{fields.get('op', 'unknown')}"
    if fields.get("pic") == "irq-ack":
        return "pic-ack"
    if (
        fields.get("cpu") == "hard-irq-service"
        and fields.get("phase") == "before"
    ):
        return "hard-irq-service-before"
    return ""


def read_events(path: Path, context: str) -> list[Event]:
    events: list[Event] = []
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_no, line in enumerate(handle, 1):
            if "BOOT_MARK b6 " not in line:
                continue
            fields = parse_fields(line)
            if not context_matches(fields, context):
                continue
            kind = classify(fields)
            if kind:
                events.append(Event(line_no=line_no, kind=kind, fields=fields))
    return events


def first_kind(events: list[Event], kind: str, after_line: int = 0) -> Event | None:
    for event in events:
        if event.line_no > after_line and event.kind == kind:
            return event
    return None


def previous_kind(events: list[Event], kind: str, before_line: int) -> Event | None:
    result = None
    for event in events:
        if event.line_no >= before_line:
            break
        if event.kind == kind:
            result = event
    return result


def first_timer(events: list[Event], after_line: int) -> Event | None:
    for event in events:
        if event.line_no <= after_line:
            continue
        if event.kind in {"tcg-timer", "pfifo-timer", "main-loop-timer"}:
            return event
    return None


def previous_timer(events: list[Event], before_line: int) -> Event | None:
    result = None
    for event in events:
        if event.line_no >= before_line:
            break
        if event.kind in {"tcg-timer", "pfifo-timer", "main-loop-timer"}:
            result = event
    return result


def summarize(path: Path, label: str, context: str) -> Summary:
    events = read_events(path, context)
    transition = first_kind(events, "transition")
    transition_line = transition.line_no if transition else 0
    return Summary(
        label=label,
        path=path,
        transition=transition,
        previous_timer_before=(
            previous_timer(events, transition_line) if transition else None
        ),
        previous_hard_irq_set=(
            previous_kind(events, "hard-irq-set", transition_line)
            if transition
            else None
        ),
        first_pit_after=first_kind(events, "pit", transition_line),
        first_timer_after=first_timer(events, transition_line),
        first_hard_irq_set_after=first_kind(events, "hard-irq-set", transition_line),
        first_hard_irq_reset_after=first_kind(
            events, "hard-irq-reset", transition_line
        ),
        first_pic_ack_after=first_kind(events, "pic-ack", transition_line),
        first_service_before_after=first_kind(
            events, "hard-irq-service-before", transition_line
        ),
    )


def field(event: Event | None, key: str, default: str = "missing") -> str:
    if event is None:
        return default
    return event.fields.get(key, default)


def delta(summary: Summary, event: Event | None) -> str:
    if summary.transition is None or event is None:
        return "missing"
    return str(event.line_no - summary.transition.line_no)


def line_no(event: Event | None) -> str:
    return str(event.line_no) if event else "0"


def event_key(event: Event | None) -> str:
    if event is None:
        return "missing"
    fields = event.fields
    if event.kind == "transition":
        return (
            f"transition:pc={fields.get('eip', 'none')}"
            f":irq={fields.get('cpu_interrupt_request', 'none')}"
            f":pending={fields.get('pending_interrupt', 'unknown')}"
            f":get={fields.get('dma_get_before', 'none')}"
            f"->{fields.get('dma_get_after', 'none')}"
        )
    if event.kind == "pit":
        return (
            f"pit:level={fields.get('irq_level', 'none')}"
            f":pc={fields.get('eip', 'none')}"
            f":irq={fields.get('cpu_interrupt_request', 'none')}"
            f":pending={fields.get('pending_interrupt', 'unknown')}"
        )
    if event.kind in {"tcg-timer", "pfifo-timer", "main-loop-timer"}:
        if event.kind == "tcg-timer":
            source = "tcg"
        elif event.kind == "pfifo-timer":
            source = "pfifo-pre-commit"
        else:
            source = "main-loop"
        return (
            f"{source}:mode={fields.get('mode', 'none')}"
            f":pc={fields.get('eip', 'none')}"
            f":irq={fields.get('cpu_interrupt_request', 'none')}"
            f":progress={fields.get('timer_progress', 'unknown')}"
        )
    if event.kind.startswith("hard-irq"):
        return (
            f"{event.kind}:pc={fields.get('eip', 'none')}"
            f":before={fields.get('request_before', 'none')}"
            f":after={fields.get('request_after', 'none')}"
        )
    if event.kind == "pic-ack":
        return (
            f"ack:intno={fields.get('intno', 'none')}"
            f":guest={fields.get('guest_irq', 'none')}"
            f":pc={fields.get('eip', 'none')}"
        )
    if event.kind == "hard-irq-service-before":
        return (
            f"service:intno={fields.get('intno', 'none')}"
            f":pc={fields.get('eip', 'none')}"
            f":irq={fields.get('cpu_interrupt_request', 'none')}"
            f":stack={fields.get('stack_hash', 'none')}"
        )
    return event.kind


def divergence(native: Summary, browser: Summary) -> str:
    if native.transition is None or browser.transition is None:
        return "missing-transition"
    native_irq = field(native.transition, "cpu_interrupt_request")
    browser_irq = field(browser.transition, "cpu_interrupt_request")
    if native_irq != browser_irq:
        return "transition-pending-irq-mismatch"
    native_timer_kind = (
        native.first_timer_after.kind if native.first_timer_after else "missing"
    )
    browser_timer_kind = (
        browser.first_timer_after.kind if browser.first_timer_after else "missing"
    )
    if native_timer_kind != browser_timer_kind:
        return "post-transition-timer-source-mismatch"
    if event_key(native.first_hard_irq_set_after) != event_key(
        browser.first_hard_irq_set_after
    ):
        return "post-transition-hard-irq-set-mismatch"
    return "none"


def summary_parts(prefix: str, summary: Summary) -> list[str]:
    return [
        f"{prefix}_transition_line={line_no(summary.transition)}",
        f"{prefix}_transition_irq={field(summary.transition, 'cpu_interrupt_request')}",
        f"{prefix}_transition_pending={field(summary.transition, 'pending_interrupt')}",
        f"{prefix}_transition_eip={field(summary.transition, 'eip')}",
        f"{prefix}_previous_timer_before_line={line_no(summary.previous_timer_before)}",
        f"{prefix}_previous_timer_before={event_key(summary.previous_timer_before)}",
        f"{prefix}_previous_hard_irq_set_line={line_no(summary.previous_hard_irq_set)}",
        f"{prefix}_previous_hard_irq_set={event_key(summary.previous_hard_irq_set)}",
        f"{prefix}_first_pit_after_delta={delta(summary, summary.first_pit_after)}",
        f"{prefix}_first_pit_after={event_key(summary.first_pit_after)}",
        f"{prefix}_first_timer_after_delta={delta(summary, summary.first_timer_after)}",
        f"{prefix}_first_timer_after={event_key(summary.first_timer_after)}",
        f"{prefix}_first_hard_irq_set_after_delta={delta(summary, summary.first_hard_irq_set_after)}",
        f"{prefix}_first_hard_irq_set_after={event_key(summary.first_hard_irq_set_after)}",
        f"{prefix}_first_hard_irq_reset_after_delta={delta(summary, summary.first_hard_irq_reset_after)}",
        f"{prefix}_first_hard_irq_reset_after={event_key(summary.first_hard_irq_reset_after)}",
        f"{prefix}_first_pic_ack_after_delta={delta(summary, summary.first_pic_ack_after)}",
        f"{prefix}_first_pic_ack_after={event_key(summary.first_pic_ack_after)}",
        f"{prefix}_first_service_before_after_delta={delta(summary, summary.first_service_before_after)}",
        f"{prefix}_first_service_before_after={event_key(summary.first_service_before_after)}",
        f"{prefix}_log={summary.path}",
    ]


def emit(native: Summary, browser: Summary) -> int:
    div = divergence(native, browser)
    result = "fail" if div == "missing-transition" else "pass"
    parts = [
        "PFIFO_TRANSITION_IRQ_TIMING_COMPARE",
        f"result={result}",
        f"divergence={div}",
    ]
    parts.extend(summary_parts("native", native))
    parts.extend(summary_parts("browser", browser))
    print(" ".join(parts))
    return 1 if result == "fail" else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Summarize native/browser IRQ and timer events around the final "
            "PFIFO stream-idle transition."
        )
    )
    parser.add_argument("--native-log", required=True, type=Path)
    parser.add_argument("--browser-log", required=True, type=Path)
    parser.add_argument("--native-context", default="")
    parser.add_argument("--browser-context", default="")
    args = parser.parse_args()

    for label, path in (("native", args.native_log), ("browser", args.browser_log)):
        if not path.is_file():
            print(
                f"PFIFO_TRANSITION_IRQ_TIMING_COMPARE result=fail "
                f"reason=missing-{label}-log path={path}",
                file=sys.stderr,
            )
            return 1

    native = summarize(args.native_log, "native", args.native_context)
    browser = summarize(args.browser_log, "browser", args.browser_context)
    return emit(native, browser)


if __name__ == "__main__":
    raise SystemExit(main())
