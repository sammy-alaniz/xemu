#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-pcrtc-vblank.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

native_log="${tmp_dir}/native.log"
browser_log="${tmp_dir}/browser.log"

cat >"${native_log}" <<'EOF'
BOOT_MARK b6 nv2a=irq-source context=native-headless seq=1 source=pcrtc op=intr-enable value=0x00000000 pmc_pending_before=0x00000000 pmc_enabled_before=0x00000000 pmc_pending_after=0x00000000 pmc_enabled_after=0x00000000 pcrtc_pending_before=0x00000000 pcrtc_enabled_before=0x00000000 pcrtc_pending_after=0x00000000 pcrtc_enabled_after=0x00000000 pgraph_pending_before=0x00000000 pgraph_enabled_before=0x00000000 pgraph_pending_after=0x00000000 pgraph_enabled_after=0x00000000
BOOT_MARK b6 dashboard=xbe-loaded context=native-headless guest_addr=0x00010000 image_size=4096 headers_size=512 entry=0x00010100 title_id=0xffff0002 source=virtual-header phys_addr=0x000e0000
BOOT_MARK b6 dashboard=xbe-entry-probe context=native-headless status=ready guest_entry=0x00010100 image_pc=0x00010100 entry_offset=0x00000100 image_base=0x00010000 image_size=4096 relation=overlap distance=0 address_mode=direct entry_phys_mapped=yes entry_phys=0x00020100 image_phys_mapped=yes image_phys=0x00020100 phys_match=yes entry_code_read=yes entry_code_hash=0x0123456789abcdef entry_opcode=0x55 source=virtual-header
BOOT_MARK b6 nv2a=pmc-access context=native-headless seq=1 op=write reg=NV_PMC_INTR_EN_0 addr=0x00000140 size=4 value=0x00000000 pmc_pending_before=0x00001000 pmc_enabled_before=0x00000001 pmc_pending_after=0x00001000 pmc_enabled_after=0x00000000 pfifo_pending=0x00000000 pfifo_enabled=0x01111111 pcrtc_pending=0x00000000 pcrtc_enabled=0x00000001 pgraph_pending=0x00100000 pgraph_enabled=0xffffffff cpu_known=yes eip=0x80045ba1
BOOT_MARK b6 nv2a=pmc-access context=native-headless seq=2 op=write reg=NV_PMC_INTR_EN_0 addr=0x00000140 size=4 value=0x00000001 pmc_pending_before=0x00000000 pmc_enabled_before=0x00000000 pmc_pending_after=0x00000000 pmc_enabled_after=0x00000001 pfifo_pending=0x00000000 pfifo_enabled=0x01111111 pcrtc_pending=0x00000000 pcrtc_enabled=0x00000001 pgraph_pending=0x00000000 pgraph_enabled=0xffffffff cpu_known=yes eip=0x80046318
BOOT_MARK b6 pfifo=window context=native-headless seq=1 op=pusher-empty channel=0 window_start=0x03880e00 dma_get=0x03881318 dma_put=0x03881318
EOF

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 nv2a=irq-source context=browser-runtime seq=1 source=pcrtc op=intr-enable value=0x00000000 pmc_pending_before=0x00000000 pmc_enabled_before=0x00000000 pmc_pending_after=0x00000000 pmc_enabled_after=0x00000000 pcrtc_pending_before=0x00000001 pcrtc_enabled_before=0x00000000 pcrtc_pending_after=0x00000001 pcrtc_enabled_after=0x00000000 pgraph_pending_before=0x00000000 pgraph_enabled_before=0x00000000 pgraph_pending_after=0x00000000 pgraph_enabled_after=0x00000000
BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime guest_addr=0x00010000 image_size=4096 headers_size=512 entry=0x00010100 title_id=0xffff0002 source=virtual-header phys_addr=0x000e0000
BOOT_MARK b6 nv2a=irq-source context=browser-runtime seq=2 source=pcrtc op=vblank-raise value=0x00000001 pmc_pending_before=0x00000000 pmc_enabled_before=0x00000001 pmc_pending_after=0x01000000 pmc_enabled_after=0x00000001 pcrtc_pending_before=0x00000000 pcrtc_enabled_before=0x00000001 pcrtc_pending_after=0x00000001 pcrtc_enabled_after=0x00000001 pgraph_pending_before=0x00000000 pgraph_enabled_before=0xffffffff pgraph_pending_after=0x00000000 pgraph_enabled_after=0xffffffff
BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime status=ready guest_entry=0x00010100 image_pc=0x00010100 entry_offset=0x00000100 image_base=0x00010000 image_size=4096 relation=overlap distance=0 address_mode=direct entry_phys_mapped=yes entry_phys=0x00020100 image_phys_mapped=yes image_phys=0x00020100 phys_match=yes entry_code_read=yes entry_code_hash=0x0123456789abcdef entry_opcode=0x55 source=virtual-header
BOOT_MARK b6 nv2a=irq-source context=browser-runtime seq=3 source=pcrtc op=vblank-raise value=0x00000001 pmc_pending_before=0x00000000 pmc_enabled_before=0x00000001 pmc_pending_after=0x01000000 pmc_enabled_after=0x00000001 pcrtc_pending_before=0x00000000 pcrtc_enabled_before=0x00000001 pcrtc_pending_after=0x00000001 pcrtc_enabled_after=0x00000001 pgraph_pending_before=0x00000000 pgraph_enabled_before=0xffffffff pgraph_pending_after=0x00000000 pgraph_enabled_after=0xffffffff
BOOT_MARK b6 nv2a=pmc-access context=browser-runtime seq=1 op=write reg=NV_PMC_INTR_EN_0 addr=0x00000140 size=4 value=0x00000000 pmc_pending_before=0x01000000 pmc_enabled_before=0x00000001 pmc_pending_after=0x01000000 pmc_enabled_after=0x00000000 pfifo_pending=0x00000000 pfifo_enabled=0x01111111 pcrtc_pending=0x00000001 pcrtc_enabled=0x00000001 pgraph_pending=0x00000000 pgraph_enabled=0xffffffff cpu_known=yes eip=0x80045ba1
BOOT_MARK b6 nv2a=pmc-access context=browser-runtime seq=2 op=write reg=NV_PMC_INTR_EN_0 addr=0x00000140 size=4 value=0x00000001 pmc_pending_before=0x00000000 pmc_enabled_before=0x00000000 pmc_pending_after=0x00000000 pmc_enabled_after=0x00000001 pfifo_pending=0x00000000 pfifo_enabled=0x01111111 pcrtc_pending=0x00000000 pcrtc_enabled=0x00000001 pgraph_pending=0x00000000 pgraph_enabled=0xffffffff cpu_known=yes eip=0x80046318
BOOT_MARK b6 pfifo=window context=browser-runtime seq=1 op=pusher-empty channel=0 window_start=0x03880e00 dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 nv2a=irq-source context=browser-runtime seq=4 source=pcrtc op=vblank-raise value=0x00000001 pmc_pending_before=0x00000000 pmc_enabled_before=0x00000001 pmc_pending_after=0x01000000 pmc_enabled_after=0x00000001 pcrtc_pending_before=0x00000000 pcrtc_enabled_before=0x00000001 pcrtc_pending_after=0x00000001 pcrtc_enabled_after=0x00000001 pgraph_pending_before=0x00000000 pgraph_enabled_before=0xffffffff pgraph_pending_after=0x00000000 pgraph_enabled_after=0xffffffff
EOF

output="$("${repo_root}/scripts/xbox-pcrtc-vblank-divergence.py" \
    --native-log "${native_log}" \
    --browser-log "${browser_log}")"

printf '%s\n' "${output}"

for pattern in \
    'PCRTC_VBLANK_DIVERGENCE result=pass' \
    'divergence=browser-initial-pcrtc-pending' \
    'native_first_pcrtc_pending_before=0x00000000' \
    'browser_first_pcrtc_pending_before=0x00000001' \
    'browser_vblank_xbe_to_ready=1' \
    'browser_vblank_ready_to_idle=1' \
    'browser_vblank_after_idle=1' \
    'browser_pmc_disable_pcrtc=1'; do
    if ! printf '%s\n' "${output}" | grep -q "${pattern}"; then
        printf 'PCRTC_VBLANK_DIVERGENCE_SELFTEST result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        exit 1
    fi
done

printf 'PCRTC_VBLANK_DIVERGENCE_SELFTEST_RESULT result=pass cases=1\n'
