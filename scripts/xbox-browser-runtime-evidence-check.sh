#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-browser-runtime-evidence-check.sh <log-file>

Validates the B5 real browser runtime evidence contract. The log must contain
a BROWSER_RUNTIME_SMOKE summary line with:

  result=pass
  mode=real
  capabilities=yes
  artifacts=yes
  asset_validate=yes
  config_persist=yes
  b3=required

The log must also contain a BROWSER_RUNTIME_TRANSCRIPT line proving compact
transcript evidence for the selected-assets run and the B3 marker source.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

log_path="${1:-}"

if [ -z "${log_path}" ]; then
    printf 'BROWSER_RUNTIME_EVIDENCE result=fail reason=missing-log-arg\n' >&2
    exit 2
fi

if [ ! -f "${log_path}" ]; then
    printf 'BROWSER_RUNTIME_EVIDENCE result=fail reason=missing-log path=%s\n' "${log_path}" >&2
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

runtime_line="$(grep '^BROWSER_RUNTIME_SMOKE ' "${log_path}" | tail -n 1 || true)"
if [ -z "${runtime_line}" ]; then
    printf 'BROWSER_RUNTIME_EVIDENCE result=fail reason=missing-runtime-smoke log=%s\n' "${log_path}" >&2
    exit 1
fi

require_value() {
    local key="$1"
    local expected="$2"
    local actual

    actual="$(value_for "${runtime_line}" "${key}")"
    if [ "${actual}" != "${expected}" ]; then
        printf 'BROWSER_RUNTIME_EVIDENCE result=fail reason=bad-field field=%s expected=%s actual=%s log=%s\n' \
            "${key}" "${expected}" "${actual:-missing}" "${log_path}" >&2
        exit 1
    fi
}

require_value result pass
require_value mode real
require_value capabilities yes
require_value artifacts yes
require_value asset_validate yes
require_value config_persist yes
require_value b3 required

boot_result="$(value_for "${runtime_line}" boot_result)"
if [ -z "${boot_result}" ]; then
    printf 'BROWSER_RUNTIME_EVIDENCE result=fail reason=missing-boot-result log=%s\n' "${log_path}" >&2
    exit 1
fi

transcript_line="$(grep '^BROWSER_RUNTIME_TRANSCRIPT ' "${log_path}" | tail -n 1 || true)"
if [ -z "${transcript_line}" ]; then
    printf 'BROWSER_RUNTIME_EVIDENCE result=fail reason=missing-runtime-transcript log=%s\n' "${log_path}" >&2
    exit 1
fi

require_transcript_value() {
    local key="$1"
    local expected="$2"
    local actual

    actual="$(value_for "${transcript_line}" "${key}")"
    if [ "${actual}" != "${expected}" ]; then
        printf 'BROWSER_RUNTIME_EVIDENCE result=fail reason=bad-transcript-field field=%s expected=%s actual=%s log=%s\n' \
            "${key}" "${expected}" "${actual:-missing}" "${log_path}" >&2
        exit 1
    fi
}

require_transcript_value result pass
require_transcript_value mode real
require_transcript_value run_mode selected-assets
require_transcript_value hdd_asset yes
require_transcript_value capability_sab yes
require_transcript_value artifact_js yes
require_transcript_value artifact_wasm yes
require_transcript_value asset_validate yes
require_transcript_value config_persist yes

b3_marker="$(value_for "${transcript_line}" b3_marker)"
case "${b3_marker}" in
    browser-block|ide-hdd) ;;
    *)
        printf 'BROWSER_RUNTIME_EVIDENCE result=fail reason=bad-transcript-field field=b3_marker expected=browser-block-or-ide-hdd actual=%s log=%s\n' \
            "${b3_marker:-missing}" "${log_path}" >&2
        exit 1
        ;;
esac

printf 'BROWSER_RUNTIME_EVIDENCE result=pass log=%s boot_result=%s\n' \
    "${log_path}" "${boot_result}"
