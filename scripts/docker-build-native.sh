#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
docker_cmd="${XEMU_DOCKER:-docker}"
image="${XEMU_NATIVE_DOCKER_IMAGE:-xemu-native-build:latest}"
skip_image_build="${XEMU_NATIVE_SKIP_IMAGE_BUILD:-0}"

detect_jobs() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu
    else
        echo 4
    fi
}

jobs="${XEMU_NATIVE_JOBS:-$(detect_jobs)}"

if [ "${skip_image_build}" != "1" ]; then
    "${docker_cmd}" build \
        -f "${repo_root}/docker/xemu-native-build.Dockerfile" \
        -t "${image}" \
        "${repo_root}/docker"
fi

"${docker_cmd}" run --rm -t \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp/xemu-home \
    -e JOBS="${jobs}" \
    -e CCACHE_DIR=/workspace/.ccache \
    -v "${repo_root}:/workspace" \
    -w /workspace \
    "${image}" \
    bash -lc '
        set -euo pipefail
        mkdir -p "${HOME}" "${CCACHE_DIR:-/workspace/.ccache}"
        ./build.sh -j"${JOBS}" "$@"
    ' xemu-native-build "$@"
