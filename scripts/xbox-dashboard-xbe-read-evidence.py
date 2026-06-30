#!/usr/bin/env python3
"""Correlate Xbox dashboard XBE FATX sectors with boot IDE read markers."""

import argparse
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass


SECTOR_SIZE = 512
FATX_HEADER_SIZE = 4096
FATX_DIR_ENTRY_SIZE = 64
DEFAULT_MAX_RAW_BYTES = 16 * 1024 * 1024 * 1024

STANDARD_FATX_OFFSETS = [
    0x00000000,
    0x2EE80000,
    0x5DC80000,
    0x6F290000,
    0x80890000,
    0x82B90000,
    0x85A90000,
    0x88990000,
    0x8BC10000,
    0x8CA80000,
    0xABE80000,
]


@dataclass
class FatxVolume:
    start: int
    end: int
    sectors_per_cluster: int
    root_cluster: int
    cluster_size: int
    fat_entry_size: int
    fat_start: int
    data_start: int


@dataclass
class FatxFile:
    name: str
    path: str
    volume: FatxVolume
    first_cluster: int
    size: int
    clusters: list[int]


@dataclass
class IdeRead:
    line: str
    context: str
    index: int
    lba: int
    sectors: int
    method: str


def fail(reason, **fields):
    parts = [f"DASHBOARD_XBE_READ_EVIDENCE result=fail reason={reason}"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts), file=sys.stderr)
    return 1


def file_failure_fields(matches):
    if not matches:
        return {}

    match = matches[0]
    ranges = file_ranges(match)
    if not ranges:
        return {
            "file": match.name,
            "file_size": match.size,
        }

    first_lba, first_sectors, _cluster = ranges[0]
    last_lba = max(start + sectors - 1 for start, sectors, _cluster in ranges)
    return {
        "file": match.name,
        "start_lba": first_lba,
        "sectors": sum(sectors for _start, sectors, _cluster in ranges),
        "end_lba": last_lba,
        "file_size": match.size,
        "partition_lba": match.volume.start // SECTOR_SIZE,
    }


def read_failure_fields(reads):
    if not reads:
        return {}

    latest = reads[-1]
    return {
        "latest_context": latest.context,
        "latest_read_index": latest.index,
        "latest_read_lba": latest.lba,
        "latest_read_nsectors": latest.sectors,
    }


def run_json(cmd):
    result = subprocess.run(cmd, check=True, stdout=subprocess.PIPE, text=True)
    return json.loads(result.stdout)


def qemu_img_info(path):
    return run_json(["qemu-img", "info", "--output=json", path])


def qemu_img_map(path):
    try:
        return run_json(["qemu-img", "map", "--output=json", path])
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return []


