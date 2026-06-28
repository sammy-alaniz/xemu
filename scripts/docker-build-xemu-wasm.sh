#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
image="${XEMU_WASM_DOCKER_IMAGE:-xemu-wasm-build:latest}"
build_dir="${XEMU_WASM_BUILD_DIR:-build-wasm}"
sysroot_dir="${XEMU_WASM_SYSROOT_DIR:-build-wasm-sysroot}"
target="${XEMU_WASM_TARGET:-qemu-system-i386.js}"
skip_image_build="${XEMU_WASM_SKIP_IMAGE_BUILD:-0}"

detect_jobs() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu
    else
        echo 4
    fi
}

jobs="${XEMU_WASM_JOBS:-$(detect_jobs)}"

if [ "${skip_image_build}" != "1" ]; then
    docker build \
        -f "${repo_root}/docker/xemu-wasm-build.Dockerfile" \
        -t "${image}" \
        "${repo_root}/docker"
fi

mkdir -p "${repo_root}/${build_dir}"

docker run --rm -t \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp/xemu-home \
    -e JOBS="${jobs}" \
    -e TARGET="${target}" \
    -e XEMU_WASM_RECONFIGURE="${XEMU_WASM_RECONFIGURE:-0}" \
    -e XEMU_WASM_SYSROOT_DIR="${sysroot_dir}" \
    -v "${repo_root}:/workspace" \
    -w "/workspace/${build_dir}" \
    "${image}" \
    bash -lc '
        set -euo pipefail
        mkdir -p "${HOME}"
        prefix="/workspace/${XEMU_WASM_SYSROOT_DIR}/prefix"
        export PKG_CONFIG_LIBDIR="${prefix}/lib/pkgconfig:${prefix}/share/pkgconfig"
        export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"
        export EM_PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"
        export PKG_CONFIG="${PKG_CONFIG:-pkg-config}"
        export CFLAGS="${CFLAGS:-} -pthread -fPIC"
        export CXXFLAGS="${CXXFLAGS:-} -pthread -fPIC"
        export LDFLAGS="${LDFLAGS:-} -pthread"

        if [ "${XEMU_WASM_RECONFIGURE}" = "1" ] || [ ! -f build.ninja ]; then
            ../configure \
                --cross-prefix=em \
                --cc=emcc \
                --cxx=em++ \
                --extra-cflags=-fPIC \
                --extra-cxxflags=-fPIC \
                --static \
                --target-list=i386-softmmu \
                --enable-tcg-interpreter \
                --disable-werror \
                --disable-gio \
                --disable-curl \
                --disable-modules \
                --disable-plugins \
                -Dvulkan=disabled \
                --enable-xemu-browser-boot \
                "$@"
        fi

        make -j"${JOBS}" "${TARGET}"

        if [ -f "${TARGET}" ]; then
            perl -0pi -e "s/rtn\\.then\\(\\(rtn\\) => __emscripten_run_js_on_main_thread_done\\(ctx, ctxArgs, rtn\\)\\);/Promise.resolve(rtn).then((rtn) => __emscripten_run_js_on_main_thread_done(ctx, ctxArgs, rtn));/" "${TARGET}"
        fi
    ' xemu-wasm-configure "$@"
