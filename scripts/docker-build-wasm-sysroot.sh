#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
image="${XEMU_WASM_DOCKER_IMAGE:-xemu-wasm-build:latest}"
skip_image_build="${XEMU_WASM_SKIP_IMAGE_BUILD:-0}"
sysroot_dir="${XEMU_WASM_SYSROOT_DIR:-build-wasm-sysroot}"

if [ "${skip_image_build}" != "1" ]; then
    docker build \
        -f "${repo_root}/docker/xemu-wasm-build.Dockerfile" \
        -t "${image}" \
        "${repo_root}/docker"
fi

mkdir -p "${repo_root}/${sysroot_dir}"

docker run --rm -t \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp/xemu-home \
    -e XEMU_GLIB_VERSION="${XEMU_GLIB_VERSION:-2.80.0}" \
    -e XEMU_WASM_GLIB_MINIMAL="${XEMU_WASM_GLIB_MINIMAL:-1}" \
    -e XEMU_LIBFFI_VERSION="${XEMU_LIBFFI_VERSION:-3.4.6}" \
    -e XEMU_PCRE2_VERSION="${XEMU_PCRE2_VERSION:-10.43}" \
    -e XEMU_ZLIB_VERSION="${XEMU_ZLIB_VERSION:-1.3.1}" \
    -v "${repo_root}:/workspace" \
    -w "/workspace/${sysroot_dir}" \
    "${image}" \
    bash -lc '
        set -euo pipefail

        mkdir -p "${HOME}" src build prefix pkgconfig
        prefix="/workspace/'"${sysroot_dir}"'/prefix"
        export PKG_CONFIG_LIBDIR="${prefix}/lib/pkgconfig:${prefix}/share/pkgconfig"
        export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"
        export EM_PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"
        export CFLAGS="${CFLAGS:-} -pthread"
        export CXXFLAGS="${CXXFLAGS:-} -pthread"
        export LDFLAGS="${LDFLAGS:-} -pthread"

        python3 -m venv --system-site-packages pyvenv
        pyvenv/bin/pip install --no-index --find-links=/workspace/python/wheels meson==1.9.0 >/dev/null
        meson_bin="${PWD}/pyvenv/bin/meson"

        zlib_archive="zlib-${XEMU_ZLIB_VERSION}.tar.gz"
        if [ ! -f "src/${zlib_archive}" ]; then
            curl -fL "https://zlib.net/fossils/${zlib_archive}" -o "src/${zlib_archive}"
        fi
        if [ ! -d "src/zlib-${XEMU_ZLIB_VERSION}" ]; then
            tar -xf "src/${zlib_archive}" -C src
        fi

        if [ ! -f "${prefix}/share/pkgconfig/zlib.pc" ]; then
            rm -rf build/zlib
            emcmake cmake -S "src/zlib-${XEMU_ZLIB_VERSION}" -B build/zlib \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_INSTALL_PREFIX="${prefix}" \
                -DBUILD_SHARED_LIBS=OFF
            cmake --build build/zlib --target install --parallel "${JOBS:-4}"
        fi
        if [ -f "${prefix}/lib/libz.a" ]; then
            sed -i "s|^Libs:.*|Libs: ${prefix}/lib/libz.a|" "${prefix}/share/pkgconfig/zlib.pc"
        fi

        pcre2_archive="pcre2-${XEMU_PCRE2_VERSION}.tar.gz"
        if [ ! -f "src/${pcre2_archive}" ]; then
            curl -fL "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${XEMU_PCRE2_VERSION}/${pcre2_archive}" \
                -o "src/${pcre2_archive}"
        fi
        if [ ! -d "src/pcre2-${XEMU_PCRE2_VERSION}" ]; then
            tar -xf "src/${pcre2_archive}" -C src
        fi

        if [ ! -f "${prefix}/lib/pkgconfig/libpcre2-8.pc" ]; then
            rm -rf build/pcre2
            emcmake cmake -S "src/pcre2-${XEMU_PCRE2_VERSION}" -B build/pcre2 \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_INSTALL_PREFIX="${prefix}" \
                -DBUILD_SHARED_LIBS=OFF \
                -DPCRE2_BUILD_PCRE2_8=ON \
                -DPCRE2_BUILD_PCRE2_16=OFF \
                -DPCRE2_BUILD_PCRE2_32=OFF \
                -DPCRE2_BUILD_PCRE2GREP=OFF \
                -DPCRE2_BUILD_TESTS=OFF \
                -DPCRE2_SUPPORT_JIT=OFF
            cmake --build build/pcre2 --target install --parallel "${JOBS:-4}"
        fi

        libffi_archive="libffi-${XEMU_LIBFFI_VERSION}.tar.gz"
        if [ ! -f "src/${libffi_archive}" ]; then
            curl -fL "https://github.com/libffi/libffi/releases/download/v${XEMU_LIBFFI_VERSION}/${libffi_archive}" \
                -o "src/${libffi_archive}"
        fi
        if [ ! -d "src/libffi-${XEMU_LIBFFI_VERSION}" ]; then
            tar -xf "src/${libffi_archive}" -C src
        fi
        if [ ! -f "src/libffi-${XEMU_LIBFFI_VERSION}/.xemu-emscripten-6-helpers" ]; then
            (
                cd "src/libffi-${XEMU_LIBFFI_VERSION}"
                patch -p1 < /workspace/patches/libffi-3.4.6-emscripten-6-helpers.patch
                touch .xemu-emscripten-6-helpers
            )
        fi
        if [ ! -f "${prefix}/.xemu-libffi-emscripten-6-helpers" ]; then
            rm -f "${prefix}/lib/pkgconfig/libffi.pc"
        fi

        if [ ! -f "${prefix}/lib/pkgconfig/libffi.pc" ]; then
            rm -rf build/libffi
            mkdir -p build/libffi
            (
                cd build/libffi
                emconfigure ../../src/libffi-${XEMU_LIBFFI_VERSION}/configure \
                    --host=wasm32-unknown-emscripten \
                    --prefix="${prefix}" \
                    --disable-shared \
                    --enable-static \
                    --disable-docs
                emmake make -j"${JOBS:-4}"
                emmake make install
                touch "${prefix}/.xemu-libffi-emscripten-6-helpers"
            )
        fi

        glib_minor="${XEMU_GLIB_VERSION%.*}"
        glib_archive="glib-${XEMU_GLIB_VERSION}.tar.xz"
        if [ ! -f "src/${glib_archive}" ]; then
            curl -fL "https://download.gnome.org/sources/glib/${glib_minor}/${glib_archive}" \
                -o "src/${glib_archive}"
        fi
        if [ ! -d "src/glib-${XEMU_GLIB_VERSION}" ]; then
            tar -xf "src/${glib_archive}" -C src
        fi
        if [ ! -f "src/glib-${XEMU_GLIB_VERSION}/.xemu-emscripten-no-res-query" ]; then
            (
                cd "src/glib-${XEMU_GLIB_VERSION}"
                patch -p1 < /workspace/patches/glib-2.80.0-emscripten-no-res-query.patch
                touch .xemu-emscripten-no-res-query
            )
        fi
        if [ ! -f "src/glib-${XEMU_GLIB_VERSION}/.xemu-emscripten-no-posix-spawn" ]; then
            (
                cd "src/glib-${XEMU_GLIB_VERSION}"
                patch -p1 < /workspace/patches/glib-2.80.0-emscripten-no-posix-spawn.patch
                touch .xemu-emscripten-no-posix-spawn
            )
        fi

        {
            printf "%s\n" "[binaries]"
            printf "c = \047emcc\047\n"
            printf "cpp = \047em++\047\n"
            printf "ar = \047emar\047\n"
            printf "strip = \047emstrip\047\n"
            printf "pkg-config = \047pkg-config\047\n"
            printf "%s\n" ""
            printf "%s\n" "[host_machine]"
            printf "system = \047emscripten\047\n"
            printf "cpu_family = \047wasm32\047\n"
            printf "cpu = \047wasm32\047\n"
            printf "endian = \047little\047\n"
            printf "%s\n" ""
            printf "%s\n" "[built-in options]"
            printf "c_args = [\047-pthread\047, \047-Wno-error=incompatible-function-pointer-types\047, \047-Wno-error=incompatible-pointer-types\047]\n"
            printf "c_link_args = [\047-pthread\047]\n"
            printf "%s\n" ""
            printf "%s\n" "[properties]"
            printf "%s\n" "needs_exe_wrapper = true"
        } > emscripten-glib.cross

        if [ ! -f "${prefix}/lib/pkgconfig/glib-2.0.pc" ] || [ ! -f "${prefix}/include/glib-2.0/glib.h" ] || [ ! -f "${prefix}/include/glib-2.0/glib-unix.h" ] || [ ! -f "${prefix}/include/glib-2.0/glib/deprecated/gallocator.h" ]; then
            rm -rf build/glib
            "${meson_bin}" setup build/glib "src/glib-${XEMU_GLIB_VERSION}" \
                --cross-file emscripten-glib.cross \
                --prefix "${prefix}" \
                --pkg-config-path "${PKG_CONFIG_LIBDIR}" \
                --wrap-mode=nodownload \
                -Ddefault_library=static \
                -Dtests=false \
                -Dinstalled_tests=false \
                -Dintrospection=disabled \
                -Dlibmount=disabled \
                -Dselinux=disabled \
                -Dxattr=false \
                -Dman-pages=disabled \
                -Dgtk_doc=false \
                -Dnls=disabled
            if [ "${XEMU_WASM_GLIB_MINIMAL}" = "1" ]; then
                ninja -C build/glib \
                    glib/libglib-2.0.a \
                    gmodule/libgmodule-2.0.a \
                    gthread/libgthread-2.0.a

                mkdir -p \
                    "${prefix}/include/glib-2.0/glib" \
                    "${prefix}/include/glib-2.0/gmodule" \
                    "${prefix}/lib/glib-2.0/include" \
                    "${prefix}/lib/pkgconfig"

                cp src/glib-${XEMU_GLIB_VERSION}/glib/*.h "${prefix}/include/glib-2.0/glib/"
                cp -R src/glib-${XEMU_GLIB_VERSION}/glib/deprecated "${prefix}/include/glib-2.0/glib/"
                cp src/glib-${XEMU_GLIB_VERSION}/glib/glib.h "${prefix}/include/glib-2.0/"
                cp src/glib-${XEMU_GLIB_VERSION}/glib/glib-unix.h "${prefix}/include/glib-2.0/"
                cp build/glib/glib/gversionmacros.h "${prefix}/include/glib-2.0/glib/"
                cp build/glib/glib/glib-visibility.h "${prefix}/include/glib-2.0/glib/"
                cp build/glib/glib/glibconfig.h "${prefix}/lib/glib-2.0/include/"
                cp src/glib-${XEMU_GLIB_VERSION}/gmodule/gmodule.h "${prefix}/include/glib-2.0/gmodule/"
                cp src/glib-${XEMU_GLIB_VERSION}/gmodule/gmodule.h "${prefix}/include/glib-2.0/"
                cp build/glib/gmodule/gmoduleconf.h "${prefix}/include/glib-2.0/gmodule/"
                cp build/glib/gmodule/gmodule-visibility.h "${prefix}/include/glib-2.0/gmodule/"
                cp build/glib/gmodule/gmoduleconf.h "${prefix}/include/glib-2.0/"
                cp build/glib/gmodule/gmodule-visibility.h "${prefix}/include/glib-2.0/"

                cp build/glib/glib/libglib-2.0.a "${prefix}/lib/"
                cp build/glib/gmodule/libgmodule-2.0.a "${prefix}/lib/"
                cp build/glib/gthread/libgthread-2.0.a "${prefix}/lib/"
                cp build/glib/meson-private/glib-2.0.pc "${prefix}/lib/pkgconfig/"
                cp build/glib/meson-private/gmodule-no-export-2.0.pc "${prefix}/lib/pkgconfig/"
                cp build/glib/meson-private/gthread-2.0.pc "${prefix}/lib/pkgconfig/"
            else
                "${meson_bin}" compile -C build/glib
                "${meson_bin}" install -C build/glib
            fi
        fi

        test -f "${prefix}/lib/pkgconfig/glib-2.0.pc"
        test -f "${prefix}/lib/pkgconfig/gmodule-no-export-2.0.pc"
        test -f "${prefix}/lib/pkgconfig/gthread-2.0.pc"
        pkg-config --modversion glib-2.0
    '
