#!/usr/bin/env python3
"""Compare native/browser idle-before-PFIFO-transition diagnostics."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path


MARKER = "BOOT_MARK b6 cpu=idle-before-pfifo-transition "


@dataclass
class Marker:
    line_no: int
    fields: dict[str, str]


def parse_fields(line: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for token in line.strip().split():
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        fields[key] = value.strip('"')
    return fields


def read_markers(path: Path) -> list[Marker]:
    markers: list[Marker] = []
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_no, line in enumerate(handle, 1):
            if MARKER not in line:
                continue
            markers.append(Marker(line_no=line_no, fields=parse_fields(line)))
    return markers


def field(marker: Marker | None, key: str, default: str = "missing") -> str:
    if marker is None:
        return default
    return marker.fields.get(key, default)


def marker_key(marker: Marker | None) -> str:
    if marker is None:
        return "missing"

    fields = marker.fields
    transition = f"{fields.get('start_pc', 'missing')}->{fields.get('next_pc', 'missing')}"
    dma = f"{fields.get('nv2a_dma_get', 'missing')}/{fields.get('nv2a_dma_put', 'missing')}"
    wait = f"{fields.get('nv2a_wait_source', 'missing')}/{fields.get('nv2a_wait_op', 'missing')}"
    activity = (
        f"{fields.get('pfifo_activity_phase', 'missing')}:"
        f"{fields.get('pfifo_activity_dma_get_before', 'missing')}->"
        f"{fields.get('pfifo_activity_dma_get_after', 'missing')}:"
        f"final={fields.get('pfifo_activity_final_transition_candidate', 'missing')}"
    )
    return ":".join(
        [
            f"start={transition}",
            f"eip={fields.get('eip', 'missing')}",
            f"pfifo_seen={fields.get('pfifo_transition_seen', 'missing')}",
            f"dma={dma}",
            f"to_put={fields.get('nv2a_dma_to_put', 'missing')}",
            f"wait={wait}",
            f"wait_seq={fields.get('nv2a_wait_seq', 'missing')}",
            f"activity={activity}",
            f"if={fields.get('interrupts_enabled', 'missing')}",
            f"inh={fields.get('irq_inhibited', 'missing')}",
            f"irq={fields.get('cpu_interrupt_request', 'missing')}",
        ]
    )


def divergence(native: Marker | None, browser: Marker | None) -> str:
    if native is None and browser is None:
        return "both-missing"
    if native is None:
        return "browser-idle-before-transition-only"
    if browser is None:
        return "native-idle-before-transition-only"
    if marker_key(native) == marker_key(browser):
        return "none"
    return "idle-before-transition-mismatch"


def format_output(
    native_log: Path,
    browser_log: Path,
    native_markers: list[Marker],
    browser_markers: list[Marker],
) -> str:
    native = native_markers[0] if native_markers else None
    browser = browser_markers[0] if browser_markers else None

    parts = [
        "IDLE_BEFORE_PFIFO_TRANSITION_COMPARE",
        "result=pass",
        f"divergence={divergence(native, browser)}",
        f"native_marker={'present' if native else 'missing'}",
        f"browser_marker={'present' if browser else 'missing'}",
        f"native_count={len(native_markers)}",
        f"browser_count={len(browser_markers)}",
        f"native_line={native.line_no if native else 0}",
        f"browser_line={browser.line_no if browser else 0}",
        f"native_start_pc={field(native, 'start_pc')}",
        f"native_next_pc={field(native, 'next_pc')}",
        f"native_eip={field(native, 'eip')}",
        f"native_dma_get={field(native, 'nv2a_dma_get')}",
        f"native_dma_put={field(native, 'nv2a_dma_put')}",
        f"native_dma_to_put={field(native, 'nv2a_dma_to_put')}",
        f"native_wait_seq={field(native, 'nv2a_wait_seq')}",
        f"native_activity_phase={field(native, 'pfifo_activity_phase')}",
        f"native_activity_active={field(native, 'pfifo_activity_active')}",
        f"native_activity_dma_get_reg={field(native, 'pfifo_activity_dma_get_reg')}",
        f"native_activity_dma_get_before={field(native, 'pfifo_activity_dma_get_before')}",
        f"native_activity_dma_get_after={field(native, 'pfifo_activity_dma_get_after')}",
        f"native_activity_dma_to_put_after={field(native, 'pfifo_activity_dma_to_put_after')}",
        f"native_activity_final_transition_candidate={field(native, 'pfifo_activity_final_transition_candidate')}",
        f"native_activity_pfifo_lock_released={field(native, 'pfifo_activity_pfifo_lock_released')}",
        f"native_activity_pgraph_locked={field(native, 'pfifo_activity_pgraph_locked')}",
        f"native_key={marker_key(native)}",
        f"browser_start_pc={field(browser, 'start_pc')}",
        f"browser_next_pc={field(browser, 'next_pc')}",
        f"browser_eip={field(browser, 'eip')}",
        f"browser_dma_get={field(browser, 'nv2a_dma_get')}",
        f"browser_dma_put={field(browser, 'nv2a_dma_put')}",
        f"browser_dma_to_put={field(browser, 'nv2a_dma_to_put')}",
        f"browser_wait_seq={field(browser, 'nv2a_wait_seq')}",
        f"browser_activity_phase={field(browser, 'pfifo_activity_phase')}",
        f"browser_activity_active={field(browser, 'pfifo_activity_active')}",
        f"browser_activity_dma_get_reg={field(browser, 'pfifo_activity_dma_get_reg')}",
        f"browser_activity_dma_get_before={field(browser, 'pfifo_activity_dma_get_before')}",
        f"browser_activity_dma_get_after={field(browser, 'pfifo_activity_dma_get_after')}",
        f"browser_activity_dma_to_put_after={field(browser, 'pfifo_activity_dma_to_put_after')}",
        f"browser_activity_final_transition_candidate={field(browser, 'pfifo_activity_final_transition_candidate')}",
        f"browser_activity_pfifo_lock_released={field(browser, 'pfifo_activity_pfifo_lock_released')}",
        f"browser_activity_pgraph_locked={field(browser, 'pfifo_activity_pgraph_locked')}",
        f"browser_key={marker_key(browser)}",
        f"native_log={native_log}",
        f"browser_log={browser_log}",
    ]
    return " ".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Compare native/browser cpu=idle-before-pfifo-transition markers "
            "without reading or dumping proprietary fixture bytes."
        )
    )
    parser.add_argument("--native-log", required=True, type=Path)
    parser.add_argument("--browser-log", required=True, type=Path)
    args = parser.parse_args()

    for label, path in (("native", args.native_log), ("browser", args.browser_log)):
        if not path.is_file():
            print(
                f"IDLE_BEFORE_PFIFO_TRANSITION_COMPARE result=fail "
                f"reason=missing-{label}-log path={path}",
                file=sys.stderr,
            )
            return 1

    native_markers = read_markers(args.native_log)
    browser_markers = read_markers(args.browser_log)
    print(format_output(args.native_log, args.browser_log, native_markers, browser_markers))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
