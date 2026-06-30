#!/usr/bin/env python3
"""Compare native/browser B6 post-command CPU/XBE handoff diagnostics."""

import argparse
import sys
from dataclasses import dataclass


def line_value(line, key, default=""):
    prefix = f"{key}="
    for token in line.split():
        if token.startswith(prefix):
            return token[len(prefix):].strip('"')
    return default


def bool_word(value):
    return "yes" if value else "no"


@dataclass
class HandoffSummary:
    label: str
    loaded: bool = False
    entry_ready: bool = False
    xbe_executed: bool = False
    exec_probe_count: int = 0
    exec_phys_match_yes_count: int = 0
    exec_high_alias_mismatch_count: int = 0
    transition_count: int = 0
    transition_next_phys_match_yes_count: int = 0
    transition_next_high_alias_mismatch_count: int = 0
    branch_phys_match_yes_count: int = 0
    branch_high_alias_mismatch_count: int = 0
    entry_target_count: int = 0
    entry_target_phys_match_yes_count: int = 0
    entry_target_near_phys_mismatch_count: int = 0
    kernel_loop_count: int = 0
    pfifo_window_count: int = 0
    latest_exec_probe: str = ""
    latest_transition: str = ""
    latest_branch_target_line: str = ""
    latest_entry_target: str = ""
    latest_kernel_loop: str = ""
    latest_pfifo_window: str = ""

    def stream_idle(self):
        return (
            self.latest_pfifo_window
            and line_value(self.latest_pfifo_window, "op", "none") == "pusher-empty"
            and line_value(self.latest_pfifo_window, "dma_get", "none") != "none"
            and line_value(self.latest_pfifo_window, "dma_get")
            == line_value(self.latest_pfifo_window, "dma_put")
        )

    def any_handoff_candidate(self):
        return (
            self.xbe_executed
            or self.exec_phys_match_yes_count > 0
            or self.transition_next_phys_match_yes_count > 0
            or self.branch_phys_match_yes_count > 0
            or self.entry_target_phys_match_yes_count > 0
        )


def fail(reason, **fields):
    parts = [f"POST_COMMAND_HANDOFF_COMPARE result=fail reason={reason}"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts), file=sys.stderr)
    return 1


def parse_log(path, label, context):
    summary = HandoffSummary(label=label)

    try:
        with open(path, "r", encoding="utf-8", errors="replace") as log:
            for raw_line in log:
                line = raw_line.rstrip("\n")
                if context and f"context={context}" not in line:
                    continue
                if line.startswith("BOOT_MARK b6 dashboard=xbe-loaded "):
                    summary.loaded = True
                    continue
                if (
                    line.startswith("BOOT_MARK b6 dashboard=xbe-entry-probe ")
                    and " status=ready " in line
                ):
                    summary.entry_ready = True
                    continue
                if line.startswith("BOOT_MARK b6 dashboard=xbe-executed "):
                    summary.xbe_executed = True
                    continue
                if line.startswith("BOOT_MARK b6 dashboard=xbe-exec-probe "):
                    summary.exec_probe_count += 1
                    summary.latest_exec_probe = line
                    if line_value(line, "phys_match", "unknown") == "yes":
                        summary.exec_phys_match_yes_count += 1
                    if line_value(line, "address_mode", "unknown") == (
                        "high-alias-mismatch"
                    ):
                        summary.exec_high_alias_mismatch_count += 1
                    if line_value(line, "branch_target_known", "no") == "yes":
                        summary.latest_branch_target_line = line
                        if line_value(line, "branch_phys_match", "unknown") == "yes":
                            summary.branch_phys_match_yes_count += 1
                        if line_value(line, "branch_address_mode", "unknown") == (
                            "high-alias-mismatch"
                        ):
                            summary.branch_high_alias_mismatch_count += 1
                    continue
                if line.startswith("BOOT_MARK b6 dashboard=xbe-exec-transition "):
                    summary.transition_count += 1
                    summary.latest_transition = line
                    if line_value(line, "next_phys_match", "unknown") == "yes":
                        summary.transition_next_phys_match_yes_count += 1
                    if line_value(line, "next_address_mode", "unknown") == (
                        "high-alias-mismatch"
                    ):
                        summary.transition_next_high_alias_mismatch_count += 1
                    if line_value(line, "next_branch_target_known", "no") == "yes":
                        summary.latest_branch_target_line = line
                        if line_value(line, "next_branch_phys_match", "unknown") == (
                            "yes"
                        ):
                            summary.branch_phys_match_yes_count += 1
                        if line_value(line, "next_branch_address_mode", "unknown") == (
                            "high-alias-mismatch"
                        ):
                            summary.branch_high_alias_mismatch_count += 1
                    continue
                if line.startswith("BOOT_MARK b6 dashboard=xbe-exec-edge "):
                    if line_value(line, "next_branch_target_known", "no") == "yes":
                        summary.latest_branch_target_line = line
                        if line_value(line, "next_branch_phys_match", "unknown") == (
                            "yes"
                        ):
                            summary.branch_phys_match_yes_count += 1
                        if line_value(line, "next_branch_address_mode", "unknown") == (
                            "high-alias-mismatch"
                        ):
                            summary.branch_high_alias_mismatch_count += 1
                    continue
                if line.startswith("BOOT_MARK b6 dashboard=xbe-entry-target-probe "):
                    summary.entry_target_count += 1
                    summary.latest_entry_target = line
                    if line_value(line, "target_phys_match", "unknown") == "yes":
                        summary.entry_target_phys_match_yes_count += 1
                    if (
                        line_value(line, "target_status", "unknown")
                        == "near-phys-mismatch"
                    ):
                        summary.entry_target_near_phys_mismatch_count += 1
                    continue
                if line.startswith("BOOT_MARK b6 dashboard=kernel-loop-probe "):
                    summary.kernel_loop_count += 1
                    summary.latest_kernel_loop = line
                    continue
                if line.startswith("BOOT_MARK b6 pfifo=window "):
                    summary.pfifo_window_count += 1
                    summary.latest_pfifo_window = line
                    continue
    except OSError as exc:
        raise RuntimeError(f"{label} log unreadable: {exc}") from exc

    return summary


