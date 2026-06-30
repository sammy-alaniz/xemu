#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-boot-smoke.sh [native-headless|docker-headless|wasm-node-headless]

Runs a headless Xbox boot smoke test and reports the highest observed boot
milestone from BOOT_MARK logs.

Required fixture:
  XEMU_FLASH       Path to Xbox flash/BIOS image.

Optional fixtures:
  XEMU_MCPX        Path to MCPX boot ROM. Must be exactly 512 bytes.
  XEMU_EEPROM      Path to EEPROM image. Must be exactly 256 bytes.
                  If omitted, a zero-filled temporary EEPROM is created.
  XEMU_HDD         Path to Xbox HDD image.
  XEMU_DVD         Path to optional DVD image.

Optional controls:
  XEMU_SMOKE_BINARY         Native binary path. Default: build/qemu-system-i386.
  XEMU_SMOKE_DOCKER_IMAGE   Docker image. Default: xemu-native-build:latest.
  XEMU_SMOKE_BUILD_DIR      Docker build dir. Default: build-docker.
  XEMU_SMOKE_WASM_IMAGE     Wasm Docker image. Default: xemu-wasm-build:latest.
  XEMU_SMOKE_WASM_BUILD_DIR Wasm build dir. Default: build-wasm-pic.
  XEMU_SMOKE_OUT_DIR        Output dir. Default: build-docker/boot-smoke.
  XEMU_SMOKE_MS             Timeout ms. Default: 3000.
  XEMU_SMOKE_EXPECT_LEVEL   Expected minimum B-level. Default: B0.
  XEMU_SMOKE_SKIP_BOOT_ANIM Set to 1 to request the Xbox short boot animation.
  XEMU_HEADLESS_BOOT_GRAPHIC_UPDATE
                            Set to 1 to pump native headless graphic updates.
  XEMU_BOOT_TRACE_XBE_*     Optional B6 XBE diagnostic limits/controls.
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
mode="${1:-docker-headless}"
out_dir="${XEMU_SMOKE_OUT_DIR:-${repo_root}/build-docker/boot-smoke}"
case "${out_dir}" in
    /*) ;;
    *) out_dir="${repo_root}/${out_dir}" ;;
esac
timeout_ms="${XEMU_SMOKE_MS:-3000}"
expect_level="${XEMU_SMOKE_EXPECT_LEVEL:-B0}"
skip_boot_anim="${XEMU_SMOKE_SKIP_BOOT_ANIM:-0}"
expected_value=""
docker_image="${XEMU_SMOKE_DOCKER_IMAGE:-xemu-native-build:latest}"
docker_build_dir="${XEMU_SMOKE_BUILD_DIR:-build-docker}"
wasm_image="${XEMU_SMOKE_WASM_IMAGE:-xemu-wasm-build:latest}"
wasm_build_dir="${XEMU_SMOKE_WASM_BUILD_DIR:-build-wasm-pic}"
native_binary="${XEMU_SMOKE_BINARY:-${repo_root}/build/qemu-system-i386}"
log_path="${out_dir}/boot-smoke.log"
config_path="${out_dir}/xemu-smoke.toml"
generated_eeprom="${out_dir}/eeprom.generated.bin"

case "${mode}" in
    native-headless|docker-headless|wasm-node-headless)
        ;;
    -h|--help|help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

level_value() {
    case "$1" in
        B0|b0) echo 0 ;;
        B1|b1) echo 1 ;;
        B2|b2) echo 2 ;;
        B3|b3) echo 3 ;;
        B4|b4) echo 4 ;;
        B5|b5) echo 5 ;;
        B6|b6) echo 6 ;;
        *)
            echo "Unknown boot level '$1'" >&2
            exit 2
            ;;
    esac
}

file_size() {
    wc -c < "$1" | tr -d '[:space:]'
}

require_file() {
    local name="$1"
    local path="$2"

    if [ -z "${path}" ]; then
        echo "${name} is required" >&2
        exit 2
    fi

    if [ ! -f "${path}" ]; then
        echo "${name} does not exist: ${path}" >&2
        exit 2
    fi
}

validate_exact_size() {
    local name="$1"
    local path="$2"
    local expected="$3"
    local actual

    actual="$(file_size "${path}")"
    if [ "${actual}" != "${expected}" ]; then
        echo "${name} must be ${expected} bytes, got ${actual}: ${path}" >&2
        exit 2
    fi
}

has_structured_b3_hdd_marker() {
    grep -Eq '^BOOT_MARK b3 ide=hdd first_read_lba=[0-9]+ nsectors=[0-9]+ method=(pio|dma) unit=[0-9]+ total_sectors=[0-9]+' "$1"
}

has_browser_block_b3_hdd_marker() {
    grep -Eq '^BOOT_MARK b3 browser_block=read ' "$1"
}

has_b3_hdd_marker() {
    has_structured_b3_hdd_marker "$1" || has_browser_block_b3_hdd_marker "$1"
}

marker_count_for_level() {
    local log="$1"
    local level="$2"

    grep -c "^BOOT_MARK ${level}" "${log}" || true
}

smoke_elapsed_ms() {
    sed -n 's/^BOOT_SMOKE_RESULT .*elapsed_ms=\([0-9][0-9]*\).*/\1/p' "$1" | tail -n 1
}

