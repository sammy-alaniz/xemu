#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-browser-boot-verify-synthetic.sh

Runs the no-private-assets verification gate for the Xbox browser boot work.
This proves the reduced wasm profile, fixture validators, browser block helper,
browser host, real browser synthetic run, and synthetic native-vs-wasm boot
matrix. It does not prove real dashboard-capable HDD B3 boot.

Controls:
  XEMU_VERIFY_SYNTHETIC_OUT_DIR       Output dir. Default: build-browser-boot-verify-synthetic.
  XEMU_VERIFY_SYNTHETIC_WASM_BUILD    Wasm build dir. Default: build-wasm-pic.
  XEMU_VERIFY_SYNTHETIC_HOST_PORT     Host-check server port. Default: 8784.
  XEMU_VERIFY_SYNTHETIC_RUNTIME_PORT  Runtime smoke server port. Default: 8785.
  XEMU_VERIFY_SYNTHETIC_BLOCK_PORT    Block persistence smoke port. Default: runtime + 2.
  XEMU_VERIFY_SYNTHETIC_DISPLAY_PORT  Display capture smoke port. Default: runtime + 3.
  XEMU_VERIFY_SKIP_HOST               Skip HTTP host check when set to 1.
  XEMU_VERIFY_SKIP_RUNTIME            Skip Playwright browser runtime smoke when set to 1.
  XEMU_VERIFY_SKIP_MATRIX             Skip Docker/native-vs-wasm synthetic matrix when set to 1.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
out_dir="${XEMU_VERIFY_SYNTHETIC_OUT_DIR:-${repo_root}/build-browser-boot-verify-synthetic}"
wasm_build="${XEMU_VERIFY_SYNTHETIC_WASM_BUILD:-build-wasm-pic}"
host_port="${XEMU_VERIFY_SYNTHETIC_HOST_PORT:-8784}"
runtime_port="${XEMU_VERIFY_SYNTHETIC_RUNTIME_PORT:-8785}"
block_port="${XEMU_VERIFY_SYNTHETIC_BLOCK_PORT:-$((runtime_port + 2))}"
display_port="${XEMU_VERIFY_SYNTHETIC_DISPLAY_PORT:-$((runtime_port + 3))}"
skip_host="${XEMU_VERIFY_SKIP_HOST:-0}"
skip_runtime="${XEMU_VERIFY_SKIP_RUNTIME:-0}"
skip_matrix="${XEMU_VERIFY_SKIP_MATRIX:-0}"