def divergence_for(native, browser):
    if browser.xbe_executed:
        return "browser-xbe-executed"
    if native.xbe_executed:
        return "native-xbe-executed-only"
    if not native.entry_ready or not browser.entry_ready:
        return "entry-not-ready"
    if not native.stream_idle() or not browser.stream_idle():
        return "command-stream-not-idle"
    if native.any_handoff_candidate() or browser.any_handoff_candidate():
        return "handoff-candidate-without-executed-marker"
    native_loop = line_value(native.latest_kernel_loop, "start_pc", "none")
    browser_loop = line_value(browser.latest_kernel_loop, "start_pc", "none")
    if native_loop != browser_loop:
        return "post-command-loop-mismatch"
    return "no-handoff-candidate"


def blocker_for(native, browser):
    if browser.xbe_executed:
        return "none"
    if not browser.loaded:
        return "browser-xbe-not-loaded"
    if not browser.entry_ready:
        return "browser-entry-not-ready"
    if not native.entry_ready:
        return "native-entry-not-ready"
    if not browser.stream_idle():
        return "browser-command-stream-not-idle"
    if not native.stream_idle():
        return "native-command-stream-not-idle"
    if (
        browser.exec_phys_match_yes_count > 0
        or browser.transition_next_phys_match_yes_count > 0
        or browser.branch_phys_match_yes_count > 0
        or browser.entry_target_phys_match_yes_count > 0
    ):
        return "browser-handoff-candidate-without-executed-marker"
    if (
        native.exec_phys_match_yes_count > 0
        or native.transition_next_phys_match_yes_count > 0
        or native.branch_phys_match_yes_count > 0
        or native.entry_target_phys_match_yes_count > 0
    ):
        return "native-handoff-candidate-without-browser-executed"
    browser_high_alias_mismatch = (
        browser.exec_high_alias_mismatch_count > 0
        or browser.transition_next_high_alias_mismatch_count > 0
    )
    native_high_alias_mismatch = (
        native.exec_high_alias_mismatch_count > 0
        or native.transition_next_high_alias_mismatch_count > 0
    )
    if browser_high_alias_mismatch and native_high_alias_mismatch:
        return "both-high-alias-phys-mismatch"
    if browser_high_alias_mismatch:
        return "browser-high-alias-phys-mismatch"
    if native_high_alias_mismatch:
        return "native-high-alias-phys-mismatch"
    return "no-handoff-candidate"