marker_rate_per_sec() {
    local markers="$1"
    local elapsed_ms="$2"

    awk -v markers="${markers}" -v elapsed_ms="${elapsed_ms}" \
        'BEGIN {
            if (elapsed_ms > 0) {
                printf "%.2f", markers * 1000.0 / elapsed_ms;
            } else {
                printf "0.00";
            }
        }'
}

toml_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

expected_value="$(level_value "${expect_level}")"
case "${skip_boot_anim}" in
    0|false|False|FALSE|no|No|NO)
        skip_boot_anim_config="false"
        ;;
    1|true|True|TRUE|yes|Yes|YES)
        skip_boot_anim_config="true"
        ;;
    *)
        echo "XEMU_SMOKE_SKIP_BOOT_ANIM must be 0 or 1, got: ${skip_boot_anim}" >&2
        exit 2
        ;;
esac

mkdir -p "${out_dir}"
rm -f "${log_path}"

require_file "XEMU_FLASH" "${XEMU_FLASH:-}"

if [ -n "${XEMU_MCPX:-}" ]; then
    require_file "XEMU_MCPX" "${XEMU_MCPX}"
    validate_exact_size "XEMU_MCPX" "${XEMU_MCPX}" 512
fi

if [ -n "${XEMU_EEPROM:-}" ]; then
    require_file "XEMU_EEPROM" "${XEMU_EEPROM}"
    validate_exact_size "XEMU_EEPROM" "${XEMU_EEPROM}" 256
    eeprom_path="${XEMU_EEPROM}"
else
    if [ ! -f "${generated_eeprom}" ]; then
        dd if=/dev/zero of="${generated_eeprom}" bs=256 count=1 status=none
    fi
    eeprom_path="${generated_eeprom}"
fi

if [ -n "${XEMU_HDD:-}" ]; then
    require_file "XEMU_HDD" "${XEMU_HDD}"
elif [ "${expected_value}" -ge 3 ]; then
    echo "XEMU_HDD is required when XEMU_SMOKE_EXPECT_LEVEL is B3 or higher" >&2
    exit 2
fi

if [ -n "${XEMU_DVD:-}" ]; then
    require_file "XEMU_DVD" "${XEMU_DVD}"
fi

config_bootrom_path="${XEMU_MCPX:-}"
config_flashrom_path="${XEMU_FLASH}"
config_eeprom_path="${eeprom_path}"
config_hdd_path="${XEMU_HDD:-}"
config_dvd_path="${XEMU_DVD:-}"

