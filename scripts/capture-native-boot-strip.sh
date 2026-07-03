#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: scripts/capture-native-boot-strip.sh [options] [-- xemu-args...]

Capture a native xemu boot strip at a fixed sample rate using software GL.
This script does not compare or grade frames. It only saves PNGs for human
visual review.

Options:
  --out DIR       Output directory. Default: /tmp/xemu-boot-strips/native-<timestamp>
  --seconds N    Capture duration in seconds. Default: 35
  --fps N        Capture rate. Default: 2
  --help         Show this help.

Environment:
  XEMU_NATIVE_BIN                    Native xemu binary. Default: ./dist/xemu
  XEMU_NATIVE_CAPTURE_SECONDS        Same as --seconds.
  XEMU_NATIVE_CAPTURE_FPS            Same as --fps.
USAGE
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
start_script="${repo_root}/scripts/start-native-software-gl.sh"
xemu_bin="${XEMU_NATIVE_BIN:-${repo_root}/dist/xemu}"
timestamp="$(date +%Y%m%d-%H%M%S)"
out_dir="${XEMU_NATIVE_CAPTURE_OUT:-/tmp/xemu-boot-strips/native-${timestamp}}"
seconds="${XEMU_NATIVE_CAPTURE_SECONDS:-35}"
fps="${XEMU_NATIVE_CAPTURE_FPS:-2}"
extra_args=()

while (($#)); do
    case "$1" in
        --out)
            out_dir="$2"
            shift 2
            ;;
        --seconds)
            seconds="$2"
            shift 2
            ;;
        --fps)
            fps="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --)
            shift
            extra_args=("$@")
            break
            ;;
        *)
            echo "error: unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ ! -x "${start_script}" ]]; then
    echo "error: missing launcher: ${start_script}" >&2
    exit 1
fi

for tool in awk date dd find nm; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "error: required tool not found: ${tool}" >&2
        exit 1
    fi
done

if ! awk -v fps="${fps}" 'BEGIN { exit !(fps > 0) }'; then
    echo "error: --fps must be greater than zero" >&2
    exit 1
fi

if ! awk -v seconds="${seconds}" 'BEGIN { exit !(seconds > 0) }'; then
    echo "error: --seconds must be greater than zero" >&2
    exit 1
fi

mkdir -p "${out_dir}"
out_dir="$(cd -- "${out_dir}" && pwd)"
work_dir="$(mktemp -d /tmp/xemu-native-strip.XXXXXX)"
socket_path="${work_dir}/qmp.sock"
log_path="${out_dir}/native-xemu.log"
manifest_path="${out_dir}/manifest.json"
frame_interval="$(awk -v fps="${fps}" 'BEGIN { printf "%.6f", 1.0 / fps }')"
xemu_realpath="$(readlink -f "${xemu_bin}")"
symbol_hex="$(
    nm -C "${xemu_realpath}" | awk '
        $2 ~ /^[Bb]$/ && $3 == "g_screenshot_pending" && !found {
            print "0x" $1
            found = 1
        }
    '
)"

if [[ -z "${symbol_hex}" ]]; then
    echo "error: could not find g_screenshot_pending in ${xemu_realpath}" >&2
    exit 1
fi

configured_screenshot_dir=""
config_path="${XEMU_CONFIG_PATH:-${HOME}/.local/share/xemu/xemu/xemu.toml}"
if [[ -f "${config_path}" ]]; then
    configured_screenshot_dir="$(
        awk '
            /^\[/ { in_general = ($0 == "[general]") }
            in_general && /^[[:space:]]*screenshot_dir[[:space:]]*=/ {
                value = $0
                sub(/^[^=]*=[[:space:]]*/, "", value)
                gsub(/^'\''|'\''$/, "", value)
                gsub(/^"|"$/, "", value)
                print value
                exit
            }
        ' "${config_path}"
    )"
fi

shot_dir="${work_dir}"
if [[ -n "${configured_screenshot_dir}" ]]; then
    shot_dir="${configured_screenshot_dir/#\~/${HOME}}"
    mkdir -p "${shot_dir}"
