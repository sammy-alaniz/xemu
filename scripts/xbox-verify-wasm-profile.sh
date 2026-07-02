#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-verify-wasm-profile.sh [build-dir]

Verifies that a reduced browser-boot wasm build is configured for the Xbox
headless/null boot profile and does not compile desktop UI or GL/Vulkan renderer
sources. Default build-dir: build-wasm-pic.

The script inspects build artifacts only; it does not rebuild.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
build_dir="${1:-${repo_root}/build-wasm-pic}"
case "${build_dir}" in
    /*) ;;
    *) build_dir="${repo_root}/${build_dir}" ;;
esac

compile_commands="${build_dir}/compile_commands.json"
meson_log="${build_dir}/meson-logs/meson-log.txt"
config_host="${build_dir}/config-host.h"
config_log="${build_dir}/config.log"
wasm_artifact="${build_dir}/qemu-system-i386.wasm"
js_artifact="${build_dir}/qemu-system-i386.js"

require_file() {
    local name="$1"
    local path="$2"

    if [ ! -f "${path}" ]; then
        printf 'WASM_PROFILE_CHECK result=fail reason=missing-%s path=%s\n' \
            "${name}" "${path}" >&2
        exit 1
    fi
}

require_pattern() {
    local name="$1"
    local pattern="$2"
    local file="$3"

    if ! grep -Eq -e "${pattern}" "${file}"; then
        printf 'WASM_PROFILE_CHECK result=fail reason=missing-%s pattern=%s file=%s\n' \
            "${name}" "${pattern}" "${file}" >&2
        exit 1
    fi
}

forbid_pattern() {
    local name="$1"
    local pattern="$2"
    local file="$3"

    if grep -Eq -e "${pattern}" "${file}"; then
        printf 'WASM_PROFILE_CHECK result=fail reason=forbidden-%s pattern=%s file=%s\n' \
            "${name}" "${pattern}" "${file}" >&2
        grep -En -e "${pattern}" "${file}" | head -20 >&2
        exit 1
    fi
}

require_file "compile-commands" "${compile_commands}"
require_file "meson-log" "${meson_log}"
require_file "config-host" "${config_host}"
require_file "config-log" "${config_log}"
require_file "wasm-artifact" "${wasm_artifact}"
require_file "js-artifact" "${js_artifact}"

require_pattern "browser-boot-option" 'xemu_browser_boot[[:space:]]*:[[:space:]]*true' "${meson_log}"
require_pattern "tci-config" '^#define CONFIG_TCG_INTERPRETER' "${config_host}"
require_pattern "pcap-disabled" '^#undef CONFIG_PCAP' "${config_host}"
require_pattern "i386-target" '--target-list=i386-softmmu' "${config_log}"
require_pattern "headless-entry" 'ui/xemu-headless\.c' "${compile_commands}"
require_pattern "null-renderer" 'hw/xbox/nv2a/pgraph/null/renderer\.c' "${compile_commands}"
require_pattern "xbox-machine" 'hw/xbox/xbox\.c' "${compile_commands}"
require_pattern "ide-core" 'hw/ide/core\.c' "${compile_commands}"

forbid_pattern "desktop-xemu-ui" '(^|[/" ])ui/xemu\.c([", ]|$)' "${compile_commands}"
forbid_pattern "xui" '(^|[/" ])ui/xui/' "${compile_commands}"
forbid_pattern "desktop-gl-renderer" 'hw/xbox/nv2a/pgraph/gl/' "${compile_commands}"
forbid_pattern "desktop-vk-renderer" 'hw/xbox/nv2a/pgraph/vk/' "${compile_commands}"
forbid_pattern "desktop-glsl-renderer" 'hw/xbox/nv2a/pgraph/glsl/' "${compile_commands}"
forbid_pattern "sdl" '(^|[/" ])ui/sdl|/SDL2\.framework|[^A-Za-z]sdl2?[^A-Za-z]' "${compile_commands}"
forbid_pattern "imgui" 'imgui|implot' "${compile_commands}"
forbid_pattern "samplerate" 'samplerate' "${compile_commands}"

wasm_size="$(wc -c < "${wasm_artifact}" | tr -d '[:space:]')"
js_size="$(wc -c < "${js_artifact}" | tr -d '[:space:]')"
compiled_sources="$(grep -c '"file":' "${compile_commands}")"

printf 'WASM_PROFILE_CHECK result=pass build_dir=%s compiled_sources=%s wasm_bytes=%s js_bytes=%s\n' \
    "${build_dir}" "${compiled_sources}" "${wasm_size}" "${js_size}"
