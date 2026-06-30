#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-post-service-watch-edge-compare.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-post-service-watch-edge.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

native_log="${tmp_dir}/native.log"
browser_log="${tmp_dir}/browser.log"
out_path="${tmp_dir}/out.log"

cat >"${native_log}" <<'EOF'
BOOT_MARK b6 pfifo=window context=native-headless seq=1 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless observed_seq=1 stream_idle=yes start_pc=0x80014f5f next_pc=0x80030e84 next_mem_value_read=yes next_mem_addr=0x8003a890 next_mem_value=0x0014c080
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless observed_seq=2 stream_idle=yes start_pc=0x80030e84 next_pc=0x80030f31 start_mem_value_read=yes start_mem_addr=0x8003a890 start_mem_value=0x0014e790
EOF

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 pfifo=window context=browser-runtime seq=1 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=1 stream_idle=yes start_pc=0x80014f32 next_pc=0x80030e84 next_mem_value_read=yes next_mem_addr=0x8003a890 next_mem_value=0x00000000
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=2 stream_idle=yes start_pc=0x80030e84 next_pc=0x80030f31 start_mem_value_read=yes start_mem_addr=0x8003a890 start_mem_value=0x00002710
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'POST_SERVICE_WATCH_EDGE_COMPARE_SELFTEST case=pre-mismatch result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

for pattern in \
    'POST_SERVICE_WATCH_EDGE_COMPARE result=pass' \
    'divergence=pre-block-watch-value-mismatch' \
    'pre_tick_relation=browser-behind' \
    'pre_tick_delta=136' \
    'post_tick_delta=136' \
    'block_delta_match=yes' \
    'native_pre_ticks=136' \
    'native_post_ticks=137' \
    'native_block_delta_ticks=1' \
    'browser_pre_ticks=0' \
    'browser_post_ticks=1' \
    'browser_block_delta_ticks=1'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'POST_SERVICE_WATCH_EDGE_COMPARE_SELFTEST case=pre-mismatch result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done

printf 'POST_SERVICE_WATCH_EDGE_COMPARE_SELFTEST case=pre-mismatch result=pass\n'

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 pfifo=window context=browser-runtime seq=1 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=1 stream_idle=yes start_pc=0x80014f5f next_pc=0x80030e84 next_mem_value_read=yes next_mem_addr=0x8003a890 next_mem_value=0x0014c080
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=2 stream_idle=yes start_pc=0x80030e84 next_pc=0x80030f31 start_mem_value_read=yes start_mem_addr=0x8003a890 start_mem_value=0x0014e790
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'POST_SERVICE_WATCH_EDGE_COMPARE_SELFTEST case=equal result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'divergence=none' "${out_path}"; then
    printf 'POST_SERVICE_WATCH_EDGE_COMPARE_SELFTEST case=equal result=fail reason=missing-none\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

printf 'POST_SERVICE_WATCH_EDGE_COMPARE_SELFTEST case=equal result=pass\n'

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 pfifo=window context=browser-runtime seq=1 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=2 stream_idle=yes start_pc=0x80030e84 next_pc=0x80030f31 start_mem_value_read=yes start_mem_addr=0x8003a890 start_mem_value=0x00002710
EOF

if "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'POST_SERVICE_WATCH_EDGE_COMPARE_SELFTEST case=missing-pre result=fail reason=unexpected-pass\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'result=fail' "${out_path}" || \
   ! grep -q 'missing-browser-pre-edge' "${out_path}"; then
    printf 'POST_SERVICE_WATCH_EDGE_COMPARE_SELFTEST case=missing-pre result=fail reason=missing-fail\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

printf 'POST_SERVICE_WATCH_EDGE_COMPARE_SELFTEST case=missing-pre result=pass\n'
printf 'POST_SERVICE_WATCH_EDGE_COMPARE_SELFTEST_RESULT result=pass cases=3\n'
