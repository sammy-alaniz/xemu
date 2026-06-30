#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-dashboard-xbe-read.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

hdd_path="${tmp_dir}/hdd.raw"
pass_log="${tmp_dir}/pass.log"
miss_log="${tmp_dir}/missing-overlap.log"
out_path="${tmp_dir}/out.log"

python3 - <<'PY' "${hdd_path}"
import os
import struct
import sys

sector = 512
cluster_size = 2048
header_size = 4096
fat_size = 4096
data_start = header_size + fat_size
image_size = 4 * 1024 * 1024
path = sys.argv[1]

with open(path, "wb") as fp:
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
    struct.pack_into("<I", entry, 48, 3072)
    fp.seek(data_start)
    fp.write(entry)

    file_start = data_start + cluster_size
    fp.seek(file_start)
    fp.write(b"XBEH")
    fp.write(b"\0" * 3068)
PY

file_lba=$(( (4096 + 4096 + 2048) / 512 ))

cat >"${pass_log}" <<EOF
BOOT_MARK b3 ide=hdd read_index=1 read_lba=${file_lba} nsectors=4 method=dma unit=0 total_sectors=8192
EOF

cat >"${miss_log}" <<'EOF'
BOOT_MARK b3 ide=hdd read_index=1 read_lba=1 nsectors=1 method=dma unit=0 total_sectors=8192
EOF

if ! "${script}" --hdd "${hdd_path}" --log "${pass_log}" \
    --default-context browser-runtime >"${out_path}" 2>&1; then
    printf 'DASHBOARD_XBE_READ_EVIDENCE_SELFTEST case=pass result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q '^BOOT_MARK b6 dashboard=xbe-read context=browser-runtime file=xboxdash.xbe ' "${out_path}"; then
    printf 'DASHBOARD_XBE_READ_EVIDENCE_SELFTEST case=pass result=fail reason=missing-marker\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
printf 'DASHBOARD_XBE_READ_EVIDENCE_SELFTEST case=pass result=pass\n'

if "${script}" --hdd "${hdd_path}" --log "${miss_log}" \
    --default-context browser-runtime >"${out_path}" 2>&1; then
    printf 'DASHBOARD_XBE_READ_EVIDENCE_SELFTEST case=missing-overlap result=fail reason=unexpected-pass\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'reason=missing-dashboard-read-overlap' "${out_path}"; then
    printf 'DASHBOARD_XBE_READ_EVIDENCE_SELFTEST case=missing-overlap result=fail reason=missing-reason\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
for field in start_lba latest_read_lba latest_read_index; do
    if ! grep -q "${field}=" "${out_path}"; then
        printf 'DASHBOARD_XBE_READ_EVIDENCE_SELFTEST case=missing-overlap result=fail reason=missing-field field=%s\n' "${field}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'DASHBOARD_XBE_READ_EVIDENCE_SELFTEST case=missing-overlap result=pass\n'

printf 'DASHBOARD_XBE_READ_EVIDENCE_SELFTEST_RESULT result=pass cases=2\n'