if [ "${mode}" = "docker-headless" ] || [ "${mode}" = "wasm-node-headless" ]; then
    config_bootrom_path=""
    if [ -n "${XEMU_MCPX:-}" ]; then
        config_bootrom_path="/xemu-fixtures/mcpx.bin"
    fi
    config_flashrom_path="/xemu-fixtures/flash.bin"
    config_eeprom_path="/xemu-fixtures/eeprom.bin"
    config_hdd_path=""
    if [ -n "${XEMU_HDD:-}" ]; then
        config_hdd_path="/xemu-fixtures/xbox_hdd.img"
    fi
    config_dvd_path=""
    if [ -n "${XEMU_DVD:-}" ]; then
        config_dvd_path="/xemu-fixtures/dvd.iso"
    fi
fi

cat > "${config_path}" <<EOF
[general]
show_welcome = false
skip_boot_anim = ${skip_boot_anim_config}

[general.updates]
check = false

[display]
renderer = "NULL"

[sys]
mem_limit = "64"
avpack = "hdtv"

[sys.files]
bootrom_path = "$(toml_escape "${config_bootrom_path}")"
flashrom_path = "$(toml_escape "${config_flashrom_path}")"
eeprom_path = "$(toml_escape "${config_eeprom_path}")"
hdd_path = "$(toml_escape "${config_hdd_path}")"
dvd_path = "$(toml_escape "${config_dvd_path}")"

[net]
enable = false
EOF

run_native() {
    if [ ! -x "${native_binary}" ]; then
        echo "Native binary is not executable: ${native_binary}" >&2
        echo "Set XEMU_SMOKE_BINARY or run scripts/docker-build-xemu.sh first." >&2
        exit 2
    fi

    XEMU_HEADLESS_BOOT=1 \
    XEMU_BOOT_TRACE=1 \
    XEMU_HEADLESS_BOOT_MS="${timeout_ms}" \
    XEMU_BOOT_TRACE_CONTEXT=native-headless \
        "${native_binary}" \
            -config_path "${config_path}"
}

