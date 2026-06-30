#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-boot-smoke-matrix.sh

Runs the browser-boot evidence matrix:
  1. fixture preflight
  2. native Docker headless smoke
  3. wasm Node headless smoke
  4. native-vs-wasm BOOT_MARK comparison

Required fixture:
  XEMU_FLASH       Path to Xbox flash/BIOS image.

Optional fixtures:
  XEMU_MCPX        Path to MCPX boot ROM. Must be exactly 512 bytes.
  XEMU_EEPROM      Path to EEPROM image. Must be exactly 256 bytes.
  XEMU_HDD         Path to Xbox HDD image. Required for B3 or higher.
  XEMU_DVD         Path to optional DVD image.

Optional controls:
  XEMU_MATRIX_EXPECT_LEVEL   Expected minimum B-level. Default: B3.
  XEMU_MATRIX_COMPARE_LEVEL  Marker compare minimum B-level. Defaults to expected level.
  XEMU_MATRIX_OUT_DIR        Output dir. Default: build-boot-matrix.
  XEMU_MATRIX_SKIP_NATIVE    Skip docker-headless when set to 1.
  XEMU_MATRIX_SKIP_WASM      Skip wasm-node-headless when set to 1.
  XEMU_SMOKE_MS              Per-smoke timeout ms. Default comes from xbox-boot-smoke.sh.

Evidence files:
  fixtures.log              Fixture preflight output.
  native/boot-smoke.log     Native Docker smoke log.
  wasm/boot-smoke.log       Wasm Node smoke log.
  compare.log               Native-vs-wasm marker comparison.
  matrix.log                Whole matrix transcript.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
out_dir="${XEMU_MATRIX_OUT_DIR:-${repo_root}/build-boot-matrix}"
case "${out_dir}" in
    /*) ;;
    *) out_dir="${repo_root}/${out_dir}" ;;
esac

expect_level="${XEMU_MATRIX_EXPECT_LEVEL:-B3}"
compare_level="${XEMU_MATRIX_COMPARE_LEVEL:-${expect_level}}"
skip_native="${XEMU_MATRIX_SKIP_NATIVE:-0}"
skip_wasm="${XEMU_MATRIX_SKIP_WASM:-0}"
fixture_log="${out_dir}/fixtures.log"
native_dir="${out_dir}/native"
wasm_dir="${out_dir}/wasm"
compare_log="${out_dir}/compare.log"
matrix_log="${out_dir}/matrix.log"

smoke_env=()
add_smoke_env_if_set() {
    local name="$1"
    if [ -n "${!name:-}" ]; then
        smoke_env+=("${name}=${!name}")
    fi
}

for name in \
    XEMU_FLASH \
    XEMU_MCPX \
    XEMU_EEPROM \
    XEMU_HDD \
    XEMU_DVD \
    XEMU_SMOKE_MS \
    XEMU_SMOKE_DOCKER_IMAGE \
    XEMU_SMOKE_BUILD_DIR \
    XEMU_SMOKE_WASM_IMAGE \
    XEMU_SMOKE_WASM_BUILD_DIR
do
    add_smoke_env_if_set "${name}"
done

mkdir -p "${out_dir}"
rm -f "${fixture_log}" "${compare_log}" "${matrix_log}"
exec > >(tee "${matrix_log}") 2>&1

"${repo_root}/scripts/xbox-boot-fixtures-check.sh" | tee "${fixture_log}"

native_log=""
wasm_log=""

if [ "${skip_native}" != "1" ]; then
    env "${smoke_env[@]}" \
    XEMU_SMOKE_EXPECT_LEVEL="${expect_level}" \
    XEMU_SMOKE_OUT_DIR="${native_dir}" \
        "${repo_root}/scripts/xbox-boot-smoke.sh" docker-headless
    native_log="${native_dir}/boot-smoke.log"
fi

if [ "${skip_wasm}" != "1" ]; then
    env "${smoke_env[@]}" \
    XEMU_SMOKE_EXPECT_LEVEL="${expect_level}" \
    XEMU_SMOKE_OUT_DIR="${wasm_dir}" \
        "${repo_root}/scripts/xbox-boot-smoke.sh" wasm-node-headless
    wasm_log="${wasm_dir}/boot-smoke.log"
fi

if [ -n "${native_log}" ] && [ -n "${wasm_log}" ]; then
    XEMU_COMPARE_MIN_LEVEL="${compare_level}" \
    XEMU_COMPARE_STORAGE_B3_EQUIV=1 \
        "${repo_root}/scripts/xbox-boot-compare-markers.sh" \
        "${native_log}" "${wasm_log}" | tee "${compare_log}"
fi

printf 'BOOT_MATRIX_RESULT result=pass expected=%s compare=%s out_dir=%s\n' \
    "${expect_level}" "${compare_level}" "${out_dir}"
