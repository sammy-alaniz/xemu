#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
image="${XEMU_DOCKER_IMAGE:-xemu-native-build:latest}"
build_dir="${XEMU_DOCKER_BUILD_DIR:-build-docker}"
target="${XEMU_DOCKER_TARGET:-qemu-system-i386}"
skip_image_build="${XEMU_DOCKER_SKIP_IMAGE_BUILD:-0}"

detect_jobs() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu
    else
        echo 4
    fi
}

jobs="${XEMU_DOCKER_JOBS:-$(detect_jobs)}"

if [ "${skip_image_build}" != "1" ]; then
    docker build \
        -f "${repo_root}/docker/xemu-native-build.Dockerfile" \
        -t "${image}" \
        "${repo_root}/docker"
fi

mkdir -p "${repo_root}/${build_dir}"

docker run --rm -t \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp/xemu-home \
    -e JOBS="${jobs}" \
    -e TARGET="${target}" \
    -e XEMU_DOCKER_RECONFIGURE="${XEMU_DOCKER_RECONFIGURE:-0}" \
    -v "${repo_root}:/workspace" \
    -w "/workspace/${build_dir}" \
    "${image}" \
    bash -lc '
        set -euo pipefail
        mkdir -p "${HOME}"

        if [ "${XEMU_DOCKER_RECONFIGURE}" = "1" ] || [ ! -f build.ninja ]; then
            ../configure \
                --extra-cflags="-DXBOX=1 -Wno-error=redundant-decls" \
                --target-list=i386-softmmu \
                --disable-werror \
                -Dvulkan=disabled \
                "$@"
        fi

        make -j"${JOBS}" "${TARGET}"
    ' xemu-docker-configure "$@"