run_docker() {
    local container_config="/xemu-smoke-out/$(basename "${config_path}")"
    local container_workdir="/workspace/${docker_build_dir}"
    local docker_args=(
        docker run --rm -t
        --user "$(id -u):$(id -g)"
        -e HOME=/tmp/xemu-home
        -e XEMU_HEADLESS_BOOT=1
        -e XEMU_BOOT_TRACE=1
        -e XEMU_BOOT_TRACE_CONTEXT=native-headless
        -e XEMU_HEADLESS_BOOT_MS="${timeout_ms}"
        -v "${repo_root}:/workspace"
        -v "${out_dir}:/xemu-smoke-out"
        -v "${XEMU_FLASH}:/xemu-fixtures/flash.bin:ro"
        -v "${eeprom_path}:/xemu-fixtures/eeprom.bin"
    )
    local trace_env

    for trace_env in \
        XEMU_HEADLESS_BOOT_GRAPHIC_UPDATE \
        XEMU_HEADLESS_BOOT_GRAPHIC_UPDATE_INTERVAL_US; do
        if [ -n "${!trace_env:-}" ]; then
            docker_args+=(-e "${trace_env}=${!trace_env}")
        fi
    done

    for trace_env in \
        XEMU_BOOT_TRACE_DMA_LIMIT \
        XEMU_BOOT_TRACE_IDE_READ_LIMIT \
        XEMU_BOOT_TRACE_BMDMA_LIMIT \
        XEMU_BOOT_TRACE_XBE_DMA_LIMIT \
        XEMU_BOOT_TRACE_XBE_PHYS_SCAN \
        XEMU_BOOT_TRACE_XBE_PHYS_SCAN_BYTES \
        XEMU_BOOT_TRACE_XBE_VIRTUAL_PROBE_LIMIT \
        XEMU_BOOT_TRACE_XBE_READ_PROGRESS_LIMIT \
        XEMU_BOOT_TRACE_XBE_EXEC_PROBE_LIMIT \
        XEMU_BOOT_TRACE_XBE_PHYS_COMPARE_LIMIT \
        XEMU_BOOT_TRACE_XBE_EXEC_EDGE_LIMIT \
        XEMU_BOOT_TRACE_XBE_ENTRY_TARGET_LIMIT \
        XEMU_BOOT_TRACE_XBE_ENTRY_TARGET_WINDOW \
        XEMU_BOOT_TRACE_XBE_DISPATCH_LIMIT \
        XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT \
        XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT \
        XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_MIN_HITS \
        XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS \
        XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT \
        XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS \
        XEMU_BOOT_TRACE_XBE_EXEC_PROBE_STRIDE \
        XEMU_BOOT_TRACE_XBE_PIC_IRQ_LIMIT \
        XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT \
        XEMU_BOOT_TRACE_XBE_IRET_LIMIT \
        XEMU_BOOT_TRACE_XBE_PIT_IRQ_LIMIT \
        XEMU_BOOT_TRACE_XBE_MAIN_LOOP_TIMER_LIMIT \
        XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL \
        XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE \
        XEMU_BOOT_TRACE_XBE_IDLE_BEFORE_PFIFO_TRANSITION_LIMIT \
        XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY \
        XEMU_BOOT_TRACE_XBE_IRQ_WATCH \
        XEMU_BOOT_TRACE_NV2A_PMC_LIMIT \
        XEMU_BOOT_TRACE_NV2A_IRQ_LIMIT \
        XEMU_BOOT_TRACE_NV2A_IRQ_LINE_LIMIT \
        XEMU_BOOT_TRACE_NV2A_IRQ_LINE_LOW_PRIORITY_LIMIT \
        XEMU_BOOT_TRACE_NV2A_IRQ_LINE_PCRTC_LIMIT \
        XEMU_BOOT_TRACE_NV2A_PFIFO_LIMIT \
        XEMU_BOOT_TRACE_NV2A_PFIFO_WINDOW_START \
        XEMU_BOOT_TRACE_NV2A_PFIFO_WINDOW_LIMIT \
        XEMU_BOOT_TRACE_NV2A_PGRAPH_METHOD_LIMIT \
        XEMU_BOOT_TRACE_NV2A_PGRAPH_METHOD_WINDOW_START \
        XEMU_BOOT_TRACE_NV2A_PGRAPH_METHOD_WINDOW_LIMIT \
        XEMU_BOOT_TRACE_NV2A_PGRAPH_NOTIFY_LIMIT \
        XEMU_BOOT_TRACE_NV2A_PGRAPH_NOTIFY_CLEAR_LIMIT; do
        if [ -n "${!trace_env:-}" ]; then
            docker_args+=(-e "${trace_env}=${!trace_env}")
        fi
    done

    if [ ! -x "${repo_root}/${docker_build_dir}/qemu-system-i386" ]; then
        echo "Docker-built binary is missing: ${repo_root}/${docker_build_dir}/qemu-system-i386" >&2
        echo "Run scripts/docker-build-xemu.sh first." >&2
        exit 2
    fi

    if [ -n "${XEMU_MCPX:-}" ]; then
        docker_args+=(-v "${XEMU_MCPX}:/xemu-fixtures/mcpx.bin:ro")
    fi
    if [ -n "${XEMU_HDD:-}" ]; then
        docker_args+=(-v "${XEMU_HDD}:/xemu-fixtures/xbox_hdd.img")
    fi
    if [ -n "${XEMU_DVD:-}" ]; then
        docker_args+=(-v "${XEMU_DVD}:/xemu-fixtures/dvd.iso:ro")
    fi

    docker_args+=(
        -w "${container_workdir}"
        "${docker_image}"
        ./qemu-system-i386 -config_path "${container_config}"
    )

    "${docker_args[@]}"
}

