#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-post-command-irq-state-compare.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-post-command-irq.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

native_log="${tmp_dir}/native.log"
browser_log="${tmp_dir}/browser.log"
out_path="${tmp_dir}/out.log"

cat >"${native_log}" <<'EOF'
BOOT_MARK b6 nv2a=pmc-access context=native-headless seq=47 op=write reg=NV_PMC_INTR_EN_0 addr=0x00000140 size=4 value=0x00000001 pmc_pending_before=0x00000000 pmc_enabled_before=0x00000000 pmc_pending_after=0x00000000 pmc_enabled_after=0x00000001 pfifo_pending=0x00000000 pfifo_enabled=0x01111111 pcrtc_pending=0x00000000 pcrtc_enabled=0x00000001 pgraph_pending=0x00000000 pgraph_enabled=0xffffffff
BOOT_MARK b6 nv2a=irq-source context=native-headless seq=23 source=pgraph op=intr-clear value=0x00100000 pmc_pending_before=0x00001000 pmc_enabled_before=0x00000000 pmc_pending_after=0x00000000 pmc_enabled_after=0x00000000 pcrtc_pending_before=0x00000000 pcrtc_enabled_before=0x00000001 pcrtc_pending_after=0x00000000 pcrtc_enabled_after=0x00000001 pgraph_pending_before=0x00100000 pgraph_enabled_before=0xffffffff pgraph_pending_after=0x00000000 pgraph_enabled_after=0xffffffff
BOOT_MARK b6 pfifo=window context=native-headless seq=375 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318 pmc_pending=0x00000000 pmc_enabled=0x00000001 pgraph_pending=0x00000000 pgraph_enabled=0xffffffff
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless observed_seq=1 observed_tbs=6411 probe=after-idle-transition-sample stream_idle=yes loop_kind=fallthrough start_pc=0x8001b02f next_pc=0x8001b030 nv2a_pmc_pending=0x00000000 nv2a_pmc_enabled=0x00000001 nv2a_pcrtc_pending=0x00000000 nv2a_pcrtc_enabled=0x00000001 nv2a_pgraph_pending=0x00000000 nv2a_pgraph_enabled=0xffffffff start_mem_kind=none start_mem_addr=0x00000000 start_mem_region=none start_mem_value_read=no start_mem_value=0x00000000 next_mem_kind=none next_mem_addr=0x00000000 next_mem_region=none next_mem_value_read=no next_mem_value=0x00000000
EOF

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 nv2a=pmc-access context=browser-runtime seq=410 op=write reg=NV_PMC_INTR_EN_0 addr=0x00000140 size=4 value=0x00000000 pmc_pending_before=0x01000000 pmc_enabled_before=0x00000001 pmc_pending_after=0x01000000 pmc_enabled_after=0x00000000 pfifo_pending=0x00000000 pfifo_enabled=0x01111111 pcrtc_pending=0x00000001 pcrtc_enabled=0x00000001 pgraph_pending=0x00000000 pgraph_enabled=0xffffffff
BOOT_MARK b6 pfifo=window context=browser-runtime seq=381 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318 pmc_pending=0x00000000 pmc_enabled=0x00000000 pgraph_pending=0x00000000 pgraph_enabled=0xffffffff
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=1 observed_tbs=5858 probe=after-idle-transition-sample stream_idle=yes loop_kind=fallthrough start_pc=0x80045ca6 next_pc=0x80045cb0 nv2a_pmc_pending=0x00000000 nv2a_pmc_enabled=0x00000000 nv2a_pcrtc_pending=0x00000000 nv2a_pcrtc_enabled=0x00000001 nv2a_pgraph_pending=0x00000000 nv2a_pgraph_enabled=0xffffffff start_mem_kind=test-rm32-imm32 start_mem_addr=0xfd000100 start_mem_region=mmio-high start_mem_value_read=yes start_mem_value=0x00000000 next_mem_kind=none next_mem_addr=0x00000000 next_mem_region=none next_mem_value_read=no next_mem_value=0x00000000
BOOT_MARK b6 nv2a=irq-source context=browser-runtime seq=143 source=pcrtc op=vblank-raise value=0x00000001 pmc_pending_before=0x00000000 pmc_enabled_before=0x00000000 pmc_pending_after=0x01000000 pmc_enabled_after=0x00000000 pcrtc_pending_before=0x00000000 pcrtc_enabled_before=0x00000001 pcrtc_pending_after=0x00000001 pcrtc_enabled_after=0x00000001 pgraph_pending_before=0x00000000 pgraph_enabled_before=0xffffffff pgraph_pending_after=0x00000000 pgraph_enabled_after=0xffffffff
BOOT_MARK b6 nv2a=pmc-access context=browser-runtime seq=413 op=write reg=NV_PMC_INTR_EN_0 addr=0x00000140 size=4 value=0x00000001 pmc_pending_before=0x01000000 pmc_enabled_before=0x00000000 pmc_pending_after=0x01000000 pmc_enabled_after=0x00000001 pfifo_pending=0x00000000 pfifo_enabled=0x01111111 pcrtc_pending=0x00000001 pcrtc_enabled=0x00000001 pgraph_pending=0x00000000 pgraph_enabled=0xffffffff
BOOT_MARK b6 nv2a=pmc-access context=browser-runtime seq=416 op=write reg=NV_PMC_INTR_EN_0 addr=0x00000140 size=4 value=0x00000000 pmc_pending_before=0x01000000 pmc_enabled_before=0x00000001 pmc_pending_after=0x01000000 pmc_enabled_after=0x00000000 pfifo_pending=0x00000000 pfifo_enabled=0x01111111 pcrtc_pending=0x00000001 pcrtc_enabled=0x00000001 pgraph_pending=0x00000000 pgraph_enabled=0xffffffff
BOOT_MARK b6 nv2a=irq-source context=browser-runtime seq=144 source=pcrtc op=intr-clear value=0x00000001 pmc_pending_before=0x01000000 pmc_enabled_before=0x00000000 pmc_pending_after=0x00000000 pmc_enabled_after=0x00000000 pcrtc_pending_before=0x00000001 pcrtc_enabled_before=0x00000001 pcrtc_pending_after=0x00000000 pcrtc_enabled_after=0x00000001 pgraph_pending_before=0x00000000 pgraph_enabled_before=0xffffffff pgraph_pending_after=0x00000000 pgraph_enabled_after=0xffffffff
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'POST_COMMAND_IRQ_STATE_COMPARE_SELFTEST case=pmc-disabled result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

