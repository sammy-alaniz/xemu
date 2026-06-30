#!/usr/bin/env python3
"""Audit B6 high-alias dashboard execution samples against XBE hashes."""

import argparse
import importlib.util
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


CODE_PROBE_BYTES = 16
FNV1A64_OFFSET = 1469598103934665603
FNV1A64_PRIME = 1099511628211
UINT64_MASK = (1 << 64) - 1


@dataclass
class AliasSample:
    line: str
    context: str
    image_pc: int
    image_base: int
    image_size: int
    guest_code_read: bool
    guest_code_hash: int | None
    image_code_read: bool
    image_code_hash: int | None
    code_hash_match: bool


@dataclass
class EntryProbe:
    line: str
    context: str
    entry_offset: int | None
    entry_code_read: bool
    entry_code_hash: int | None


@dataclass
class CodeSample:
    line: str
    kind: str
    context: str
    image_pc: int | None
    image_base: int | None
    code_read: bool
    code_hash: int | None


@dataclass
class TargetSample:
    line: str
    context: str
    image_pc: int | None
    image_base: int | None
    target_code_read: bool
    target_code_hash: int | None
    target_image_code_read: bool
    target_image_code_hash: int | None


def fail(reason, **fields):
    parts = [f"DASHBOARD_XBE_HASH_EVIDENCE result=fail reason={reason}"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts), file=sys.stderr)
    return 1


