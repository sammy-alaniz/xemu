#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-combine-dashboard-xbe-read-evidence.sh --hdd <hdd> --log <boot.log> --out <combined.log> [--require-context <context>]

Copies a boot/runtime log and appends auditable dashboard XBE FATX/IDE read
evidence from scripts/xbox-dashboard-xbe-read-evidence.py. This is intended for
B6 diagnostics where the runtime log already contains browser execution/display
markers, while the HDD parser supplies the exact on-disk xboxdash.xbe file size
and read overlap.

The script does not copy private HDD contents. It appends only the existing
non-content metadata emitted by the read evidence helper.
EOF
}

hdd_path=""
log_path=""
out_path=""
require_context=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --hdd)
            hdd_path="${2:-}"
            shift 2
            ;;
        --log)
            log_path="${2:-}"
            shift 2
            ;;
        --out)
            out_path="${2:-}"
            shift 2
            ;;
        --require-context)
            require_context="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'COMBINE_DASHBOARD_XBE_READ_EVIDENCE result=fail reason=bad-arg value=%s\n' "$1" >&2
            exit 2
            ;;
    esac
done

if [ -z "${hdd_path}" ] || [ -z "${log_path}" ] || [ -z "${out_path}" ]; then
    usage >&2
    printf 'COMBINE_DASHBOARD_XBE_READ_EVIDENCE result=fail reason=missing-required-arg\n' >&2
    exit 2
fi

if [ ! -f "${hdd_path}" ]; then
    printf 'COMBINE_DASHBOARD_XBE_READ_EVIDENCE result=fail reason=missing-hdd path=%s\n' "${hdd_path}" >&2
    exit 2
fi

if [ ! -f "${log_path}" ]; then
    printf 'COMBINE_DASHBOARD_XBE_READ_EVIDENCE result=fail reason=missing-log path=%s\n' "${log_path}" >&2
    exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
out_dir="$(dirname "${out_path}")"
tmp_out="$(mktemp "${TMPDIR:-/tmp}/xemu-xbe-read-combined.XXXXXX")"
tmp_read="$(mktemp "${TMPDIR:-/tmp}/xemu-xbe-read-evidence.XXXXXX")"
trap 'rm -f "${tmp_out}" "${tmp_read}"' EXIT

mkdir -p "${out_dir}"

read_cmd=(
    "${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py"
    --hdd "${hdd_path}"
    --log "${log_path}"
)
if [ -n "${require_context}" ]; then
    read_cmd+=(--require-context "${require_context}")
fi

if ! "${read_cmd[@]}" >"${tmp_read}" 2>&1; then
    cat "${tmp_read}" >&2
    printf 'COMBINE_DASHBOARD_XBE_READ_EVIDENCE result=fail reason=read-evidence-failed log=%s out=%s\n' \
        "${log_path}" "${out_path}" >&2
    exit 1
fi

cp "${log_path}" "${tmp_out}"
printf '\n' >>"${tmp_out}"
cat "${tmp_read}" >>"${tmp_out}"
mv "${tmp_out}" "${out_path}"

printf 'COMBINE_DASHBOARD_XBE_READ_EVIDENCE result=pass log=%s out=%s context=%s\n' \
    "${log_path}" "${out_path}" "${require_context:-any}"
