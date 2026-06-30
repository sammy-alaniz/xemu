#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-dashboard-xbe-hash-evidence.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-dashboard-xbe-hash.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

hdd_path="${tmp_dir}/hdd.raw"
pass_log="${tmp_dir}/pass.log"
fail_log="${tmp_dir}/guest-disk-match.log"
exec_fail_log="${tmp_dir}/exec-disk-match.log"
target_fail_log="${tmp_dir}/target-disk-match.log"
out_path="${tmp_dir}/out.log"

python3 - <<'PY' "${hdd_path}" "${pass_log}" "${fail_log}" "${exec_fail_log}" "${target_fail_log}"
import struct
import sys

sector = 512
cluster_size = 2048
header_size = 4096
fat_size = 4096
data_start = header_size + fat_size
image_size = 4 * 1024 * 1024
file_size = 4096
file_offset = 0x100
image_base = 0x10000
image_pc = image_base + file_offset
hdd_path, pass_log, fail_log, exec_fail_log, target_fail_log = sys.argv[1:6]


def fnv1a64(data):
    value = 1469598103934665603
    for item in data:
        value ^= item
        value = (value * 1099511628211) & ((1 << 64) - 1)
    return value


file_bytes = bytearray(file_size)
for index in range(file_size):
    file_bytes[index] = (index * 17 + 3) & 0xff
disk_hash = fnv1a64(file_bytes[file_offset:file_offset + 16])
other_hash = fnv1a64(b"not-dashboard-16")

