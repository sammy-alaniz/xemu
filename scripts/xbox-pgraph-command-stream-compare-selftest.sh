#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-pgraph-command-stream-compare.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-pgraph-command-stream.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

native_log="${tmp_dir}/native.log"
browser_log="${tmp_dir}/browser.log"
out_path="${tmp_dir}/out.log"

cat >"${native_log}" <<'EOF'
BOOT_MARK b6 pgraph=notify-error context=native-headless seq=1 trapped_data=0x00000304 dma_get=0x03880e2c dma_put=0x03881318
BOOT_MARK b6 pgraph=notify-clear context=native-headless seq=1 pending_after=0x00000000 waiting_nop_after=no trapped_data=0x00000304 dma_get=0x03880e30 dma_put=0x03881318
BOOT_MARK b6 pfifo=window context=native-headless seq=1 op=pusher-puller-stall method=0x0100 parameter=0x00000304 dma_get=0x03880e30 dma_put=0x03881318
BOOT_MARK b6 pgraph=method-window context=native-headless seq=1 phase=exit method=0x0100 parameter=0x00000304 dma_get=0x03880e30 dma_put=0x03881318
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless start_pc=0x80030e4c next_pc=0x80014f32 loop_kind=backward nv2a_wait_source=pgraph nv2a_wait_op=intr-clear nv2a_wait_seq=23 nv2a_dma_get=0x03880e30 nv2a_dma_put=0x03881318 nv2a_pgraph_pending=0x00000000 nv2a_waiting_nop=no
EOF

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 pgraph=notify-error context=browser-runtime seq=1 trapped_data=0x00000304 dma_get=0x03880e2c dma_put=0x03881318
BOOT_MARK b6 pgraph=notify-clear context=browser-runtime seq=1 pending_after=0x00000000 waiting_nop_after=no trapped_data=0x00000304 dma_get=0x03880e30 dma_put=0x03881318
BOOT_MARK b6 pfifo=window context=browser-runtime seq=1 op=pusher-puller-done method=0x0100 parameter=0x00000304 dma_get=0x03880e30 dma_put=0x03881318
BOOT_MARK b6 pgraph=method-window context=browser-runtime seq=1 phase=exit method=0x0100 parameter=0x00000304 dma_get=0x03880e30 dma_put=0x03881318
BOOT_MARK b6 pgraph=notify-error context=browser-runtime seq=2 trapped_data=0x00000310 dma_get=0x0393a800 dma_put=0x0393a804
BOOT_MARK b6 pgraph=notify-clear context=browser-runtime seq=2 pending_after=0x00000000 waiting_nop_after=no trapped_data=0x00000310 dma_get=0x0393a804 dma_put=0x0393a804
BOOT_MARK b6 pfifo=window context=browser-runtime seq=2 op=pusher-empty method=0x0100 parameter=0x00000310 dma_get=0x0393a804 dma_put=0x0393a804
BOOT_MARK b6 pgraph=method-window context=browser-runtime seq=2 phase=exit method=0x0100 parameter=0x00000310 dma_get=0x0393a804 dma_put=0x0393a804
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime start_pc=0x80045ca6 next_pc=0x80014386 loop_kind=backward nv2a_wait_source=pgraph-notify-clear nv2a_wait_op=notify-error-clear nv2a_wait_seq=2 nv2a_dma_get=0x0393a804 nv2a_dma_put=0x0393a804 nv2a_pgraph_pending=0x00000000 nv2a_waiting_nop=no
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PGRAPH_COMMAND_STREAM_COMPARE_SELFTEST case=browser-extra result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

for pattern in \
    'PGRAPH_COMMAND_STREAM_COMPARE result=pass' \
    'divergence=browser-extra-notify-clear' \
    'command_stream_aligned=no' \
    'native_notify_clear=1' \
    'browser_notify_clear=2' \
    'native_last_trapped_data=0x00000304' \
    'browser_last_trapped_data=0x00000310' \
    'native_pfifo_window=1' \
    'browser_pfifo_window=2' \
    'native_pgraph_method_window=1' \
    'browser_pgraph_method_window=2' \
    'browser_pfifo_window_dma_get=0x0393a804' \
    'browser_pgraph_window_dma_get=0x0393a804' \
    'native_loop_start_pc=0x80030e4c' \
    'browser_loop_start_pc=0x80045ca6'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'PGRAPH_COMMAND_STREAM_COMPARE_SELFTEST case=browser-extra result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done

