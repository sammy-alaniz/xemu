#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-native-reference-evidence-check.sh <log-file>

Validates the native reference-frame evidence contract for B6. The log must
contain a line shaped like:

  NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless \
      source=native-framebuffer hash=<hex> width=<n> height=<n> \
      dashboard=xbe-executed ...

This script validates provenance and shape only. It does not capture a native
frame and it does not satisfy B6 by itself.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

log_path="${1:-}"

if [ -z "${log_path}" ]; then
    printf 'NATIVE_REFERENCE_EVIDENCE result=fail reason=missing-log-arg\n' >&2
    exit 2
fi

if [ ! -f "${log_path}" ]; then
    printf 'NATIVE_REFERENCE_EVIDENCE result=fail reason=missing-log path=%s\n' \
        "${log_path}" >&2
    exit 2
fi

value_for() {
    local line="$1"
    local key="$2"
    local token

    for token in ${line}; do
        case "${token}" in
            "${key}="*)
                printf '%s' "${token#*=}"
                return
                ;;
        esac
    done
}

reference_line="$(grep '^NATIVE_DASHBOARD_REFERENCE ' "${log_path}" | tail -n 1 || true)"
if [ -z "${reference_line}" ]; then
    printf 'NATIVE_REFERENCE_EVIDENCE result=fail reason=missing-native-reference log=%s\n' \
        "${log_path}" >&2
    exit 1
fi

result_value="$(value_for "${reference_line}" result)"
context_value="$(value_for "${reference_line}" context)"
source_value="$(value_for "${reference_line}" source)"
hash_value="$(value_for "${reference_line}" hash)"
width_value="$(value_for "${reference_line}" width)"
height_value="$(value_for "${reference_line}" height)"
dashboard_value="$(value_for "${reference_line}" dashboard)"

if [ "${result_value}" != "pass" ]; then
    printf 'NATIVE_REFERENCE_EVIDENCE result=fail reason=reference-not-pass value=%s log=%s\n' \
        "${result_value:-missing}" "${log_path}" >&2
    exit 1
fi

if [ "${context_value}" != "native-headless" ]; then
    printf 'NATIVE_REFERENCE_EVIDENCE result=fail reason=bad-context value=%s log=%s\n' \
        "${context_value:-missing}" "${log_path}" >&2
    exit 1
fi

case "${source_value}" in
    native-framebuffer|native-screenshot) ;;
    *)
        printf 'NATIVE_REFERENCE_EVIDENCE result=fail reason=bad-source value=%s log=%s\n' \
            "${source_value:-missing}" "${log_path}" >&2
        exit 1
        ;;
esac

if ! printf '%s' "${hash_value}" | grep -Eq '^[0-9a-fA-F]{16,128}$'; then
    printf 'NATIVE_REFERENCE_EVIDENCE result=fail reason=bad-hash value=%s log=%s\n' \
        "${hash_value:-missing}" "${log_path}" >&2
    exit 1
fi

if ! printf '%s' "${width_value}" | grep -Eq '^[1-9][0-9]*$'; then
    printf 'NATIVE_REFERENCE_EVIDENCE result=fail reason=bad-width value=%s log=%s\n' \
        "${width_value:-missing}" "${log_path}" >&2
    exit 1
fi

if ! printf '%s' "${height_value}" | grep -Eq '^[1-9][0-9]*$'; then
    printf 'NATIVE_REFERENCE_EVIDENCE result=fail reason=bad-height value=%s log=%s\n' \
        "${height_value:-missing}" "${log_path}" >&2
    exit 1
fi

if [ "${dashboard_value}" != "xbe-executed" ]; then
    printf 'NATIVE_REFERENCE_EVIDENCE result=fail reason=bad-dashboard value=%s log=%s\n' \
        "${dashboard_value:-missing}" "${log_path}" >&2
    exit 1
fi

printf 'NATIVE_REFERENCE_EVIDENCE result=pass log=%s hash=%s source=%s width=%s height=%s\n' \
    "${log_path}" "${hash_value}" "${source_value}" "${width_value}" \
    "${height_value}"