def load_xbe_read_module():
    script_path = Path(__file__).with_name("xbox-dashboard-xbe-read-evidence.py")
    spec = importlib.util.spec_from_file_location("xbox_dashboard_xbe_read",
                                                  script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load {script_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fnv1a64(data):
    value = FNV1A64_OFFSET
    for item in data:
        value ^= item
        value = (value * FNV1A64_PRIME) & UINT64_MASK
    return value


def line_value(line, key):
    prefix = f"{key}="
    for token in line.split():
        if token.startswith(prefix):
            return token[len(prefix):].strip('"')
    return None


def parse_int(value):
    if value is None:
        return None
    try:
        return int(value, 0)
    except ValueError:
        return None


def parse_bool(value):
    return value == "yes"


def parse_alias_sample(line):
    image_pc = parse_int(line_value(line, "image_pc"))
    image_base = parse_int(line_value(line, "image_base"))
    image_size = parse_int(line_value(line, "image_size"))
    if image_pc is None or image_base is None or image_size is None:
        return None

    return AliasSample(
        line=line,
        context=line_value(line, "context") or "unknown",
        image_pc=image_pc,
        image_base=image_base,
        image_size=image_size,
        guest_code_read=parse_bool(line_value(line, "guest_code_read")),
        guest_code_hash=parse_int(line_value(line, "guest_code_hash")),
        image_code_read=parse_bool(line_value(line, "image_code_read")),
        image_code_hash=parse_int(line_value(line, "image_code_hash")),
        code_hash_match=parse_bool(line_value(line, "code_hash_match")),
    )


def parse_entry_probe(line):
    if line_value(line, "status") != "ready":
        return None
    return EntryProbe(
        line=line,
        context=line_value(line, "context") or "unknown",
        entry_offset=parse_int(line_value(line, "entry_offset")),
        entry_code_read=parse_bool(line_value(line, "entry_code_read")),
        entry_code_hash=parse_int(line_value(line, "entry_code_hash")),
    )


def parse_loaded_base(line):
    return parse_int(line_value(line, "guest_addr"))


def parse_code_sample(line, loaded_base):
    context = line_value(line, "context") or "unknown"
    if line.startswith("BOOT_MARK b6 dashboard=xbe-exec-probe "):
        return CodeSample(
            line=line,
            kind="exec-probe",
            context=context,
            image_pc=parse_int(line_value(line, "image_pc")),
            image_base=parse_int(line_value(line, "image_base")),
            code_read=parse_bool(line_value(line, "pc_code_read")),
            code_hash=parse_int(line_value(line, "pc_code_hash")),
        )
    if line.startswith("BOOT_MARK b6 dashboard=xbe-exec-transition "):
        return CodeSample(
            line=line,
            kind="exec-transition-next",
            context=context,
            image_pc=parse_int(line_value(line, "next_image_pc")),
            image_base=loaded_base,
            code_read=parse_bool(line_value(line, "next_code_read")),
            code_hash=parse_int(line_value(line, "next_code_hash")),
        )
    if line.startswith("BOOT_MARK b6 dashboard=xbe-exec-edge "):
        return CodeSample(
            line=line,
            kind="exec-edge-next",
            context=context,
            image_pc=parse_int(line_value(line, "next_image_pc")),
            image_base=loaded_base,
            code_read=parse_bool(line_value(line, "next_code_read")),
            code_hash=parse_int(line_value(line, "next_code_hash")),
        )
    return None


def parse_target_sample(line):
    return TargetSample(
        line=line,
        context=line_value(line, "context") or "unknown",
        image_pc=parse_int(line_value(line, "target_image_pc")),
        image_base=parse_int(line_value(line, "image_base")),
        target_code_read=parse_bool(line_value(line, "target_code_read")),
        target_code_hash=parse_int(line_value(line, "target_code_hash")),
        target_image_code_read=parse_bool(
            line_value(line, "target_image_code_read")
        ),
        target_image_code_hash=parse_int(
            line_value(line, "target_image_code_hash")
        ),
    )


def parse_log(log_path, require_context):
    samples = []
    code_samples = []
    target_samples = []
    entry_probe = None
    loaded_base = None
    with open(log_path, "r", encoding="utf-8", errors="replace") as log:
        for raw_line in log:
            line = raw_line.rstrip("\n")
            if line.startswith("BOOT_MARK b6 dashboard=xbe-loaded "):
                if not require_context or line_value(line, "context") == require_context:
                    loaded_base = parse_loaded_base(line)
                continue
            if line.startswith("BOOT_MARK b6 dashboard=xbe-entry-probe "):
                probe = parse_entry_probe(line)
                if probe and (not require_context or
                              probe.context == require_context):
                    entry_probe = probe
                continue
            code_sample = parse_code_sample(line, loaded_base)
            if code_sample is not None:
                if not require_context or code_sample.context == require_context:
                    code_samples.append(code_sample)
                continue
            if line.startswith("BOOT_MARK b6 dashboard=xbe-entry-target-probe "):
                target_sample = parse_target_sample(line)
                if not require_context or target_sample.context == require_context:
                    target_samples.append(target_sample)
                continue
            if not line.startswith("BOOT_MARK b6 dashboard=xbe-alias-compare "):
                continue
            sample = parse_alias_sample(line)
            if sample is None:
                continue
            if require_context and sample.context != require_context:
                continue
            samples.append(sample)
    return samples, entry_probe, code_samples, target_samples


def load_dashboard_file(readmod, hdd_path, target_names, max_raw_bytes,
                        keep_temp):
    info = readmod.qemu_img_info(hdd_path)
    virtual_size = int(info["virtual-size"])
    image_format = info.get("format", "")
    raw_path, tmp_dir = readmod.image_to_raw(
        hdd_path, image_format, virtual_size, max_raw_bytes, keep_temp,
    )

    try:
        with open(raw_path, "rb") as fp:
            starts = readmod.find_fatx_starts(
                fp, readmod.candidate_offsets(hdd_path, virtual_size),
                virtual_size,
            )
            if not starts:
                raise RuntimeError("missing FATX volume")

            volumes = []
            for index, start in enumerate(starts):
                end = starts[index + 1] if index + 1 < len(starts) else virtual_size
                try:
                    volumes.append(readmod.parse_volume(fp, start, end))
                except (EOFError, ValueError):
                    continue

            matches = readmod.find_dashboard_files(fp, volumes, target_names)
            if not matches:
                raise RuntimeError(
                    f"missing dashboard XBE targets={','.join(target_names)}"
                )

            match = matches[0]
            data = readmod.read_chain_bytes(
                fp, match.volume, match.first_cluster, match.size,
            )
            if len(data) < match.size:
                raise RuntimeError(
                    f"short dashboard XBE read file={match.name} "
                    f"expected={match.size} actual={len(data)}"
                )
            return match.name, data[:match.size], tmp_dir
    except Exception:
        if tmp_dir and not keep_temp:
            shutil.rmtree(tmp_dir)
        raise


def disk_hash_for_offset(file_bytes, offset):
    if offset is None or offset < 0:
        return None
    if offset + CODE_PROBE_BYTES > len(file_bytes):
        return None
    return fnv1a64(file_bytes[offset:offset + CODE_PROBE_BYTES])


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Validate that bounded xbe-alias-compare samples do not look like "
            "dashboard XBE execution by comparing marker hashes with the "
            "dashboard file bytes."
        )
    )
    parser.add_argument("--hdd", required=True, help="Xbox HDD image path")
    parser.add_argument("--log", required=True, help="Boot log path")
    parser.add_argument("--file", action="append", default=[],
                        help="Dashboard XBE basename to find")
    parser.add_argument("--require-context", default="",
                        help="Only consider markers from this context")
    parser.add_argument("--max-raw-bytes", type=int,
                        default=16 * 1024 * 1024 * 1024)
    parser.add_argument("--keep-temp", action="store_true")
    args = parser.parse_args()

    target_names = args.file or ["xboxdash.xbe"]
    tmp_dir = None
    try:
        samples, entry_probe, code_samples, target_samples = parse_log(
            args.log, args.require_context,
        )
        if not samples:
            return fail("missing-alias-compare",
                        log=args.log,
                        context=args.require_context or "any")

        readmod = load_xbe_read_module()
        file_name, file_bytes, tmp_dir = load_dashboard_file(
            readmod, args.hdd, target_names, args.max_raw_bytes,
            args.keep_temp,
        )

        comparable = 0
        guest_image_hash_matches = 0
        guest_disk_hash_matches = 0
        image_disk_hash_matches = 0
        skipped_out_of_range = 0
        skipped_unreadable = 0
        code_comparable = 0
        code_disk_hash_matches = 0
        code_skipped_out_of_range = 0
        code_skipped_unreadable = 0
        target_comparable = 0
        target_disk_hash_matches = 0
        target_image_disk_hash_matches = 0
        target_skipped_out_of_range = 0
        target_skipped_unreadable = 0
        first_code_disk_match = None
        first_target_disk_match = None
        first_guest_disk_match = None
        first_guest_image_match = None
        unique_offsets = set()
        unique_code_offsets = set()
        unique_target_offsets = set()

        for sample in samples:
            offset = sample.image_pc - sample.image_base
            if offset < 0 or offset + CODE_PROBE_BYTES > len(file_bytes):
                skipped_out_of_range += 1
                continue
            disk_hash = disk_hash_for_offset(file_bytes, offset)
            unique_offsets.add(offset)
            if not sample.guest_code_read or sample.guest_code_hash is None:
                skipped_unreadable += 1
                continue

            comparable += 1
            if sample.code_hash_match:
                guest_image_hash_matches += 1
                if first_guest_image_match is None:
                    first_guest_image_match = sample
            if disk_hash == sample.guest_code_hash:
                guest_disk_hash_matches += 1
                if first_guest_disk_match is None:
                    first_guest_disk_match = (sample, disk_hash, offset)
            if (sample.image_code_read and sample.image_code_hash is not None and
                    disk_hash == sample.image_code_hash):
                image_disk_hash_matches += 1

        for sample in code_samples:
            if sample.image_pc is None or sample.image_base is None:
                code_skipped_out_of_range += 1
                continue
            offset = sample.image_pc - sample.image_base
            if offset < 0 or offset + CODE_PROBE_BYTES > len(file_bytes):
                code_skipped_out_of_range += 1
                continue
            disk_hash = disk_hash_for_offset(file_bytes, offset)
            unique_code_offsets.add(offset)
            if not sample.code_read or sample.code_hash is None:
                code_skipped_unreadable += 1
                continue

            code_comparable += 1
            if disk_hash == sample.code_hash:
                code_disk_hash_matches += 1
                if first_code_disk_match is None:
                    first_code_disk_match = (sample, disk_hash, offset)

        for sample in target_samples:
            if sample.image_pc is None or sample.image_base is None:
                target_skipped_out_of_range += 1
                continue
            offset = sample.image_pc - sample.image_base
            if offset < 0 or offset + CODE_PROBE_BYTES > len(file_bytes):
                target_skipped_out_of_range += 1
                continue
            disk_hash = disk_hash_for_offset(file_bytes, offset)
            unique_target_offsets.add(offset)
            if (sample.target_image_code_read and
                    sample.target_image_code_hash is not None and
                    disk_hash == sample.target_image_code_hash):
                target_image_disk_hash_matches += 1
            if not sample.target_code_read or sample.target_code_hash is None:
                target_skipped_unreadable += 1
                continue

            target_comparable += 1
            if disk_hash == sample.target_code_hash:
                target_disk_hash_matches += 1
                if first_target_disk_match is None:
                    first_target_disk_match = (sample, disk_hash, offset)

        if comparable == 0:
            return fail("no-comparable-samples",
                        samples=len(samples),
                        skipped_unreadable=skipped_unreadable,
                        skipped_out_of_range=skipped_out_of_range,
                        context=args.require_context or "any")

        entry_disk_hash_match = "unavailable"
        if entry_probe and entry_probe.entry_code_read:
            entry_disk_hash = disk_hash_for_offset(
                file_bytes, entry_probe.entry_offset,
            )
            if entry_disk_hash is not None and entry_probe.entry_code_hash is not None:
                entry_disk_hash_match = (
                    "yes" if entry_disk_hash == entry_probe.entry_code_hash
                    else "no"
                )

        common_fields = {
            "context": args.require_context or "any",
            "file": file_name,
            "samples": len(samples),
            "comparable": comparable,
            "unique_offsets": len(unique_offsets),
            "sample_bytes": CODE_PROBE_BYTES,
            "guest_image_hash_match": guest_image_hash_matches,
            "guest_disk_hash_match": guest_disk_hash_matches,
            "image_disk_hash_match": image_disk_hash_matches,
            "entry_disk_hash_match": entry_disk_hash_match,
            "exec_samples": len(code_samples),
            "exec_comparable": code_comparable,
            "exec_unique_offsets": len(unique_code_offsets),
            "exec_disk_hash_match": code_disk_hash_matches,
            "exec_skipped_unreadable": code_skipped_unreadable,
            "exec_skipped_out_of_range": code_skipped_out_of_range,
            "target_samples": len(target_samples),
            "target_comparable": target_comparable,
            "target_unique_offsets": len(unique_target_offsets),
            "target_disk_hash_match": target_disk_hash_matches,
            "target_image_disk_hash_match": target_image_disk_hash_matches,
            "target_skipped_unreadable": target_skipped_unreadable,
            "target_skipped_out_of_range": target_skipped_out_of_range,
            "skipped_unreadable": skipped_unreadable,
            "skipped_out_of_range": skipped_out_of_range,
            "disk_offset_model": "raw-image-offset",
            "log": args.log,
        }

        if guest_image_hash_matches:
            sample = first_guest_image_match
            return fail(
                "guest-image-hash-match",
                first_image_pc=f"0x{sample.image_pc:08x}",
                first_image_base=f"0x{sample.image_base:08x}",
                first_guest_hash=f"0x{sample.guest_code_hash:016x}",
                **common_fields,
            )

        if guest_disk_hash_matches:
            sample, disk_hash, offset = first_guest_disk_match
            return fail(
                "guest-disk-hash-match",
                first_image_pc=f"0x{sample.image_pc:08x}",
                first_offset=f"0x{offset:08x}",
                first_guest_hash=f"0x{sample.guest_code_hash:016x}",
                first_disk_hash=f"0x{disk_hash:016x}",
                **common_fields,
            )

        if code_disk_hash_matches:
            sample, disk_hash, offset = first_code_disk_match
            return fail(
                "exec-disk-hash-match",
                first_kind=sample.kind,
                first_image_pc=f"0x{sample.image_pc:08x}",
                first_offset=f"0x{offset:08x}",
                first_code_hash=f"0x{sample.code_hash:016x}",
                first_disk_hash=f"0x{disk_hash:016x}",
                **common_fields,
            )

        if target_disk_hash_matches:
            sample, disk_hash, offset = first_target_disk_match
            return fail(
                "target-disk-hash-match",
                first_image_pc=f"0x{sample.image_pc:08x}",
                first_offset=f"0x{offset:08x}",
                first_target_hash=f"0x{sample.target_code_hash:016x}",
                first_disk_hash=f"0x{disk_hash:016x}",
                **common_fields,
            )

        parts = ["DASHBOARD_XBE_HASH_EVIDENCE result=pass"]
        parts.extend(f"{key}={value}" for key, value in common_fields.items())
        print(" ".join(parts))
        return 0
    except (OSError, RuntimeError, subprocess.CalledProcessError,
            EOFError, ValueError) as exc:
        return fail("error", detail=str(exc).replace(" ", "_"))
    finally:
        if tmp_dir and not args.keep_temp:
            shutil.rmtree(tmp_dir)


if __name__ == "__main__":
    sys.exit(main())