printf 'PGRAPH_COMMAND_STREAM_COMPARE_SELFTEST case=browser-extra result=pass\n'

cat >"${native_log}" <<'EOF'
BOOT_MARK b6 pgraph=notify-error context=native-headless seq=8 trapped_data=0x00000304 dma_get=0x03880e2c dma_put=0x03881318
BOOT_MARK b6 pgraph=notify-clear context=native-headless seq=8 pending_after=0x00000000 waiting_nop_after=no trapped_data=0x00000304 dma_get=0x03880e30 dma_put=0x03881318
BOOT_MARK b6 pfifo=window context=native-headless seq=379 op=pusher-empty method=0x0000 parameter=0x00000000 dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 pgraph=method-window context=native-headless seq=200 phase=exit method=0x1d90 parameter=0x00000000 dma_get=0x03881314 dma_put=0x03881318
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless start_pc=0x8001b02f next_pc=0x8001b030 loop_kind=fallthrough nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty nv2a_wait_seq=375 nv2a_dma_get=0x03881318 nv2a_dma_put=0x03881318 nv2a_pgraph_pending=0x00000000 nv2a_waiting_nop=no
EOF

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 pgraph=notify-error context=browser-runtime seq=8 trapped_data=0x00000304 dma_get=0x03880e2c dma_put=0x03881318
BOOT_MARK b6 pgraph=notify-clear context=browser-runtime seq=8 pending_after=0x00000000 waiting_nop_after=no trapped_data=0x00000304 dma_get=0x03880e30 dma_put=0x03881318
BOOT_MARK b6 pfifo=window context=browser-runtime seq=381 op=pusher-empty method=0x0000 parameter=0x00000000 dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 pgraph=method-window context=browser-runtime seq=200 phase=exit method=0x1d90 parameter=0x00000000 dma_get=0x03881314 dma_put=0x03881318
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime start_pc=0x80014fb4 next_pc=0x8001aea5 loop_kind=forward nv2a_wait_source=pcrtc nv2a_wait_op=vblank-raise nv2a_wait_seq=36 nv2a_dma_get=0x03880000 nv2a_dma_put=0x03880000 nv2a_pgraph_pending=0x00000000 nv2a_waiting_nop=no
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PGRAPH_COMMAND_STREAM_COMPARE_SELFTEST case=post-command-loop result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

for pattern in \
    'PGRAPH_COMMAND_STREAM_COMPARE result=pass' \
    'divergence=post-command-loop-mismatch' \
    'command_stream_aligned=yes' \
    'native_stream_idle=yes' \
    'browser_stream_idle=yes' \
    'native_pfifo_window_dma_get=0x03881318' \
    'browser_pfifo_window_dma_get=0x03881318' \
    'native_pgraph_window_method=0x1d90' \
    'browser_pgraph_window_method=0x1d90' \
    'native_loop_start_pc=0x8001b02f' \
    'browser_loop_start_pc=0x80014fb4'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'PGRAPH_COMMAND_STREAM_COMPARE_SELFTEST case=post-command-loop result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done

printf 'PGRAPH_COMMAND_STREAM_COMPARE_SELFTEST case=post-command-loop result=pass\n'

if "${script}" --native-log "${tmp_dir}/missing.log" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PGRAPH_COMMAND_STREAM_COMPARE_SELFTEST case=missing-native result=fail reason=unexpected-pass\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'result=fail' "${out_path}"; then
    printf 'PGRAPH_COMMAND_STREAM_COMPARE_SELFTEST case=missing-native result=fail reason=missing-fail\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

printf 'PGRAPH_COMMAND_STREAM_COMPARE_SELFTEST case=missing-native result=pass\n'
printf 'PGRAPH_COMMAND_STREAM_COMPARE_SELFTEST_RESULT result=pass cases=3\n'
