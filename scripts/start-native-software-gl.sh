#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

xemu_bin="${XEMU_NATIVE_BIN:-${repo_root}/dist/xemu}"

if [[ ! -x "${xemu_bin}" ]]; then
    echo "error: native xemu binary is not executable: ${xemu_bin}" >&2
    echo "Set XEMU_NATIVE_BIN=/path/to/xemu to use a different binary." >&2
    exit 1
fi

# Some local packaged builds expect the older libpcap.so.0.8 soname while the
# host provides libpcap.so.1. Keep that compatibility symlink outside the repo.
ldd_output="$(ldd "${xemu_bin}" 2>/dev/null || true)"
if grep -q 'libpcap\.so\.0\.8 => not found' <<<"${ldd_output}"; then
    lib_shim_dir="${XEMU_NATIVE_LIB_SHIM_DIR:-/tmp/xemu-native-libs}"
    mkdir -p "${lib_shim_dir}"

    if [[ ! -e "${lib_shim_dir}/libpcap.so.0.8" ]]; then
        for candidate in \
            /usr/lib64/libpcap.so.1 \
            /usr/lib/libpcap.so.1 \
            /lib64/libpcap.so.1 \
            /lib/libpcap.so.1; do
            if [[ -e "${candidate}" ]]; then
                ln -s "${candidate}" "${lib_shim_dir}/libpcap.so.0.8"
                break
            fi
        done
    fi

    if [[ ! -e "${lib_shim_dir}/libpcap.so.0.8" ]]; then
        echo "error: ${xemu_bin} needs libpcap.so.0.8, but no compatible libpcap.so.1 was found." >&2
        exit 1
    fi

    export LD_LIBRARY_PATH="${lib_shim_dir}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi

export LIBGL_ALWAYS_SOFTWARE=1
export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
export GALLIUM_DRIVER=llvmpipe

echo "Starting native xemu with software GL: ${xemu_bin}" >&2
exec "${xemu_bin}" "$@"