run_wasm_node() {
    if [ "${expected_value}" -ge 3 ] && [ -n "${XEMU_HDD:-}" ]; then
        local delegate_out="${out_dir}/browser-block"
        local delegate_summary="${out_dir}/browser-block-summary.log"
        local delegate_status

        set +e
        XEMU_BROWSER_BLOCK_OUT_DIR="${delegate_out}" \
        XEMU_BROWSER_BLOCK_MS="${timeout_ms}" \
        XEMU_SMOKE_WASM_IMAGE="${wasm_image}" \
        XEMU_SMOKE_WASM_BUILD_DIR="${wasm_build_dir}" \
            "${repo_root}/scripts/xbox-browser-block-callback-smoke.sh" \
                >"${delegate_summary}" 2>&1
        delegate_status="$?"
        set -e

        if [ -f "${delegate_out}/browser-block-callback-smoke.log" ]; then
            cat "${delegate_out}/browser-block-callback-smoke.log"
        fi
        if [ "${delegate_status}" -ne 0 ]; then
            cat "${delegate_summary}"
        fi
        return "${delegate_status}"
    fi

    local container_config="/xemu-smoke-out/$(basename "${config_path}")"
    local container_workdir="/workspace/${wasm_build_dir}"
    local timeout_s="$(( (timeout_ms + 999) / 1000 + 1 ))"
    local docker_args=(
        docker run --rm -t
        --user "$(id -u):$(id -g)"
        -e HOME=/tmp/xemu-home
        -e XEMU_HEADLESS_BOOT=1
        -e XEMU_BOOT_TRACE=1
        -e XEMU_BOOT_TRACE_CONTEXT=wasm-node-headless
        -e XEMU_HEADLESS_BOOT_MS="${timeout_ms}"
        -e XEMU_NODE_CONFIG="${container_config}"
        -e XEMU_NODE_TIMEOUT_MS="${timeout_ms}"
        -v "${repo_root}:/workspace"
        -v "${out_dir}:/xemu-smoke-out"
        -v "${XEMU_FLASH}:/xemu-fixtures/flash.bin:ro"
        -v "${eeprom_path}:/xemu-fixtures/eeprom.bin"
    )
    local trace_env

    for trace_env in \
        XEMU_BOOT_TRACE_DMA_LIMIT \
        XEMU_BOOT_TRACE_IDE_READ_LIMIT \
        XEMU_BOOT_TRACE_BMDMA_LIMIT \
        XEMU_BOOT_TRACE_XBE_DMA_LIMIT \
        XEMU_BOOT_TRACE_XBE_PHYS_SCAN \
        XEMU_BOOT_TRACE_XBE_PHYS_SCAN_BYTES \
        XEMU_BOOT_TRACE_XBE_VIRTUAL_PROBE_LIMIT \
        XEMU_BOOT_TRACE_XBE_READ_PROGRESS_LIMIT \
        XEMU_BOOT_TRACE_XBE_EXEC_PROBE_LIMIT \
        XEMU_BOOT_TRACE_XBE_PHYS_COMPARE_LIMIT \
        XEMU_BOOT_TRACE_XBE_EXEC_EDGE_LIMIT \
        XEMU_BOOT_TRACE_XBE_ENTRY_TARGET_LIMIT \
        XEMU_BOOT_TRACE_XBE_ENTRY_TARGET_WINDOW \
        XEMU_BOOT_TRACE_XBE_DISPATCH_LIMIT \
        XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT \
        XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT \
        XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_MIN_HITS \
        XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS \
        XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT \
        XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS \
        XEMU_BOOT_TRACE_XBE_EXEC_PROBE_STRIDE \
        XEMU_BOOT_TRACE_XBE_PIC_IRQ_LIMIT \
        XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT \
        XEMU_BOOT_TRACE_XBE_IRET_LIMIT \
        XEMU_BOOT_TRACE_XBE_PIT_IRQ_LIMIT \
        XEMU_BOOT_TRACE_XBE_MAIN_LOOP_TIMER_LIMIT \
        XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL \
        XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE \
        XEMU_BOOT_TRACE_XBE_IDLE_BEFORE_PFIFO_TRANSITION_LIMIT \
        XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY \
        XEMU_BOOT_TRACE_XBE_IRQ_WATCH \
        XEMU_BOOT_TRACE_NV2A_PMC_LIMIT \
        XEMU_BOOT_TRACE_NV2A_IRQ_LIMIT \
        XEMU_BOOT_TRACE_NV2A_IRQ_LINE_LIMIT \
        XEMU_BOOT_TRACE_NV2A_IRQ_LINE_LOW_PRIORITY_LIMIT \
        XEMU_BOOT_TRACE_NV2A_IRQ_LINE_PCRTC_LIMIT \
        XEMU_BOOT_TRACE_NV2A_PFIFO_LIMIT \
        XEMU_BOOT_TRACE_NV2A_PFIFO_WINDOW_START \
        XEMU_BOOT_TRACE_NV2A_PFIFO_WINDOW_LIMIT \
        XEMU_BOOT_TRACE_NV2A_PGRAPH_METHOD_LIMIT \
        XEMU_BOOT_TRACE_NV2A_PGRAPH_METHOD_WINDOW_START \
        XEMU_BOOT_TRACE_NV2A_PGRAPH_METHOD_WINDOW_LIMIT \
        XEMU_BOOT_TRACE_NV2A_PGRAPH_NOTIFY_LIMIT \
        XEMU_BOOT_TRACE_NV2A_PGRAPH_NOTIFY_CLEAR_LIMIT; do
        if [ -n "${!trace_env:-}" ]; then
            docker_args+=(-e "${trace_env}=${!trace_env}")
        fi
    done

    if [ ! -f "${repo_root}/${wasm_build_dir}/qemu-system-i386.js" ] || [ ! -f "${repo_root}/${wasm_build_dir}/qemu-system-i386.wasm" ]; then
        echo "Wasm build artifacts are missing in ${repo_root}/${wasm_build_dir}" >&2
        echo "Run scripts/docker-build-xemu-wasm.sh first." >&2
        exit 2
    fi

    if [ -n "${XEMU_MCPX:-}" ]; then
        docker_args+=(-v "${XEMU_MCPX}:/xemu-fixtures/mcpx.bin:ro")
    fi
    if [ -n "${XEMU_HDD:-}" ]; then
        docker_args+=(-v "${XEMU_HDD}:/xemu-fixtures/xbox_hdd.img")
    fi
    if [ -n "${XEMU_DVD:-}" ]; then
        docker_args+=(-v "${XEMU_DVD}:/xemu-fixtures/dvd.iso:ro")
    fi

    docker_args+=(
        -w "${container_workdir}"
        "${wasm_image}"
        timeout "${timeout_s}s"
        node -e '
            import("./qemu-system-i386.js").then(async ({ default: Factory }) => {
                const startedAt = Date.now();
                const timeoutMs = Number(process.env.XEMU_NODE_TIMEOUT_MS) || 30000;
                setTimeout(() => {
                    console.log(`BOOT_SMOKE_RESULT reason=timeout elapsed_ms=${Date.now() - startedAt} exit=0`);
                    process.exit(0);
                }, timeoutMs);
                const moduleArg = {
                    arguments: [
                        "-config_path", process.env.XEMU_NODE_CONFIG,
                        "-headless_boot_ms", String(timeoutMs),
                    ],
                };
                moduleArg.preRun = [() => {
                    moduleArg.FS.mkdir("/workspace");
                    moduleArg.FS.mount(moduleArg.NODEFS, { root: "/workspace" }, "/workspace");
                    moduleArg.FS.mkdir("/xemu-smoke-out");
                    moduleArg.FS.mount(moduleArg.NODEFS, { root: "/xemu-smoke-out" }, "/xemu-smoke-out");
                    moduleArg.FS.writeFile("/xemu-smoke-out/boot_trace_context.txt", "wasm-node-headless\n");
                    moduleArg.FS.mkdir("/xemu-fixtures");
                    moduleArg.FS.mount(moduleArg.NODEFS, { root: "/xemu-fixtures" }, "/xemu-fixtures");
                    moduleArg.FS.mkdirTree("/home/web_user/.local/share/xemu/xemu");
                }];
                await Factory(moduleArg);
            }).catch((err) => {
                console.error(err);
                process.exit(1);
            });
        '
    )

    "${docker_args[@]}"
}