with open(hdd_path, "wb") as fp:
    fp.truncate(image_size)
    fp.seek(0)
    fp.write(b"FATX")
    fp.write(struct.pack("<I", 0x12345678))
    fp.write(struct.pack("<I", cluster_size // sector))
    fp.write(struct.pack("<I", 1))

    fat = bytearray(fat_size)
    struct.pack_into("<H", fat, 1 * 2, 0xFFFF)
    struct.pack_into("<H", fat, 2 * 2, 3)
    struct.pack_into("<H", fat, 3 * 2, 0xFFF8)
    fp.seek(header_size)
    fp.write(fat)

    entry = bytearray(64)
    name = b"xboxdash.xbe"
    entry[0] = len(name)
    entry[1] = 0
    entry[2:2 + len(name)] = name
    entry[2 + len(name):44] = b"\xff" * (42 - len(name))
    struct.pack_into("<I", entry, 44, 2)
    struct.pack_into("<I", entry, 48, file_size)
    fp.seek(data_start)
    fp.write(entry)

    fp.seek(data_start + cluster_size)
    fp.write(file_bytes[:cluster_size])
    fp.seek(data_start + 2 * cluster_size)
    fp.write(file_bytes[cluster_size:])

common = (
    "context=browser-runtime observed_seq=1 alias_seq=1 entry_ready=yes "
    f"guest_pc=0x80010100 image_pc=0x{image_pc:08x} tb_size=1 "
    f"image_base=0x{image_base:08x} image_size={file_size} "
    "relation=above distance=1 address_mode=high-alias-mismatch "
    "guest_phys_mapped=yes guest_phys=0x00010100 "
    "image_phys_mapped=yes image_phys=0x000c0100 phys_match=no "
    "guest_code_read=yes image_code_read=yes "
    "cpu_known=yes cpu_mode=protected32 cpl=0 eip=0x80010100 "
    "cs=0x0008 source=tcg-tb-post"
)

with open(pass_log, "w", encoding="utf-8") as fp:
    fp.write(
        "BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime "
        "status=ready guest_entry=0x00010100 image_pc=0x00010100 "
        "entry_offset=0x00000100 image_base=0x00010000 "
        f"image_size={file_size} entry_code_read=yes "
        f"entry_code_hash=0x{disk_hash:016x}\n"
    )
    fp.write(
        "BOOT_MARK b6 dashboard=xbe-alias-compare "
        f"{common} guest_code_hash=0x{other_hash:016x} "
        f"image_code_hash=0x{disk_hash:016x} code_hash_match=no\n"
    )
    fp.write(
        "BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime "
        f"guest_addr=0x{image_base:08x} image_size={file_size} "
        "source=virtual-header\n"
    )
    fp.write(
        "BOOT_MARK b6 dashboard=xbe-exec-transition "
        "context=browser-runtime observed_seq=1 observed_tbs=1 "
        f"next_image_pc=0x{image_pc:08x} next_code_read=yes "
        f"next_code_hash=0x{other_hash:016x}\n"
    )
    fp.write(
        "BOOT_MARK b6 dashboard=xbe-entry-target-probe "
        "context=browser-runtime observed_seq=1 observed_tbs=1 "
        f"image_base=0x{image_base:08x} branch_target=0x80010100 "
        f"target_image_pc=0x{image_pc:08x} "
        "target_code_read=yes "
        f"target_code_hash=0x{other_hash:016x} "
        "target_image_code_read=yes "
        f"target_image_code_hash=0x{disk_hash:016x}\n"
    )

with open(fail_log, "w", encoding="utf-8") as fp:
    fp.write(
        "BOOT_MARK b6 dashboard=xbe-alias-compare "
        f"{common} guest_code_hash=0x{disk_hash:016x} "
        f"image_code_hash=0x{other_hash:016x} code_hash_match=no\n"
    )

with open(exec_fail_log, "w", encoding="utf-8") as fp:
    fp.write(
        "BOOT_MARK b6 dashboard=xbe-alias-compare "
        f"{common} guest_code_hash=0x{other_hash:016x} "
        f"image_code_hash=0x{disk_hash:016x} code_hash_match=no\n"
    )
    fp.write(
        "BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime "
        f"guest_addr=0x{image_base:08x} image_size={file_size} "
        "source=virtual-header\n"
    )
    fp.write(
        "BOOT_MARK b6 dashboard=xbe-exec-edge "
        "context=browser-runtime observed_seq=1 observed_tbs=1 "
        f"next_image_pc=0x{image_pc:08x} next_code_read=yes "
        f"next_code_hash=0x{disk_hash:016x}\n"
    )

with open(target_fail_log, "w", encoding="utf-8") as fp:
    fp.write(
        "BOOT_MARK b6 dashboard=xbe-alias-compare "
        f"{common} guest_code_hash=0x{other_hash:016x} "
        f"image_code_hash=0x{disk_hash:016x} code_hash_match=no\n"
    )
    fp.write(
        "BOOT_MARK b6 dashboard=xbe-entry-target-probe "
        "context=browser-runtime observed_seq=1 observed_tbs=1 "
        f"image_base=0x{image_base:08x} branch_target=0x80010100 "
        f"target_image_pc=0x{image_pc:08x} "
        "target_code_read=yes "
        f"target_code_hash=0x{disk_hash:016x} "
        "target_image_code_read=yes "
        f"target_image_code_hash=0x{disk_hash:016x}\n"
    )
PY

if ! "${script}" --hdd "${hdd_path}" --log "${pass_log}" \
    --require-context browser-runtime >"${out_path}" 2>&1; then
    printf 'DASHBOARD_XBE_HASH_EVIDENCE_SELFTEST case=pass result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
for pattern in \
    'DASHBOARD_XBE_HASH_EVIDENCE result=pass' \
    'guest_disk_hash_match=0' \
    'guest_image_hash_match=0' \
    'image_disk_hash_match=1' \
    'entry_disk_hash_match=yes' \
    'exec_disk_hash_match=0' \
    'exec_comparable=1' \
    'target_disk_hash_match=0' \
    'target_image_disk_hash_match=1' \
    'target_comparable=1'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'DASHBOARD_XBE_HASH_EVIDENCE_SELFTEST case=pass result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'DASHBOARD_XBE_HASH_EVIDENCE_SELFTEST case=pass result=pass\n'

if "${script}" --hdd "${hdd_path}" --log "${fail_log}" \
    --require-context browser-runtime >"${out_path}" 2>&1; then
    printf 'DASHBOARD_XBE_HASH_EVIDENCE_SELFTEST case=guest-disk-match result=fail reason=unexpected-pass\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'reason=guest-disk-hash-match' "${out_path}"; then
    printf 'DASHBOARD_XBE_HASH_EVIDENCE_SELFTEST case=guest-disk-match result=fail reason=missing-reason\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
printf 'DASHBOARD_XBE_HASH_EVIDENCE_SELFTEST case=guest-disk-match result=pass\n'

if "${script}" --hdd "${hdd_path}" --log "${exec_fail_log}" \
    --require-context browser-runtime >"${out_path}" 2>&1; then
    printf 'DASHBOARD_XBE_HASH_EVIDENCE_SELFTEST case=exec-disk-match result=fail reason=unexpected-pass\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'reason=exec-disk-hash-match' "${out_path}"; then
    printf 'DASHBOARD_XBE_HASH_EVIDENCE_SELFTEST case=exec-disk-match result=fail reason=missing-reason\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
printf 'DASHBOARD_XBE_HASH_EVIDENCE_SELFTEST case=exec-disk-match result=pass\n'

if "${script}" --hdd "${hdd_path}" --log "${target_fail_log}" \
    --require-context browser-runtime >"${out_path}" 2>&1; then
    printf 'DASHBOARD_XBE_HASH_EVIDENCE_SELFTEST case=target-disk-match result=fail reason=unexpected-pass\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'reason=target-disk-hash-match' "${out_path}"; then
    printf 'DASHBOARD_XBE_HASH_EVIDENCE_SELFTEST case=target-disk-match result=fail reason=missing-reason\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
printf 'DASHBOARD_XBE_HASH_EVIDENCE_SELFTEST case=target-disk-match result=pass\n'

printf 'DASHBOARD_XBE_HASH_EVIDENCE_SELFTEST_RESULT result=pass cases=4\n'
