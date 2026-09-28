#!/usr/bin/env bash
# run_freertos_qemu.sh -- chay image FreeRTOS tren QEMU (bare-metal ELF).
#   ./run_freertos_qemu.sh [a76|r52]              (mac dinh: a76, che do tuong tac)
#   ./run_freertos_qemu.sh [a76|r52] smoke [secs] (headless + log serial)
#   ./run_freertos_qemu.sh [a76|r52] -a ...       (-a = thu HVF accel, chi a76)
# Image: build/<p>/os-<p>-freertos.elf (build bang ./build_freertos.sh <p>).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$HERE/config.sh"

BUILD="$HERE/build"

usage() {
  sed -n '2,6p' "$0"
  echo "  a76 -> Cortex-A76 tren \"virt\"        (qemu-system-aarch64)"
  echo "  r52 -> Cortex-R52 tren \"mps3-an536\"  (qemu-system-arm, AN536 image)"
  exit "${1:-0}"
}

valid_profile() { [ "$1" = a76 ] || [ "$1" = r52 ]; }

# ---- interactive run: console -> terminal (Ctrl-A X de thoat) ----
run_one() {
  local p="$1"; shift
  local q m ram elf cpu accel
  q="$(pcfg qemu-$p)"; m="$(pcfg machine-$p)"; ram="$(pcfg ram-$p)"
  elf="$BUILD/$p/os-$p-freertos.elf"
  cpu=""; accel=""
  [ "$p" = a76 ] && cpu="$(pcfg cpu-a76)"
  [ -f "$elf" ] || { echo "image missing: $elf -- chay: ./build_freertos.sh $p" >&2; exit 1; }
  if [ "${1:-}" = "-a" ]; then accel="-accel hvf"; shift; fi
  printf '\n== %s -M %s -kernel %s ==\n' "$q" "$m" "$elf"
  # shellcheck disable=SC2086
  exec "$q" -M "$m" -m "$ram" ${cpu:+-cpu "$cpu"} -kernel "$elf" \
       -nographic -serial mon:stdio $accel "$@"
}

# ---- smoke: headless vai giay, ghi serial ra file roi in ra ----
smoke_one() {
  local p="$1"; shift
  local q m ram elf cpu out secs pid
  q="$(pcfg qemu-$p)"; m="$(pcfg machine-$p)"; ram="$(pcfg ram-$p)"
  elf="$BUILD/$p/os-$p-freertos.elf"
  out="$BUILD/$p/freertos-smoke.log"
  cpu=""
  [ "$p" = a76 ] && cpu="$(pcfg cpu-a76)"
  [ -f "$elf" ] || { echo "image missing: $elf -- chay: ./build_freertos.sh $p" >&2; exit 1; }
  secs="${1:-6}"
  rm -f "$out"
  echo "== smoke [$p] ${secs}s: $q -M $m -kernel $elf =="
  # shellcheck disable=SC2086
  "$q" -M "$m" -m "$ram" ${cpu:+-cpu "$cpu"} -kernel "$elf" \
       -display none -serial "file:$out" &
  pid=$!
  sleep "$secs"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  echo "== -> serial output in $out =="
  if [ -s "$out" ]; then
    cat "$out"
  else
    echo "(no serial output captured)"
  fi
}

# ================= CLI =================
p="${1:-a76}"
valid_profile "$p" || usage 2
shift || true
case "${1:-}" in
  smoke) smoke_one "$p" "${2:-6}" ;;
  help|-h|--help) usage 0 ;;
  *) run_one "$p" "$@" ;;
esac
