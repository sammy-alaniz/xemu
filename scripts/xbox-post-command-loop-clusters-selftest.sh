#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-post-command-loop-clusters.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-post-command-loops.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

native_log="${tmp_dir}/native.log"
browser_log="${tmp_dir}/browser.log"
out_path="${tmp_dir}/out.log"

cat >"${native_log}" <<'EOF'
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless observed_seq=1 observed_tbs=1 loop_kind=forward start_pc=0x80014386 next_pc=0x800146ea tb_size=1 tb_exit=3 cpu_mode=protected32 cpl=0 cs=0x0008 nv2a_wait_source=pgraph nv2a_wait_op=intr-enable start_code_hash=0x64b934187aacd766 start_opcode=0xc3 next_code_hash=0x427f6f948322d9ed next_opcode=0x8a next_mem_region=none next_mem_value_read=no
BOOT_MARK b6 pfifo=window context=native-headless seq=375 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless observed_seq=1 observed_tbs=100000 loop_kind=backward start_pc=0x8001b030 next_pc=0x8001b02f tb_size=7 tb_exit=0 cpu_mode=protected32 cpl=0 cs=0x0008 nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty start_code_hash=0x623287e7c989db8f start_opcode=0x90 next_code_hash=0x7018e4c793b74783 next_opcode=0x90 next_mem_region=none next_mem_value_read=no
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless observed_seq=2 observed_tbs=200000 stream_idle=yes loop_kind=backward start_pc=0x8001b030 next_pc=0x8001b02f tb_size=7 tb_exit=0 cpu_mode=protected32 cpl=0 cs=0x0008 esp=0xd0025bf8 eflags=0x00000206 interrupts_enabled=yes irq_inhibited=no cpu_interrupt_request=0x00000002 pending_interrupt=yes cpu_exit_request=yes nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty start_code_hash=0x623287e7c989db8f start_opcode=0x90 next_code_hash=0x7018e4c793b74783 next_opcode=0x90 next_mem_region=none next_mem_value_read=no
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless observed_seq=3 observed_tbs=300000 loop_kind=fallthrough start_pc=0x8001b02f next_pc=0x8001b030 tb_size=1 tb_exit=0 cpu_mode=protected32 cpl=0 cs=0x0008 nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty start_code_hash=0x7018e4c793b74783 start_opcode=0x90 next_code_hash=0x623287e7c989db8f next_opcode=0x90 next_mem_region=none next_mem_value_read=no
EOF

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=1 observed_tbs=1 loop_kind=backward start_pc=0x8003adcc next_pc=0x8002430e tb_size=53 tb_exit=0 cpu_mode=protected32 cpl=0 cs=0x0008 nv2a_wait_source=pcrtc nv2a_wait_op=vblank-raise start_code_hash=0x0f69ede7ed360828 start_opcode=0x54 next_code_hash=0xd9695668fc6d0f16 next_opcode=0xc7 next_mem_region=none next_mem_value_read=no
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=2 observed_tbs=2 loop_kind=forward start_pc=0x80014fb4 next_pc=0x8001aea5 tb_size=1 tb_exit=0 cpu_mode=protected32 cpl=0 cs=0x0008 nv2a_wait_source=pcrtc nv2a_wait_op=vblank-raise start_code_hash=0x22e9318314915db9 start_opcode=0xc3 next_code_hash=0xd4c7e741ee84ea6c next_opcode=0x8b next_mem_region=kernel-ram-alias next_mem_value_read=yes
BOOT_MARK b6 pfifo=window context=browser-runtime seq=381 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'POST_COMMAND_LOOP_CLUSTERS_SELFTEST case=wait-source result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

for pattern in \
    'POST_COMMAND_LOOP_CLUSTERS result=pass' \
    'divergence=wait-source-mismatch' \
    'after_idle_divergence=browser-no-after-idle-loop-samples' \
    'after_idle_cpu_interrupt_divergence=native-only-after-idle-cpu-interrupt' \
    'shared_edges=0' \
    'same_top_edge=no' \
    'after_idle_shared_edges=0' \
    'after_idle_same_top_edge=no' \
    'native_stream_idle_seen=yes' \
    'native_stream_idle_count=1' \
    'native_samples=4' \
    'native_unique_edges=3' \
    'native_repeating_edges=1' \
    'native_top_edge_count=2' \
    'native_dominant_wait_source=pfifo-window' \
    'native_after_idle_samples=3' \
    'native_after_idle_unique_edges=2' \
    'native_after_idle_repeating_edges=1' \
    'native_after_idle_dominant_wait_source=pfifo-window' \
    'native_after_idle_cpu_interrupt_nonzero=1' \
    'native_after_idle_first_cpu_interrupt_request=0x00000002' \
    'native_after_idle_first_cpu_interrupt_start=0x8001b030' \
    'native_after_idle_pending_interrupt_yes=1' \
    'native_after_idle_cpu_exit_request_yes=1' \
    'browser_stream_idle_seen=yes' \
    'browser_stream_idle_count=1' \
    'browser_samples=2' \
    'browser_unique_edges=2' \
    'browser_dominant_wait_source=pcrtc' \
    'browser_after_idle_samples=0' \
    'browser_after_idle_cpu_interrupt_nonzero=0' \
    'browser_latest_next_mem_region=kernel-ram-alias'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'POST_COMMAND_LOOP_CLUSTERS_SELFTEST case=wait-source result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done

printf 'POST_COMMAND_LOOP_CLUSTERS_SELFTEST case=wait-source result=pass\n'

if "${script}" --native-log "${tmp_dir}/missing.log" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'POST_COMMAND_LOOP_CLUSTERS_SELFTEST case=missing-native result=fail reason=unexpected-pass\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'result=fail' "${out_path}"; then
    printf 'POST_COMMAND_LOOP_CLUSTERS_SELFTEST case=missing-native result=fail reason=missing-fail\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

printf 'POST_COMMAND_LOOP_CLUSTERS_SELFTEST case=missing-native result=pass\n'
printf 'POST_COMMAND_LOOP_CLUSTERS_SELFTEST_RESULT result=pass cases=2\n'