fi
sentinel="${shot_dir}/.xemu-native-strip-sentinel-${timestamp}"
touch "${sentinel}"

pid=""
cleanup() {
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        kill "${pid}" 2>/dev/null || true
        wait "${pid}" 2>/dev/null || true
    fi
    rm -f "${sentinel}"
    rm -rf "${work_dir}"
}
trap cleanup EXIT

(
    cd "${work_dir}"
    exec "${start_script}" \
        -snapshot \
        -qmp "unix:${socket_path},server=on,wait=off" \
        -no-shutdown \
        "${extra_args[@]}"
) >"${log_path}" 2>&1 &
pid=$!

for _ in $(seq 1 120); do
    if [[ -S "${socket_path}" ]]; then
        break
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
        echo "error: xemu exited before QMP socket became available" >&2
        tail -80 "${log_path}" >&2 || true
        exit 1
    fi
    sleep 0.25
done

base_hex=""
for _ in $(seq 1 80); do
    if [[ -r "/proc/${pid}/maps" ]]; then
        base_hex="$(
            awk -v bin="${xemu_realpath}" '$3 == "00000000" && $6 == bin {
                split($1, range, "-")
                print "0x" range[1]
                exit
            }' "/proc/${pid}/maps"
        )"
    fi
    if [[ -n "${base_hex}" ]]; then
        break
    fi
    sleep 0.1
done

if [[ -z "${base_hex}" ]]; then
    echo "error: could not locate xemu base address in /proc/${pid}/maps" >&2
    exit 1
fi

runtime_addr=$((base_hex + symbol_hex))
frame_count="$(awk -v seconds="${seconds}" -v fps="${fps}" 'BEGIN { printf "%d", int(seconds * fps + 0.5) }')"

latest_screenshot() {
    find "${shot_dir}" -maxdepth 1 -type f -name 'xemu-*.png' -newer "${sentinel}" \
        -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR == 1 { $1=""; sub(/^ /, ""); print }'
}

echo "Capturing native software-GL boot strip into ${out_dir}" >&2
echo "frames=${frame_count} fps=${fps} seconds=${seconds}" >&2

captured=0
for frame in $(seq 0 $((frame_count - 1))); do
    frame_name="$(printf '%04d.png' "${frame}")"
    printf '\001' | dd of="/proc/${pid}/mem" bs=1 seek="${runtime_addr}" conv=notrunc status=none

    shot=""
    for _ in $(seq 1 40); do
        shot="$(latest_screenshot || true)"
        if [[ -n "${shot}" && -s "${shot}" ]]; then
            break
        fi
        sleep 0.05
    done

    if [[ -n "${shot}" && -s "${shot}" ]]; then
        mv "${shot}" "${out_dir}/${frame_name}"
        captured=$((captured + 1))
    else
        echo "warning: no screenshot produced for frame ${frame_name}" >&2
    fi

    sleep "${frame_interval}"
done

if command -v socat >/dev/null 2>&1 && [[ -S "${socket_path}" ]]; then
    printf '{"execute":"qmp_capabilities"}\n{"execute":"quit"}\n' | \
        socat - "UNIX-CONNECT:${socket_path}" >/dev/null 2>&1 || true
fi

for _ in $(seq 1 40); do
    if ! kill -0 "${pid}" 2>/dev/null; then
        break
    fi
    sleep 0.25
done

if kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}" 2>/dev/null || true
fi
wait "${pid}" 2>/dev/null || true
pid=""

renderer="$(awk -F': ' '/^GL_RENDERER:/ { print $2; exit }' "${log_path}" || true)"

cat >"${manifest_path}" <<EOF
{
  "kind": "native-llvmpipe-boot-strip",
  "capturedFrames": ${captured},
  "requestedFrames": ${frame_count},
  "fps": ${fps},
  "seconds": ${seconds},
  "renderer": "$(printf '%s' "${renderer}" | sed 's/"/\\"/g')",
  "xemu": "$(printf '%s' "${xemu_realpath}" | sed 's/"/\\"/g')",
  "log": "native-xemu.log",
  "review": "human-eyeball-only"
}
EOF

echo "Captured ${captured}/${frame_count} native frames." >&2
echo "${out_dir}"