set +e
case "${mode}" in
    native-headless)
        run_native >"${log_path}" 2>&1
        ;;
    docker-headless)
        run_docker >"${log_path}" 2>&1
        ;;
    wasm-node-headless)
        run_wasm_node >"${log_path}" 2>&1
        ;;
esac
run_status=$?
set -e

if [ "${mode}" = "wasm-node-headless" ] &&
   [ "${run_status}" -eq 124 ] &&
   ! grep -q '^BOOT_SMOKE_RESULT ' "${log_path}"; then
    {
        printf 'BOOT_SMOKE_RESULT reason=host-timeout elapsed_ms=%s exit=124\n' "${timeout_ms}"
    } >>"${log_path}"
fi

highest_level="NONE"
highest_value=-1
failure_reason=""
for level in b0 b1 b2 b3 b4 b5 b6; do
    if grep -q "BOOT_MARK ${level}" "${log_path}"; then
        value="$(level_value "${level}")"
        highest_level="B${value}"
        highest_value="${value}"
    fi
done

if [ "${highest_value}" -lt "${expected_value}" ]; then
    result="fail"
    failure_reason="missing-expected-level"
else
    result="pass"
fi

if [ "${expected_value}" -ge 3 ] && ! has_b3_hdd_marker "${log_path}"; then
    result="fail"
    failure_reason="missing-b3-hdd-read"