for pattern in \
    'POST_COMMAND_IRQ_STATE_COMPARE result=pass' \
    'divergence=browser-pmc-disabled-after-idle' \
    'both_stream_idle=yes' \
    'both_after_idle_loop=yes' \
    'same_loop_pmc_enabled=no' \
    'native_loop_pmc_enabled=0x00000001' \
    'browser_loop_pmc_enabled=0x00000000' \
    'browser_loop_start_mem_region=mmio-high' \
    'browser_loop_start_mem_addr=0xfd000100' \
    'browser_pcrtc_vblank_raise_after_idle=1' \
    'browser_pmc_after_idle_enable_writes=1' \
    'browser_pmc_after_idle_disable_writes=1' \
    'browser_latest_after_idle_pmc_disable_pmc_pending_after=0x01000000'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'POST_COMMAND_IRQ_STATE_COMPARE_SELFTEST case=pmc-disabled result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done

printf 'POST_COMMAND_IRQ_STATE_COMPARE_SELFTEST case=pmc-disabled result=pass\n'

if "${script}" --native-log "${tmp_dir}/missing.log" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'POST_COMMAND_IRQ_STATE_COMPARE_SELFTEST case=missing-native result=fail reason=unexpected-pass\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'result=fail' "${out_path}"; then
    printf 'POST_COMMAND_IRQ_STATE_COMPARE_SELFTEST case=missing-native result=fail reason=missing-fail\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

printf 'POST_COMMAND_IRQ_STATE_COMPARE_SELFTEST case=missing-native result=pass\n'
printf 'POST_COMMAND_IRQ_STATE_COMPARE_SELFTEST_RESULT result=pass cases=2\n'
