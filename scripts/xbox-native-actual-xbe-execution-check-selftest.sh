#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-native-xbe-exec-check.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

write_pass_log() {
    cat >"${tmpdir}/pass.log" <<'EOF'
BOOT_MARK b6 dashboard=xbe-entry-probe context=native-headless status=ready guest_entry=0x00017d60 image_pc=0x00017d60 entry_code_read=yes phys_match=yes
BOOT_MARK b6 dashboard=xbe-executed-detector-proof context=native-headless result=pass guest_pc=0x00017d60 eip=0x80014703 phys_match=yes section_flags=0x00000006
BOOT_MARK b6 dashboard=xbe-executed context=native-headless guest_pc=0x00017d60 phys_match=yes section_flags=0x00000006
EOF
}

write_detector_only_log() {
    cat >"${tmpdir}/detector-only.log" <<'EOF'
BOOT_MARK b6 dashboard=xbe-entry-probe context=native-headless status=ready guest_entry=0x00017d60 image_pc=0x00017d60 entry_code_read=yes phys_match=yes
BOOT_MARK b6 dashboard=xbe-executed-detector-proof context=native-headless result=pass guest_pc=0x00017d60 eip=0x80014703 phys_match=yes section_flags=0x00000006
BOOT_MARK b6 dashboard=xbe-exec-probe context=native-headless guest_pc=0x80014703 image_pc=0x00014703 phys_match=no address_mode=high-alias-mismatch
BOOT_MARK b6 dashboard=xbe-exec-edge context=native-headless start_pc=0x80014703 next_pc=0x8001470a start_phys_match=no next_phys_match=no next_branch_phys_match=unknown
EOF
}

write_missing_detector_log() {
    cat >"${tmpdir}/missing-detector.log" <<'EOF'
BOOT_MARK b6 dashboard=xbe-entry-probe context=native-headless status=ready guest_entry=0x00017d60 image_pc=0x00017d60 entry_code_read=yes phys_match=yes
BOOT_MARK b6 dashboard=xbe-exec-probe context=native-headless guest_pc=0x80014703 image_pc=0x00014703 phys_match=no address_mode=high-alias-mismatch
EOF
}

assert_output() {
    local name="$1"
    local log="$2"
    local expected_status="$3"
    local pattern="$4"
    local output
    local status

    set +e
    output="$("${repo_root}/scripts/xbox-native-actual-xbe-execution-check.py" "${log}" 2>&1)"
    status=$?
    set -e

    if [ "${status}" -ne "${expected_status}" ]; then
        printf 'NATIVE_ACTUAL_XBE_EXECUTION_SELFTEST result=fail case=%s reason=bad-status expected=%s actual=%s output=%s\n' \
            "${name}" "${expected_status}" "${status}" "${output}" >&2
        exit 1
    fi

    if ! printf '%s' "${output}" | grep -Eq "${pattern}"; then
        printf 'NATIVE_ACTUAL_XBE_EXECUTION_SELFTEST result=fail case=%s reason=bad-output pattern=%s output=%s\n' \
            "${name}" "${pattern}" "${output}" >&2
        exit 1
    fi
}

write_pass_log
write_detector_only_log
write_missing_detector_log

assert_output pass "${tmpdir}/pass.log" 0 \
    'result=pass .*reason=strict-dashboard-executed .*strict_xbe_executed=yes .*direct_entry_pc=yes'
assert_output detector-only "${tmpdir}/detector-only.log" 1 \
    'result=fail .*reason=no-strict-dashboard-executed-marker .*detector_proof=pass .*exec_probe_phys_match_yes=0 .*direct_entry_pc=no'
assert_output missing-detector "${tmpdir}/missing-detector.log" 1 \
    'result=fail .*reason=missing-detector-proof .*detector_proof=missing'

printf 'NATIVE_ACTUAL_XBE_EXECUTION_SELFTEST result=pass cases=3\n'