fi

if ! grep -q '^BOOT_SMOKE_RESULT ' "${log_path}"; then
    result="fail"
    failure_reason="missing-smoke-result"
fi

summary="BOOT_SMOKE_SUMMARY result=${result} mode=${mode} level=${highest_level} expected=${expect_level} exit=${run_status}"
if [ -n "${failure_reason}" ]; then
    summary="${summary} reason=${failure_reason}"
fi
echo "${summary} log=${log_path}"

elapsed_ms="$(smoke_elapsed_ms "${log_path}")"
if [ -n "${elapsed_ms}" ]; then
    total_markers="$(grep -c '^BOOT_MARK ' "${log_path}" || true)"
    b0_markers="$(marker_count_for_level "${log_path}" b0)"
    b1_markers="$(marker_count_for_level "${log_path}" b1)"
    b2_markers="$(marker_count_for_level "${log_path}" b2)"
    b3_markers="$(marker_count_for_level "${log_path}" b3)"
    b4_markers="$(marker_count_for_level "${log_path}" b4)"
    b5_markers="$(marker_count_for_level "${log_path}" b5)"
    b6_markers="$(marker_count_for_level "${log_path}" b6)"
    marker_rate="$(marker_rate_per_sec "${total_markers}" "${elapsed_ms}")"
    printf 'BOOT_SMOKE_METRIC mode=%s elapsed_ms=%s markers=%s markers_per_sec=%s b0=%s b1=%s b2=%s b3=%s b4=%s b5=%s b6=%s\n' \
        "${mode}" "${elapsed_ms}" "${total_markers}" "${marker_rate}" \
        "${b0_markers}" "${b1_markers}" "${b2_markers}" "${b3_markers}" \
        "${b4_markers}" "${b5_markers}" "${b6_markers}"
fi

grep -E '^(Created QEMU launch parameters:|BOOT_MARK |BOOT_SMOKE_RESULT )' "${log_path}" || true

if [ "${result}" != "pass" ]; then
    exit 1
fi

exit 0
