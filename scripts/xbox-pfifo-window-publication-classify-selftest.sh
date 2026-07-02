#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-pfifo-window-publication-classify.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-pfifo-window-classify.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

browser_log="${tmp_dir}/browser.log"
out_path="${tmp_dir}/out.log"

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 headless=timer-opportunity context=browser-runtime seq=1 ready=no reason=wait-not-pfifo-empty wait_source=pcrtc wait_op=vblank-suppress
BOOT_MARK b6 headless=timer-opportunity context=browser-runtime seq=2 ready=no reason=wait-not-pfifo-empty wait_source=pcrtc wait_op=vblank-suppress
BOOT_MARK b6 pfifo=progress context=browser-runtime seq=1 op=pusher-enter dma_get=0x03880000 dma_put=0x03881318 available=0
BOOT_MARK b6 pfifo=progress context=browser-runtime seq=2 op=pusher-new-method-inc dma_get=0x03880dfc dma_put=0x03881318 available=327
BOOT_MARK b6 pfifo=window context=browser-runtime seq=1 op=pusher-new-method-inc window_start=0x03880e00 dma_get=0x03880e00 dma_put=0x03881318 available=326
EOF

if ! "${script}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PFIFO_WINDOW_PUBLICATION_CLASSIFY_SELFTEST case=after-opportunity result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
for pattern in \
    'PFIFO_WINDOW_PUBLICATION_CLASSIFY result=pass' \
    'divergence=pfifo-producer-starts-after-opportunities-window-start-gated' \
    'timer_opportunities=2' \
    'pfifo_progress=2' \
    'pfifo_windows=1' \
    'window_start=0x03880e00' \
    'progress_before_first_opportunity=no' \
    'last_not_published_reason_before_first_opportunity=no-pfifo-producer-before-first-opportunity' \
    'first_pfifo_progress_after_last_opportunity=yes' \
    'progress_between_last_opportunity_and_first_window=2' \
    'last_progress_before_window_dma_get=0x03880dfc' \
    'last_not_published_reason_before_window=dma-get-before-window-start' \
    'first_window_line=5' \
    'first_published_reason=window-start-reached'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'PFIFO_WINDOW_PUBLICATION_CLASSIFY_SELFTEST case=after-opportunity result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'PFIFO_WINDOW_PUBLICATION_CLASSIFY_SELFTEST case=after-opportunity result=pass\n'

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 pfifo=progress context=browser-runtime seq=1 op=pusher-enter dma_get=0x03880000 dma_put=0x03881318 available=0
BOOT_MARK b6 headless=timer-opportunity context=browser-runtime seq=1 ready=no reason=wait-not-pfifo-empty wait_source=pcrtc wait_op=vblank-suppress
BOOT_MARK b6 pfifo=window context=browser-runtime seq=1 op=pusher-new-method-inc window_start=0x03880e00 dma_get=0x03880e00 dma_put=0x03881318 available=326
EOF

if ! "${script}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PFIFO_WINDOW_PUBLICATION_CLASSIFY_SELFTEST case=producer-before-opportunity result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
for pattern in \
    'divergence=pfifo-producer-active-before-opportunities' \
    'progress_before_first_opportunity=yes' \
    'last_not_published_reason_before_first_opportunity=dma-get-before-window-start' \
    'first_pfifo_progress_after_first_opportunity=no'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'PFIFO_WINDOW_PUBLICATION_CLASSIFY_SELFTEST case=producer-before-opportunity result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'PFIFO_WINDOW_PUBLICATION_CLASSIFY_SELFTEST case=producer-before-opportunity result=pass\n'

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 headless=timer-opportunity context=browser-runtime seq=1 ready=no reason=wait-not-pfifo-empty wait_source=pcrtc wait_op=vblank-suppress
BOOT_MARK b6 pfifo=progress context=browser-runtime seq=1 op=pusher-enter dma_get=0x03880000 dma_put=0x03881318 available=0
EOF

if "${script}" --browser-log "${browser_log}" --window-start 0x03880e00 >"${out_path}" 2>&1; then
    printf 'PFIFO_WINDOW_PUBLICATION_CLASSIFY_SELFTEST case=missing-window result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
for pattern in \
    'PFIFO_WINDOW_PUBLICATION_CLASSIFY result=fail' \
    'divergence=missing-pfifo-window-publication' \
    'first_published_reason=missing-pfifo-window-publication'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'PFIFO_WINDOW_PUBLICATION_CLASSIFY_SELFTEST case=missing-window result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'PFIFO_WINDOW_PUBLICATION_CLASSIFY_SELFTEST case=missing-window result=pass\n'

printf 'PFIFO_WINDOW_PUBLICATION_CLASSIFY_SELFTEST_RESULT result=pass cases=3\n'