def round_up(value, multiple):
    return ((value + multiple - 1) // multiple) * multiple


def read_at(fp, offset, size):
    fp.seek(offset)
    data = fp.read(size)
    if len(data) != size:
        raise EOFError(f"short read at {offset}")
    return data


def image_to_raw(path, image_format, virtual_size, max_raw_bytes, keep_temp):
    if image_format == "raw":
        return path, None

    if virtual_size > max_raw_bytes:
        raise RuntimeError(
            f"image virtual size {virtual_size} exceeds max raw conversion "
            f"{max_raw_bytes}"
        )

    tmp_dir = tempfile.mkdtemp(prefix="xemu-dashboard-xbe-read.")
    raw_path = os.path.join(tmp_dir, "hdd.raw")
    subprocess.run(
        ["qemu-img", "convert", "-O", "raw", "-S", "4096", path, raw_path],
        check=True,
    )
    if keep_temp:
        print(
            f"DASHBOARD_XBE_READ_EVIDENCE temp_raw={raw_path}",
            file=sys.stderr,
        )
        return raw_path, None
    return raw_path, tmp_dir


def candidate_offsets(image_path, virtual_size):
    offsets = set()
    for item in qemu_img_map(image_path):
        if item.get("data") and item.get("start", -1) % SECTOR_SIZE == 0:
            offsets.add(int(item["start"]))

    offsets.update(offset for offset in STANDARD_FATX_OFFSETS
                   if 0 <= offset < virtual_size)

    scan_limit = min(virtual_size, 16 * 1024 * 1024)
    offsets.update(range(0, scan_limit, 64 * 1024))
    return sorted(offsets)


def find_fatx_starts(fp, candidates, virtual_size):
    starts = []
    for offset in candidates:
        if offset + 16 > virtual_size:
            continue
        try:
            header = read_at(fp, offset, 16)
        except EOFError:
            continue
        if header[:4] == b"FATX":
            starts.append(offset)
    return sorted(set(starts))


def parse_volume(fp, start, end):
    header = read_at(fp, start, 16)
    sectors_per_cluster = struct.unpack_from("<I", header, 8)[0]
    root_cluster = struct.unpack_from("<I", header, 12)[0]
    if sectors_per_cluster == 0 or sectors_per_cluster > 4096:
        raise ValueError("bad sectors_per_cluster")
    if root_cluster == 0:
        raise ValueError("bad root_cluster")

    cluster_size = sectors_per_cluster * SECTOR_SIZE
    approx_clusters = max(1, (end - start - FATX_HEADER_SIZE) // cluster_size)
    fat_entry_size = 2 if approx_clusters < 65525 else 4
    fat_bytes = round_up(approx_clusters * fat_entry_size, cluster_size)
    data_start = start + FATX_HEADER_SIZE + fat_bytes
    if data_start >= end:
        raise ValueError("bad data_start")

    return FatxVolume(
        start=start,
        end=end,
        sectors_per_cluster=sectors_per_cluster,
        root_cluster=root_cluster,
        cluster_size=cluster_size,
        fat_entry_size=fat_entry_size,
        fat_start=start + FATX_HEADER_SIZE,
        data_start=data_start,
    )


def cluster_offset(volume, cluster):
    return volume.data_start + (cluster - 1) * volume.cluster_size


def fat_entry(fp, volume, cluster):
    offset = volume.fat_start + cluster * volume.fat_entry_size
    if offset + volume.fat_entry_size > volume.data_start:
        return None
    data = read_at(fp, offset, volume.fat_entry_size)
    if volume.fat_entry_size == 2:
        return struct.unpack("<H", data)[0]
    return struct.unpack("<I", data)[0]


def is_eoc(volume, value):
    if value is None:
        return True
    if volume.fat_entry_size == 2:
        return value >= 0xFFF8
    return value >= 0x0FFFFFF8


def read_cluster_chain(fp, volume, first_cluster, needed_bytes=None,
                       max_clusters=4096):
    clusters = []
    seen = set()
    cluster = first_cluster
    while cluster and cluster not in seen and len(clusters) < max_clusters:
        offset = cluster_offset(volume, cluster)
        if offset < volume.data_start or offset >= volume.end:
            break
        clusters.append(cluster)
        seen.add(cluster)
        if needed_bytes is not None and (
            len(clusters) * volume.cluster_size >= needed_bytes
        ):
            break
        next_cluster = fat_entry(fp, volume, cluster)
        if is_eoc(volume, next_cluster):
            break
        cluster = next_cluster
    return clusters


def read_chain_bytes(fp, volume, first_cluster, max_bytes):
    chunks = []
    remaining = max_bytes
    for cluster in read_cluster_chain(fp, volume, first_cluster,
                                      needed_bytes=max_bytes):
        offset = cluster_offset(volume, cluster)
        size = min(volume.cluster_size, remaining)
        chunks.append(read_at(fp, offset, size))
        remaining -= size
        if remaining <= 0:
            break
    return b"".join(chunks)


def decode_name(raw):
    return raw.decode("ascii", errors="ignore")


def walk_directory(fp, volume, cluster, prefix="", depth=0, visited=None):
    if visited is None:
        visited = set()
    if depth > 8 or cluster in visited:
        return
    visited.add(cluster)

    data = read_chain_bytes(fp, volume, cluster, 1024 * 1024)
    for offset in range(0, len(data) - FATX_DIR_ENTRY_SIZE + 1,
                        FATX_DIR_ENTRY_SIZE):
        entry = data[offset:offset + FATX_DIR_ENTRY_SIZE]
        name_len = entry[0]
        if name_len in (0x00, 0xFF, 0xE5):
            continue
        if name_len > 42:
            continue
        attrs = entry[1]
        name = decode_name(entry[2:2 + name_len])
        if not name or name in (".", ".."):
            continue
        first_cluster = struct.unpack_from("<I", entry, 44)[0]
        size = struct.unpack_from("<I", entry, 48)[0]
        path = f"{prefix}/{name}" if prefix else name
        yield path, name, attrs, first_cluster, size
        if attrs & 0x10 and first_cluster:
            yield from walk_directory(fp, volume, first_cluster, path,
                                      depth + 1, visited)


def find_dashboard_files(fp, volumes, target_names):
    targets = {name.lower() for name in target_names}
    matches = []
    for volume in volumes:
        for path, name, attrs, first_cluster, size in walk_directory(
            fp, volume, volume.root_cluster
        ):
            if attrs & 0x10:
                continue
            if name.lower() not in targets:
                continue
            clusters = read_cluster_chain(fp, volume, first_cluster,
                                          needed_bytes=size)
            if not clusters:
                continue
            matches.append(FatxFile(
                name=name,
                path=path,
                volume=volume,
                first_cluster=first_cluster,
                size=size,
                clusters=clusters,
            ))
    return matches


def file_ranges(fatx_file):
    remaining = fatx_file.size
    ranges = []
    for cluster in fatx_file.clusters:
        start = cluster_offset(fatx_file.volume, cluster)
        length = min(fatx_file.volume.cluster_size, remaining)
        if length <= 0:
            break
        ranges.append((start // SECTOR_SIZE,
                       math.ceil(length / SECTOR_SIZE),
                       cluster))
        remaining -= length
    return ranges


def line_value(line, key):
    prefix = f"{key}="
    for token in line.split():
        if token.startswith(prefix):
            return token[len(prefix):].strip('"')
    return None


def context_for_line(line, current_context):
    if line.startswith("BOOT_SMOKE_SUMMARY "):
        mode = line_value(line, "mode")
        if mode in ("docker-headless", "native-headless", "native-container",
                    "native-local"):
            return "native-headless"
        if mode:
            return mode
    if line.startswith("BROWSER_BLOCK_CALLBACK_SMOKE "):
        return "browser-block-callback"
    if (line.startswith("BROWSER_RUNTIME_TRANSCRIPT_BEGIN") or
            line.startswith("BROWSER_BOOT_START") or
            line.startswith("BROWSER_RUNTIME_TRANSCRIPT ") or
            line.startswith("BROWSER_RUNTIME_SMOKE ")):
        return "browser-runtime"
    return current_context


def parse_ide_reads(log_path, default_context, require_context):
    pattern = re.compile(
        r"^BOOT_MARK b3 ide=hdd read_index=(?P<index>[0-9]+) "
        r"read_lba=(?P<lba>[0-9]+) nsectors=(?P<sectors>[0-9]+) "
        r"method=(?P<method>pio|dma) "
    )
    reads = []
    current_context = default_context
    with open(log_path, "r", encoding="utf-8", errors="replace") as log:
        for line in log:
            stripped = line.rstrip("\n")
            current_context = context_for_line(stripped, current_context)
            match = pattern.match(stripped)
            if not match:
                continue
            if require_context and current_context != require_context:
                continue
            reads.append(IdeRead(
                line=stripped,
                context=current_context,
                index=int(match.group("index")),
                lba=int(match.group("lba")),
                sectors=int(match.group("sectors")),
                method=match.group("method"),
            ))
    return reads


def overlap(a_start, a_count, b_start, b_count):
    start = max(a_start, b_start)
    end = min(a_start + a_count, b_start + b_count)
    if end <= start:
        return None
    return start, end - start


def emit_read_marker(match, file_range, read, overlap_range):
    file_lba, file_sectors, cluster = file_range
    overlap_lba, overlap_sectors = overlap_range
    print(
        "BOOT_MARK b6 dashboard=xbe-read "
        f"context={read.context} file={match.name} path={match.path} "
        f"partition_lba={match.volume.start // SECTOR_SIZE} "
        f"start_lba={file_lba} sectors={file_sectors} "
        f"file_size={match.size} first_cluster={match.first_cluster} "
        f"cluster={cluster} read_index={read.index} "
        f"read_lba={read.lba} read_nsectors={read.sectors} "
        f"overlap_lba={overlap_lba} overlap_sectors={overlap_sectors} "
        f"method={read.method} source=ide-read-log"
    )
    print(
        "DASHBOARD_XBE_READ_EVIDENCE result=pass "
        f"context={read.context} file={match.name} "
        f"start_lba={file_lba} sectors={file_sectors} "
        f"read_lba={read.lba} read_nsectors={read.sectors} "
        f"overlap_lba={overlap_lba} overlap_sectors={overlap_sectors}",
        file=sys.stderr,
    )


def main():
    parser = argparse.ArgumentParser(
        description="Emit B6 xbe-read evidence from FATX + IDE LBA logs."
    )
    parser.add_argument("--hdd", required=True, help="Xbox HDD image path")
    parser.add_argument("--log", required=True, help="Boot log path")
    parser.add_argument("--file", action="append", default=[],
                        help="Dashboard XBE basename to find")
    parser.add_argument("--max-raw-bytes", type=int,
                        default=DEFAULT_MAX_RAW_BYTES)
    parser.add_argument("--default-context", default="unknown",
                        help="Context label for IDE reads outside known sections")
    parser.add_argument("--require-context", default="",
                        help="Only consider IDE reads from this context")
    parser.add_argument("--keep-temp", action="store_true")
    args = parser.parse_args()

    target_names = args.file or ["xboxdash.xbe"]
    tmp_dir = None
    try:
        info = qemu_img_info(args.hdd)
        virtual_size = int(info["virtual-size"])
        image_format = info.get("format", "")
        candidates = candidate_offsets(args.hdd, virtual_size)
        raw_path, tmp_dir = image_to_raw(
            args.hdd, image_format, virtual_size, args.max_raw_bytes,
            args.keep_temp,
        )

        with open(raw_path, "rb") as fp:
            starts = find_fatx_starts(fp, candidates, virtual_size)
            if not starts:
                return fail("missing-fatx-volume", hdd=args.hdd)

            volumes = []
            for index, start in enumerate(starts):
                end = starts[index + 1] if index + 1 < len(starts) else virtual_size
                try:
                    volumes.append(parse_volume(fp, start, end))
                except (EOFError, ValueError):
                    continue

            matches = find_dashboard_files(fp, volumes, target_names)
            if not matches:
                return fail("missing-dashboard-xbe",
                            targets=",".join(target_names))

            reads = parse_ide_reads(
                args.log, args.default_context, args.require_context
            )
            if not reads:
                fields = {
                    "log": args.log,
                    "context": args.require_context or "any",
                }
                fields.update(file_failure_fields(matches))
                return fail("missing-ide-read-markers", **fields)

            for match in matches:
                for file_range in file_ranges(match):
                    file_lba, file_sectors, _cluster = file_range
                    for read in reads:
                        overlap_range = overlap(file_lba, file_sectors,
                                                read.lba, read.sectors)
                        if overlap_range:
                            emit_read_marker(match, file_range, read,
                                             overlap_range)
                            return 0

            fields = {
                "files": len(matches),
                "reads": len(reads),
                "context": args.require_context or "any",
            }
            fields.update(file_failure_fields(matches))
            fields.update(read_failure_fields(reads))
            return fail("missing-dashboard-read-overlap", **fields)
    except (OSError, RuntimeError, subprocess.CalledProcessError, EOFError) as exc:
        return fail("error", detail=str(exc).replace(" ", "_"))
    finally:
        if tmp_dir:
            shutil.rmtree(tmp_dir)


if __name__ == "__main__":
    sys.exit(main())
