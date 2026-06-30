#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-post-command-handoff-compare.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-post-command-handoff.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

native_log="${tmp_dir}/native.log"
browser_log="${tmp_dir}/browser.log"
out_path="${tmp_dir}/out.log"

cat >"${native_log}" <<'EOF'
BOOT_MARK b6 dashboard=xbe-loaded context=native-headless guest_addr=0x00010000 image_size=175080 headers_size=2932 entry=0x00017d60 source=virtual-header
BOOT_MARK b6 dashboard=xbe-entry-probe context=native-headless status=ready guest_entry=0x00017d60 entry_code_read=yes phys_match=yes
BOOT_MARK b6 pfifo=window context=native-headless seq=379 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 dashboard=xbe-exec-probe context=native-headless observed_seq=32 observed_tbs=2400000 guest_pc=0x8001b02f image_pc=0x0001b02f tb_size=1 relation=above address_mode=high-alias-mismatch phys_match=no cpu_mode=protected32 cpl=0 eip=0x8001b02f cs=0x0008 pc_code_hash=0x7018e4c793b74783 pc_opcode=0x90
BOOT_MARK b6 dashboard=xbe-exec-transition context=native-headless observed_seq=32 observed_tbs=2400000 start_pc=0x8001b030 next_pc=0x8001b02f next_address_mode=high-alias-mismatch next_phys_match=no next_code_hash=0x7018e4c793b74783 next_branch_target_known=yes next_branch_target=0x8001ae75 next_branch_address_mode=high-alias-mismatch next_branch_phys_match=no
BOOT_MARK b6 dashboard=xbe-entry-target-probe context=native-headless observed_seq=1 observed_tbs=32 branch_target=0x8001ae75 target_address_mode=high-alias-mismatch target_phys_match=no target_status=near-phys-mismatch target_code_read=yes target_code_hash=0x1111111111111111 target_image_code_read=yes target_image_code_hash=0x2222222222222222 target_code_hash_match=no
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless observed_seq=16 observed_tbs=800000 loop_kind=fallthrough start_pc=0x8001b02f next_pc=0x8001b030 cpu_mode=protected32 cpl=0 cs=0x0008 nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty start_code_hash=0x7018e4c793b74783 start_opcode=0x90 next_code_hash=0x623287e7c989db8f next_opcode=0x90 next_mem_region=none next_mem_value_read=no
EOF

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime guest_addr=0x00010000 image_size=175080 headers_size=2932 entry=0x00017d60 source=virtual-header
BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime status=ready guest_entry=0x00017d60 entry_code_read=yes phys_match=yes
BOOT_MARK b6 pfifo=window context=browser-runtime seq=381 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 dashboard=xbe-exec-probe context=browser-runtime observed_seq=10 observed_tbs=200000 guest_pc=0x80060ffe image_pc=0x80060ffe tb_size=3 relation=above address_mode=none phys_match=not-applicable cpu_mode=protected32 cpl=0 eip=0x80060ffe cs=0x0008 pc_code_hash=0x24e38a652455b84d pc_opcode=0x0f branch_target_known=yes branch_target=0x800241fe branch_address_mode=high-alias-mismatch branch_phys_match=no
BOOT_MARK b6 dashboard=xbe-exec-transition context=browser-runtime observed_seq=10 observed_tbs=200000 start_pc=0x8004cdb8 next_pc=0x80014fb4 next_address_mode=high-alias-mismatch next_phys_match=no next_code_hash=0x22e9318314915db9
BOOT_MARK b6 dashboard=xbe-entry-target-probe context=browser-runtime observed_seq=1 observed_tbs=10 branch_target=0x800241fe target_address_mode=high-alias-mismatch target_phys_match=no target_status=near-phys-mismatch target_code_read=yes target_code_hash=0x3333333333333333 target_image_code_read=yes target_image_code_hash=0x4444444444444444 target_code_hash_match=no
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=8 observed_tbs=8 loop_kind=forward start_pc=0x80014fb4 next_pc=0x8001aea5 cpu_mode=protected32 cpl=0 cs=0x0008 nv2a_wait_source=pcrtc nv2a_wait_op=vblank-raise start_code_hash=0x22e9318314915db9 start_opcode=0xc3 next_code_hash=0xd4c7e741ee84ea6c next_opcode=0x8b next_mem_region=kernel-ram-alias next_mem_value_read=yes
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'POST_COMMAND_HANDOFF_COMPARE_SELFTEST case=post-command-loop result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

for pattern in \
    'POST_COMMAND_HANDOFF_COMPARE result=pass' \
    'divergence=post-command-loop-mismatch' \
    'handoff_blocker=both-high-alias-phys-mismatch' \
    'both_entry_ready=yes' \
    'both_stream_idle=yes' \
    'any_handoff_candidate=no' \
    'native_latest_exec_mode=high-alias-mismatch' \
    'native_latest_exec_phys_match=no' \
    'browser_latest_transition_next_mode=high-alias-mismatch' \
    'browser_branch_high_alias_mismatch=1' \
    'browser_entry_target_near_phys_mismatch=1' \
    'browser_latest_entry_target=0x800241fe' \
    'browser_latest_entry_target_code_read=yes' \
    'browser_latest_entry_target_hash=0x3333333333333333' \
    'browser_latest_entry_target_image_code_read=yes' \
    'browser_latest_entry_target_image_hash=0x4444444444444444' \
    'browser_latest_entry_target_hash_match=no' \
    'browser_latest_loop_wait_source=pcrtc'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'POST_COMMAND_HANDOFF_COMPARE_SELFTEST case=post-command-loop result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done

printf 'POST_COMMAND_HANDOFF_COMPARE_SELFTEST case=post-command-loop result=pass\n'

cat >>"${browser_log}" <<'EOF'
BOOT_MARK b6 dashboard=xbe-exec-probe context=browser-runtime observed_seq=11 observed_tbs=210000 guest_pc=0x00017d60 image_pc=0x00017d60 tb_size=8 relation=overlap address_mode=direct phys_match=yes cpu_mode=protected32 cpl=0 eip=0x00017d60 cs=0x0008 pc_code_hash=0x7cbb4e8a328f1553 pc_opcode=0x55
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'POST_COMMAND_HANDOFF_COMPARE_SELFTEST case=handoff-candidate result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

for pattern in \
    'POST_COMMAND_HANDOFF_COMPARE result=pass' \
    'divergence=handoff-candidate-without-executed-marker' \
    'handoff_blocker=browser-handoff-candidate-without-executed-marker' \
    'any_handoff_candidate=yes' \
    'browser_exec_phys_match_yes=1' \
    'browser_latest_exec_pc=0x00017d60' \
    'browser_latest_exec_phys_match=yes'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'POST_COMMAND_HANDOFF_COMPARE_SELFTEST case=handoff-candidate result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done

printf 'POST_COMMAND_HANDOFF_COMPARE_SELFTEST case=handoff-candidate result=pass\n'

if "${script}" --native-log "${tmp_dir}/missing.log" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'POST_COMMAND_HANDOFF_COMPARE_SELFTEST case=missing-native result=fail reason=unexpected-pass\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'result=fail' "${out_path}"; then
    printf 'POST_COMMAND_HANDOFF_COMPARE_SELFTEST case=missing-native result=fail reason=missing-fail\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

printf 'POST_COMMAND_HANDOFF_COMPARE_SELFTEST case=missing-native result=pass\n'
printf 'POST_COMMAND_HANDOFF_COMPARE_SELFTEST_RESULT result=pass cases=3\n'