case "${out_dir}" in
    /*) ;;
    *) out_dir="${repo_root}/${out_dir}" ;;
esac

mkdir -p "${out_dir}"
verify_log="${out_dir}/synthetic-verify.log"
rm -f "${verify_log}"

canonical_report="${repo_root}/xbox-browser-boot-status.md"
if [ "${skip_host}" = "1" ] || [ "${skip_runtime}" = "1" ] || [ "${skip_matrix}" = "1" ]; then
    canonical_report="${out_dir}/xbox-browser-boot-status.md"
fi

run_step() {
    local name="$1"
    shift

    printf 'VERIFY_STEP name=%s status=start\n' "${name}"
    "$@"
    printf 'VERIFY_STEP name=%s status=pass\n' "${name}"
}

run_expected_failure() {
    local name="$1"
    local expected="$2"
    local log_path="${out_dir}/${name}.log"
    shift 2

    printf 'VERIFY_STEP name=%s status=start\n' "${name}"
    if "$@" >"${log_path}" 2>&1; then
        printf 'VERIFY_STEP name=%s status=fail reason=unexpected-pass log=%s\n' \
            "${name}" "${log_path}" >&2
        cat "${log_path}" >&2
        return 1
    fi
    if ! grep -q "${expected}" "${log_path}"; then
        printf 'VERIFY_STEP name=%s status=fail reason=missing-expected-output expected=%s log=%s\n' \
            "${name}" "${expected}" "${log_path}" >&2
        cat "${log_path}" >&2
        return 1
    fi
    cat "${log_path}"
    printf 'VERIFY_STEP name=%s status=pass\n' "${name}"
}

run_browser_runtime_real_guard() {
    env -i PATH="${PATH}" \
        XEMU_BROWSER_RUNTIME_MODE=real \
        XEMU_BROWSER_RUNTIME_PORT="$((runtime_port + 1))" \
            "${repo_root}/scripts/xbox-browser-runtime-smoke.sh"
}

run_real_fixture_readiness() {
    "${repo_root}/scripts/xbox-real-fixtures-ready.sh" | tee "${out_dir}/real-fixture-ready.log"
}

run_host_check() {
    local server_log="${out_dir}/host-server.log"
    local server_pid=""
    local status=0

    python3 "${repo_root}/scripts/serve-xbox-browser-boot.py" --port "${host_port}" >"${server_log}" 2>&1 &
    server_pid="$!"

    cleanup_host_server() {
        if [ -n "${server_pid}" ]; then
            kill "${server_pid}" >/dev/null 2>&1 || true
            wait "${server_pid}" >/dev/null 2>&1 || true
        fi
    }

    for _ in $(seq 1 50); do
        if curl -fsSI "http://127.0.0.1:${host_port}/browser/xbox-boot/" >/dev/null 2>&1; then
            break
        fi
        if ! kill -0 "${server_pid}" >/dev/null 2>&1; then
            printf 'VERIFY_STEP name=browser-host-check status=fail reason=server-exited log=%s\n' "${server_log}" >&2
            cat "${server_log}" >&2
            cleanup_host_server
            return 1
        fi
        sleep 0.1
    done

    set +e
    "${repo_root}/scripts/xbox-browser-host-check.sh" "http://127.0.0.1:${host_port}"
    status="$?"
    set -e
    cleanup_host_server
    return "${status}"
}

run_all() {
    cd "${repo_root}"

    run_step shell-syntax bash -n \
        scripts/xbox-boot-fixtures-check.sh \
        scripts/xbox-boot-fixtures-check-selftest.sh \
        scripts/xbox-fixture-privacy-check.sh \
        scripts/xbox-fixture-privacy-check-selftest.sh \
        scripts/xbox-real-fixtures-ready.sh \
        scripts/xbox-real-fixtures-ready-selftest.sh \
        scripts/xbox-real-fixture-manifest.sh \
        scripts/xbox-real-fixture-manifest-selftest.sh \
        scripts/xbox-real-fixture-layout.sh \
        scripts/xbox-real-fixture-layout-selftest.sh \
        scripts/xbox-real-b3-matrix.sh \
        scripts/xbox-real-b3-matrix-selftest.sh \
        scripts/xbox-real-b3-evidence-check.sh \
        scripts/xbox-real-b3-evidence-check-selftest.sh \
        scripts/xbox-display-capture-evidence-check.sh \
        scripts/xbox-display-capture-evidence-check-selftest.sh \
        scripts/xbox-browser-runtime-evidence-check.sh \
        scripts/xbox-browser-runtime-evidence-check-selftest.sh \
        scripts/xbox-native-reference-evidence-check.sh \
        scripts/xbox-native-reference-evidence-check-selftest.sh \
        scripts/xbox-dashboard-loaded-evidence-check.sh \
        scripts/xbox-dashboard-loaded-evidence-check-selftest.sh \
        scripts/xbox-native-actual-xbe-execution-check-selftest.sh \
        scripts/xbox-native-headless-handoff-check-selftest.sh \
        scripts/xbox-dashboard-xbe-read-evidence-selftest.sh \
        scripts/xbox-dashboard-xbe-hash-evidence-selftest.sh \
        scripts/xbox-pgraph-command-stream-compare-selftest.sh \
        scripts/xbox-post-command-handoff-compare-selftest.sh \
        scripts/xbox-post-command-loop-clusters-selftest.sh \
        scripts/xbox-post-service-memory-poll-compare-selftest.sh \
        scripts/xbox-pre-service-tick-gap-compare-selftest.sh \
        scripts/xbox-pcrtc-vblank-divergence-selftest.sh \
        scripts/xbox-browser-host-check.sh \
        scripts/xbox-browser-runtime-smoke.sh \
        scripts/xbox-browser-runtime-smoke-selftest.sh \
        scripts/xbox-browser-display-capture-smoke.sh \
        scripts/xbox-browser-block-persistence-smoke.sh \
        scripts/xbox-browser-block-callback-smoke.sh \
        scripts/xbox-boot-smoke.sh \
        scripts/xbox-boot-smoke-selftest.sh \
        scripts/xbox-boot-smoke-matrix.sh \
        scripts/xbox-boot-synthetic-matrix.sh \
        scripts/xbox-boot-compare-markers.sh \
        scripts/xbox-verify-wasm-profile.sh \
        scripts/xbox-boot-completion-audit.sh \
        scripts/xbox-boot-completion-audit-selftest.sh \
        scripts/xbox-boot-evidence-summary.sh \
        scripts/xbox-boot-evidence-summary-selftest.sh \
        scripts/xbox-boot-evidence-report.sh \
        scripts/xbox-boot-next-step.sh \
        scripts/xbox-boot-next-step-selftest.sh \
        scripts/xbox-b6-current-boundary.sh \
        scripts/docker-build-xemu.sh \
        scripts/docker-build-xemu-wasm.sh \
        scripts/docker-build-wasm-sysroot.sh \
        scripts/xbox-docker-build-check.sh

    run_step python-syntax python3 -m py_compile \
        scripts/xbox-dashboard-xbe-read-evidence.py \
        scripts/xbox-dashboard-xbe-hash-evidence.py \
        scripts/xbox-native-actual-xbe-execution-check.py \
        scripts/xbox-native-headless-handoff-check.py \
        scripts/xbox-pgraph-command-stream-compare.py \
        scripts/xbox-post-command-handoff-compare.py \
        scripts/xbox-post-command-loop-clusters.py \
        scripts/xbox-post-service-memory-poll-compare.py \
        scripts/xbox-pre-service-tick-gap-compare.py
    run_step browser-js-syntax node --check browser/xbox-boot/main.js
    run_step browser-worker-syntax node --check browser/xbox-boot/worker.js
    run_step browser-firefox-bidi-syntax node --check scripts/xbox-browser-runtime-firefox-bidi.mjs
    run_step docker-build-check "${repo_root}/scripts/xbox-docker-build-check.sh"
    run_step wasm-profile "${repo_root}/scripts/xbox-verify-wasm-profile.sh" "${wasm_build}"
    run_step fixture-privacy "${repo_root}/scripts/xbox-fixture-privacy-check.sh"
    run_step fixture-privacy-selftest "${repo_root}/scripts/xbox-fixture-privacy-check-selftest.sh"
    run_step fixture-guards "${repo_root}/scripts/xbox-boot-fixtures-check-selftest.sh"
    run_step real-fixture-layout "${repo_root}/scripts/xbox-real-fixture-layout-selftest.sh"
    run_step real-fixture-readiness-report run_real_fixture_readiness
    run_step real-fixture-readiness "${repo_root}/scripts/xbox-real-fixtures-ready-selftest.sh"
    run_step real-fixture-manifest "${repo_root}/scripts/xbox-real-fixture-manifest.sh" "${out_dir}/real-fixture-manifest"
    run_step real-fixture-manifest-selftest "${repo_root}/scripts/xbox-real-fixture-manifest-selftest.sh"
    run_step real-b3-wrapper "${repo_root}/scripts/xbox-real-b3-matrix-selftest.sh"
    run_step real-b3-evidence "${repo_root}/scripts/xbox-real-b3-evidence-check-selftest.sh"
    run_step boot-smoke-parser "${repo_root}/scripts/xbox-boot-smoke-selftest.sh"
    run_step browser-block-storage node scripts/xbox-browser-block-selftest.mjs
    run_step evidence-summary-selftest "${repo_root}/scripts/xbox-boot-evidence-summary-selftest.sh"
    run_step completion-audit-selftest "${repo_root}/scripts/xbox-boot-completion-audit-selftest.sh"
    XEMU_COMPLETION_AUDIT_ALLOW_INCOMPLETE=1 \
        run_step completion-audit "${repo_root}/scripts/xbox-boot-completion-audit.sh" "${out_dir}"
    run_step next-step-selftest "${repo_root}/scripts/xbox-boot-next-step-selftest.sh"
    run_step display-capture-evidence "${repo_root}/scripts/xbox-display-capture-evidence-check-selftest.sh"
    run_step browser-runtime-evidence "${repo_root}/scripts/xbox-browser-runtime-evidence-check-selftest.sh"
    run_step native-reference-evidence "${repo_root}/scripts/xbox-native-reference-evidence-check-selftest.sh"
    run_step dashboard-loaded-evidence "${repo_root}/scripts/xbox-dashboard-loaded-evidence-check-selftest.sh"
    run_step native-actual-xbe-execution "${repo_root}/scripts/xbox-native-actual-xbe-execution-check-selftest.sh"
    run_step native-headless-handoff "${repo_root}/scripts/xbox-native-headless-handoff-check-selftest.sh"
    run_step dashboard-xbe-read-evidence "${repo_root}/scripts/xbox-dashboard-xbe-read-evidence-selftest.sh"
    run_step dashboard-xbe-hash-evidence "${repo_root}/scripts/xbox-dashboard-xbe-hash-evidence-selftest.sh"
    run_step pgraph-command-stream-compare "${repo_root}/scripts/xbox-pgraph-command-stream-compare-selftest.sh"
    run_step post-command-handoff-compare "${repo_root}/scripts/xbox-post-command-handoff-compare-selftest.sh"
    run_step post-command-loop-clusters "${repo_root}/scripts/xbox-post-command-loop-clusters-selftest.sh"
    run_step post-service-memory-poll-compare "${repo_root}/scripts/xbox-post-service-memory-poll-compare-selftest.sh"
    run_step pre-service-tick-gap-compare "${repo_root}/scripts/xbox-pre-service-tick-gap-compare-selftest.sh"
    run_step pcrtc-vblank-divergence "${repo_root}/scripts/xbox-pcrtc-vblank-divergence-selftest.sh"
    run_step browser-runtime-smoke-selftest "${repo_root}/scripts/xbox-browser-runtime-smoke-selftest.sh"

    if [ "${skip_host}" = "1" ]; then
        printf 'VERIFY_STEP name=browser-host-check status=skipped\n'
    else
        run_step browser-host-check run_host_check
    fi

    if [ "${skip_runtime}" = "1" ]; then
        printf 'VERIFY_STEP name=browser-display-capture status=skipped\n'
        printf 'VERIFY_STEP name=browser-block-persistence status=skipped\n'
        printf 'VERIFY_STEP name=browser-runtime-smoke status=skipped\n'
        printf 'VERIFY_STEP name=browser-runtime-real-guard status=skipped\n'
    else
        XEMU_BROWSER_DISPLAY_CAPTURE_PORT="${display_port}" \
            run_step browser-display-capture "${repo_root}/scripts/xbox-browser-display-capture-smoke.sh"
        XEMU_BROWSER_BLOCK_PERSISTENCE_PORT="${block_port}" \
            run_step browser-block-persistence "${repo_root}/scripts/xbox-browser-block-persistence-smoke.sh"
        XEMU_BROWSER_RUNTIME_PORT="${runtime_port}" \
        XEMU_BROWSER_RUNTIME_TIMEOUT_MS="${XEMU_BROWSER_RUNTIME_TIMEOUT_MS:-60000}" \
            run_step browser-runtime-smoke "${repo_root}/scripts/xbox-browser-runtime-smoke.sh"
        run_expected_failure browser-runtime-real-guard \
            'BROWSER_RUNTIME_SMOKE result=fail reason=missing-env name=XEMU_FLASH' \
            run_browser_runtime_real_guard
    fi

    if [ "${skip_matrix}" = "1" ]; then
        printf 'VERIFY_STEP name=synthetic-matrix status=skipped\n'
    else
        XEMU_SYNTHETIC_OUT_DIR="${out_dir}/synthetic-matrix" \
            run_step synthetic-matrix "${repo_root}/scripts/xbox-boot-synthetic-matrix.sh"
    fi

    run_step evidence-summary "${repo_root}/scripts/xbox-boot-evidence-summary.sh" "${out_dir}"
    run_step evidence-report "${repo_root}/scripts/xbox-boot-evidence-report.sh" \
        "${canonical_report}" "${out_dir}"

    printf 'BROWSER_BOOT_SYNTHETIC_VERIFY result=pass out_dir=%s host=%s runtime=%s matrix=%s\n' \
        "${out_dir}" \
        "$([ "${skip_host}" = "1" ] && printf skipped || printf pass)" \
        "$([ "${skip_runtime}" = "1" ] && printf skipped || printf pass)" \
        "$([ "${skip_matrix}" = "1" ] && printf skipped || printf pass)"
}

run_all 2>&1 | tee "${verify_log}"
