#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-docker-build-check.sh

Checks that the Docker build scaffolding for the Xbox browser boot plan is
present and still carries the required native and wasm configuration flags.
This is a static check only; it does not build images or compile xemu.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
native_dockerfile="${repo_root}/docker/xemu-native-build.Dockerfile"
wasm_dockerfile="${repo_root}/docker/xemu-wasm-build.Dockerfile"
native_script="${repo_root}/scripts/docker-build-xemu.sh"
wasm_script="${repo_root}/scripts/docker-build-xemu-wasm.sh"
sysroot_script="${repo_root}/scripts/docker-build-wasm-sysroot.sh"

require_file() {
    local name="$1"
    local path="$2"

    if [ ! -f "${path}" ]; then
        printf 'DOCKER_BUILD_CHECK result=fail reason=missing-%s path=%s\n' \
            "${name}" "${path}" >&2
        exit 1
    fi
}

require_executable() {
    local name="$1"
    local path="$2"

    if [ ! -x "${path}" ]; then
        printf 'DOCKER_BUILD_CHECK result=fail reason=not-executable-%s path=%s\n' \
            "${name}" "${path}" >&2
        exit 1
    fi
}

require_pattern() {
    local name="$1"
    local pattern="$2"
    local file="$3"

    if ! grep -Eq -e "${pattern}" "${file}"; then
        printf 'DOCKER_BUILD_CHECK result=fail reason=missing-%s pattern=%s file=%s\n' \
            "${name}" "${pattern}" "${file}" >&2
        exit 1
    fi
}

require_file native-dockerfile "${native_dockerfile}"
require_file wasm-dockerfile "${wasm_dockerfile}"
require_file native-script "${native_script}"
require_file wasm-script "${wasm_script}"
require_file sysroot-script "${sysroot_script}"

require_executable native-script "${native_script}"
require_executable wasm-script "${wasm_script}"
require_executable sysroot-script "${sysroot_script}"

bash -n "${native_script}" "${wasm_script}" "${sysroot_script}"

require_pattern native-base '^FROM ubuntu:24\.04$' "${native_dockerfile}"
require_pattern native-meson 'meson==1\.9\.0' "${native_dockerfile}"
require_pattern native-ninja 'ninja-build' "${native_dockerfile}"
require_pattern native-i386 '--target-list=i386-softmmu' "${native_script}"
require_pattern native-vulkan-disabled '-Dvulkan=disabled' "${native_script}"

require_pattern wasm-base '^ARG EMSCRIPTEN_IMAGE=emscripten/emsdk:latest$' "${wasm_dockerfile}"
require_pattern wasm-i386 '--target-list=i386-softmmu' "${wasm_script}"
require_pattern wasm-tci '--enable-tcg-interpreter' "${wasm_script}"
require_pattern wasm-browser-boot '--enable-xemu-browser-boot' "${wasm_script}"
require_pattern wasm-vulkan-disabled '-Dvulkan=disabled' "${wasm_script}"
require_pattern wasm-sysroot-env 'XEMU_WASM_SYSROOT_DIR' "${wasm_script}"
require_pattern wasm-pkg-config 'PKG_CONFIG_LIBDIR=.*prefix' "${wasm_script}"

require_pattern sysroot-zlib 'XEMU_ZLIB_VERSION' "${sysroot_script}"
require_pattern sysroot-pcre2 'XEMU_PCRE2_VERSION' "${sysroot_script}"
require_pattern sysroot-libffi 'XEMU_LIBFFI_VERSION' "${sysroot_script}"
require_pattern sysroot-glib 'XEMU_GLIB_VERSION' "${sysroot_script}"
require_pattern sysroot-emscripten-cross 'emscripten-glib\.cross' "${sysroot_script}"
require_pattern sysroot-wasm32-host 'wasm32' "${sysroot_script}"

printf 'DOCKER_BUILD_CHECK result=pass native_dockerfile=%s wasm_dockerfile=%s scripts=3\n' \
    "${native_dockerfile}" "${wasm_dockerfile}"
