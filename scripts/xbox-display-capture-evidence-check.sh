#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-display-capture-evidence-check.sh <log-file>

Validates the B4 display evidence contract without requiring private assets.
The log must contain both:

  BOOT_MARK b4 ...
  BROWSER_DISPLAY_CAPTURE result=pass nonempty=yes hash=<hex> source=<name>

This script does not generate display evidence. It only prevents weak or
ambiguous B4 markers from satisfying the completion gate.

Controls:
  XEMU_DISPLAY_EVIDENCE_ALLOW_SYNTHETIC  Accept source=synthetic-framebuffer
                                         when set to 1. Default: reject it.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

log_path="${1:-}"

if [ -z "${log_path}" ]; then
    printf 'DISPLAY_CAPTURE_EVIDENCE result=fail reason=missing-log-arg\n' >&2
    exit 2
fi

if [ ! -f "${log_path}" ]; then
    printf 'DISPLAY_CAPTURE_EVIDENCE result=fail reason=missing-log path=%s\n' "${log_path}" >&2
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

if ! grep -q '^BOOT_MARK b4' "${log_path}"; then
    printf 'DISPLAY_CAPTURE_EVIDENCE result=fail reason=missing-b4-marker log=%s\n' "${log_path}" >&2
    exit 1
fi

capture_line="$(grep '^BROWSER_DISPLAY_CAPTURE ' "${log_path}" | tail -n 1 || true)"
if [ -z "${capture_line}" ]; then
    printf 'DISPLAY_CAPTURE_EVIDENCE result=fail reason=missing-display-capture log=%s\n' "${log_path}" >&2
    exit 1
fi

capture_result="$(value_for "${capture_line}" result)"
nonempty="$(value_for "${capture_line}" nonempty)"
hash_value="$(value_for "${capture_line}" hash)"
source_value="$(value_for "${capture_line}" source)"
allow_synthetic="${XEMU_DISPLAY_EVIDENCE_ALLOW_SYNTHETIC:-0}"

if [ "${capture_result}" != "pass" ]; then
    printf 'DISPLAY_CAPTURE_EVIDENCE result=fail reason=capture-not-pass value=%s log=%s\n' \
        "${capture_result:-missing}" "${log_path}" >&2
    exit 1
fi

if [ "${nonempty}" != "yes" ]; then
    printf 'DISPLAY_CAPTURE_EVIDENCE result=fail reason=capture-empty value=%s log=%s\n' \
        "${nonempty:-missing}" "${log_path}" >&2
    exit 1
fi

if ! printf '%s' "${hash_value}" | grep -Eq '^[0-9a-fA-F]{16,128}$'; then
    printf 'DISPLAY_CAPTURE_EVIDENCE result=fail reason=bad-hash value=%s log=%s\n' \
        "${hash_value:-missing}" "${log_path}" >&2
    exit 1
fi

case "${source_value}" in
    browser-canvas|browser-framebuffer|native-reference) ;;
    synthetic-framebuffer)
        if [ "${allow_synthetic}" != "1" ]; then
            printf 'DISPLAY_CAPTURE_EVIDENCE result=fail reason=synthetic-source-not-real value=%s log=%s\n' \
                "${source_value}" "${log_path}" >&2
            exit 1
        fi
        ;;
    *)
        printf 'DISPLAY_CAPTURE_EVIDENCE result=fail reason=bad-source value=%s log=%s\n' \
            "${source_value:-missing}" "${log_path}" >&2
        exit 1
        ;;
esac

printf 'DISPLAY_CAPTURE_EVIDENCE result=pass log=%s hash=%s source=%s\n' \
    "${log_path}" "${hash_value}" "${source_value}"
