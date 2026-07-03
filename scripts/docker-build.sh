#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 [native|wasm|all] [-- <extra build args>]

Targets:
  native    Build the native Linux target in Docker
  wasm      Build the browser/WASM target in Docker
  all       Build native and WASM targets in Docker

Environment:
  XEMU_DOCKER                 Docker-compatible CLI to use, default: docker
  XEMU_NATIVE_JOBS            Native build parallelism
  XEMU_WASM_JOBS              WASM build parallelism
  XEMU_NATIVE_SKIP_IMAGE_BUILD=1
  XEMU_WASM_SKIP_IMAGE_BUILD=1
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
target="${1:-all}"
if [ "$#" -gt 0 ]; then
    shift
fi
if [ "${1:-}" = "--" ]; then
    shift
fi

case "${target}" in
    native)
        "${repo_root}/scripts/docker-build-native.sh" "$@"
        ;;
    wasm)
        "${repo_root}/scripts/docker-build-wasm-sysroot.sh"
        XEMU_WASM_SKIP_IMAGE_BUILD=1 "${repo_root}/scripts/docker-build-xemu-wasm.sh" "$@"
        "${repo_root}/scripts/xbox-verify-wasm-profile.sh" "${XEMU_WASM_BUILD_DIR:-build-wasm}"
        ;;
    all)
        if [ "$#" -gt 0 ]; then
            echo "Extra build arguments are supported for native or wasm targets, not all." >&2
            exit 2
        fi
        "${repo_root}/scripts/docker-build-native.sh" "$@"
        "${repo_root}/scripts/docker-build-wasm-sysroot.sh"
        XEMU_WASM_SKIP_IMAGE_BUILD=1 "${repo_root}/scripts/docker-build-xemu-wasm.sh"
        "${repo_root}/scripts/xbox-verify-wasm-profile.sh" "${XEMU_WASM_BUILD_DIR:-build-wasm}"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