def add_side_fields(fields, prefix, summary):
    exec_line = summary.latest_exec_probe
    transition_line = summary.latest_transition
    branch_line = summary.latest_branch_target_line
    entry_target_line = summary.latest_entry_target
    loop_line = summary.latest_kernel_loop
    pfifo_line = summary.latest_pfifo_window

    fields.update(
        {
            f"{prefix}_loaded": bool_word(summary.loaded),
            f"{prefix}_entry_ready": bool_word(summary.entry_ready),
            f"{prefix}_xbe_executed": bool_word(summary.xbe_executed),
            f"{prefix}_stream_idle": bool_word(summary.stream_idle()),
            f"{prefix}_exec_probes": summary.exec_probe_count,
            f"{prefix}_exec_phys_match_yes": summary.exec_phys_match_yes_count,
            f"{prefix}_exec_high_alias_mismatch": (
                summary.exec_high_alias_mismatch_count
            ),
            f"{prefix}_latest_exec_pc": line_value(exec_line, "guest_pc", "none"),
            f"{prefix}_latest_exec_mode": line_value(
                exec_line, "address_mode", "none"
            ),
            f"{prefix}_latest_exec_phys_match": line_value(
                exec_line, "phys_match", "unknown"
            ),
            f"{prefix}_latest_exec_hash": line_value(
                exec_line, "pc_code_hash", "none"
            ),
            f"{prefix}_latest_exec_opcode": line_value(
                exec_line, "pc_opcode", "none"
            ),
            f"{prefix}_transitions": summary.transition_count,
            f"{prefix}_transition_next_phys_match_yes": (
                summary.transition_next_phys_match_yes_count
            ),
            f"{prefix}_transition_next_high_alias_mismatch": (
                summary.transition_next_high_alias_mismatch_count
            ),
            f"{prefix}_branch_phys_match_yes": (
                summary.branch_phys_match_yes_count
            ),
            f"{prefix}_branch_high_alias_mismatch": (
                summary.branch_high_alias_mismatch_count
            ),
            f"{prefix}_latest_branch_target": (
                line_value(branch_line, "branch_target", "")
                or line_value(branch_line, "next_branch_target", "none")
            ),
            f"{prefix}_latest_branch_phys_match": (
                line_value(branch_line, "branch_phys_match", "")
                or line_value(branch_line, "next_branch_phys_match", "unknown")
            ),
            f"{prefix}_latest_branch_address_mode": (
                line_value(branch_line, "branch_address_mode", "")
                or line_value(branch_line, "next_branch_address_mode", "unknown")
            ),
            f"{prefix}_entry_targets": summary.entry_target_count,
            f"{prefix}_entry_target_phys_match_yes": (
                summary.entry_target_phys_match_yes_count
            ),
            f"{prefix}_entry_target_near_phys_mismatch": (
                summary.entry_target_near_phys_mismatch_count
            ),
            f"{prefix}_latest_entry_target": line_value(
                entry_target_line, "branch_target", "none"
            ),
            f"{prefix}_latest_entry_target_status": line_value(
                entry_target_line, "target_status", "none"
            ),
            f"{prefix}_latest_entry_target_phys_match": line_value(
                entry_target_line, "target_phys_match", "unknown"
            ),
            f"{prefix}_latest_entry_target_code_read": line_value(
                entry_target_line, "target_code_read", "unknown"
            ),
            f"{prefix}_latest_entry_target_hash": line_value(
                entry_target_line, "target_code_hash", "none"
            ),
            f"{prefix}_latest_entry_target_image_code_read": line_value(
                entry_target_line, "target_image_code_read", "unknown"
            ),
            f"{prefix}_latest_entry_target_image_hash": line_value(
                entry_target_line, "target_image_code_hash", "none"
            ),
            f"{prefix}_latest_entry_target_hash_match": line_value(
                entry_target_line, "target_code_hash_match", "unknown"
            ),
            f"{prefix}_latest_transition_start": line_value(
                transition_line, "start_pc", "none"
            ),
            f"{prefix}_latest_transition_next": line_value(
                transition_line, "next_pc", "none"
            ),
            f"{prefix}_latest_transition_next_mode": line_value(
                transition_line, "next_address_mode", "none"
            ),
            f"{prefix}_latest_transition_next_phys_match": line_value(
                transition_line, "next_phys_match", "unknown"
            ),
            f"{prefix}_latest_transition_next_hash": line_value(
                transition_line, "next_code_hash", "none"
            ),
            f"{prefix}_kernel_loops": summary.kernel_loop_count,
            f"{prefix}_latest_loop_start": line_value(loop_line, "start_pc", "none"),
            f"{prefix}_latest_loop_next": line_value(loop_line, "next_pc", "none"),
            f"{prefix}_latest_loop_kind": line_value(loop_line, "loop_kind", "none"),
            f"{prefix}_latest_loop_cpu_mode": line_value(
                loop_line, "cpu_mode", "none"
            ),
            f"{prefix}_latest_loop_cpl": line_value(loop_line, "cpl", "none"),
            f"{prefix}_latest_loop_cs": line_value(loop_line, "cs", "none"),
            f"{prefix}_latest_loop_wait_source": line_value(
                loop_line, "nv2a_wait_source", "none"
            ),
            f"{prefix}_latest_loop_wait_op": line_value(
                loop_line, "nv2a_wait_op", "none"
            ),
            f"{prefix}_latest_loop_start_hash": line_value(
                loop_line, "start_code_hash", "none"
            ),
            f"{prefix}_latest_loop_start_opcode": line_value(
                loop_line, "start_opcode", "none"
            ),
            f"{prefix}_latest_loop_next_hash": line_value(
                loop_line, "next_code_hash", "none"
            ),
            f"{prefix}_latest_loop_next_opcode": line_value(
                loop_line, "next_opcode", "none"
            ),
            f"{prefix}_latest_loop_next_mem_region": line_value(
                loop_line, "next_mem_region", "none"
            ),
            f"{prefix}_latest_loop_next_mem_value_read": line_value(
                loop_line, "next_mem_value_read", "unknown"
            ),
            f"{prefix}_pfifo_windows": summary.pfifo_window_count,
            f"{prefix}_latest_pfifo_op": line_value(pfifo_line, "op", "none"),
            f"{prefix}_latest_pfifo_dma_get": line_value(
                pfifo_line, "dma_get", "none"
            ),
            f"{prefix}_latest_pfifo_dma_put": line_value(
                pfifo_line, "dma_put", "none"
            ),
        }
    )


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Summarize native/browser post-command CPU handoff evidence without "
            "reading or dumping proprietary asset bytes."
        )
    )
    parser.add_argument("--native-log", required=True)
    parser.add_argument("--browser-log", required=True)
    parser.add_argument("--native-context", default="native-headless")
    parser.add_argument("--browser-context", default="browser-runtime")
    args = parser.parse_args()

    try:
        native = parse_log(args.native_log, "native", args.native_context)
        browser = parse_log(args.browser_log, "browser", args.browser_context)
    except RuntimeError as exc:
        return fail(str(exc).replace(" ", "-"))

    if not native.loaded:
        return fail("missing-native-xbe-loaded", native_log=args.native_log)
    if not browser.loaded:
        return fail("missing-browser-xbe-loaded", browser_log=args.browser_log)
    if native.exec_probe_count == 0 and native.transition_count == 0:
        return fail("missing-native-exec-diagnostics", native_log=args.native_log)
    if browser.exec_probe_count == 0 and browser.transition_count == 0:
        return fail("missing-browser-exec-diagnostics", browser_log=args.browser_log)

    divergence = divergence_for(native, browser)
    fields = {
        "divergence": divergence,
        "handoff_blocker": blocker_for(native, browser),
        "both_entry_ready": bool_word(native.entry_ready and browser.entry_ready),
        "both_stream_idle": bool_word(native.stream_idle() and browser.stream_idle()),
        "any_handoff_candidate": bool_word(
            native.any_handoff_candidate() or browser.any_handoff_candidate()
        ),
    }
    add_side_fields(fields, "native", native)
    add_side_fields(fields, "browser", browser)
    fields.update(
        {
            "native_log": args.native_log,
            "browser_log": args.browser_log,
        }
    )

    parts = ["POST_COMMAND_HANDOFF_COMPARE result=pass"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
