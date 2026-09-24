#!/usr/bin/env bash
# chip-emu — get, build and boot a bare-metal OS image on QEMU for the
# ARM Cortex-A76 and Cortex-R52 (RT) chips.
#
#   ./run_os.sh setup                       # check/install toolchain + QEMU
#   ./run_os.sh get                         # show OS-source options (demo OS is in src/)
#   ./run_os.sh get free-rtos              # also fetch FreeRTOS kernel into extern/
#   ./run_os.sh build [a76|r52|all]         # cross-compile the OS image (clang)
#   ./run_os.sh run   [a76|r52] [-a]        # boot the image under QEMU
#   ./run_os.sh smoke [a76|r52] [secs]      # headless boot + captured serial
#   ./run_os.sh all   [a76|r52] [-a]        # setup + build + run
#
#   a76 -> Cortex-A76 on "virt"            (qemu-system-aarch64)
#   r52 -> Cortex-R52 on "mps3-an536"     (qemu-system-arm,  AN536 image)
#   -a  -> try HVF acceleration (only a76)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$HERE/config.sh"

SRC="$HERE/src"
BUILD="$HERE/build"

usage() {
  sed -n '2,17p' "$0"
  exit "${1:-0}"
}

# ---------------------------------------------------------------- build --
build_one() {
  local p="$1"
  local w="$BUILD/$p"
  local triple thumbopt cpu machine uart uarttype stacktop
  triple=$(pcfg triple-$p); thumbopt=$(pcfg thumb-$p)
  cpu=$(pcfg cpu-$p); machine=$(pcfg machine-$p)
  uart=$(pcfg uart-$p); uarttype=$(pcfg uarttype-$p)
  stacktop=$(pcfg stacktop-$p)

  mkdir -p "$w"
  printf '\n== building profile [%s] %s (%s) ==\n' "$p" "$cpu" "$machine"

  # 1) boot glue (assembly)
  "$CLANG" --target="$triple" $thumbopt -c "$SRC/boot/start_$p.S" \
            -o "$w/start.o"

  # 2) kernel C sources (freestanding; platform picked via -DUART_*/-DPLAT_*)
  cpu_def="PLAT_CPU=\"$cpu\""
  mach_def="PLAT_MACHINE=\"$machine\""
  for src in kernel.c uart.c; do
    "$CLANG" --target="$triple" $thumbopt -c \
        -O2 -Wall -Wextra -g -ffreestanding -fno-builtin \
        -DUART_BASE="$uart" -DUART_TYPE="$uarttype" \
        "-D$cpu_def" "-D$mach_def" \
        -DPLAT_STACKTOP="$stacktop" \
        -I"$SRC/kernel" \
        "$SRC/kernel/$src" -o "$w/${src%.c}.o"
  done

  # 3) link with an ELF linker (ld.lld; target arch auto-detected).
  #    Layout comes from the profile linker script, entry point is _start
  #    from the boot glue.
  if [ -z "$LLD" ] || [ ! -x "$LLD" ]; then
    echo "ERROR: linker ld.lld not found — run:  $HERE/run_os.sh setup" >&2
    exit 1
  fi
  "$LLD" -o "$w/os-$p.elf" -e _start \
      -T "$HERE/toolchain/$(pcfg ld-$p)" \
      "$w/start.o" "$w/kernel.o" "$w/uart.o"

  # 4) disassembly for inspection (when llvm-objdump is available)
  if command -v llvm-objdump >/dev/null 2>&1; then
    llvm-objdump -d "$w/os-$p.elf" > "$w/os-$p.list"
  elif [ -x "$LLVM_PREFIX/bin/llvm-objdump" ]; then
    "$LLVM_PREFIX/bin/llvm-objdump" -d "$w/os-$p.elf" > "$w/os-$p.list"
  fi

  printf '   -> %s\n' "$w/os-$p.elf"
}

# ----------------------------------------------------------------- run ---
run_one() {
  local p="$1"
  local q m ram elf accel extra cpu
  shift
  q=$(pcfg qemu-$p); m=$(pcfg machine-$p); ram=$(pcfg ram-$p)
  elf="$BUILD/$p/os-$p.elf"
  accel=""
  extra=""

  [ -f "$elf" ] || { echo "image missing — run: $0 build $p" >&2; exit 1; }

  if [ "${1:-}" = "-a" ]; then
    accel="-accel hvf"
    shift
  fi

  if [ "$p" = a76 ]; then
    cpu="$(pcfg cpu-a76)"
  fi

  printf '\n== %s -kernel %s ==\n' "$q" "$elf"
  exec "$q" -M "$m" -m "$ram" ${cpu:+-cpu "$cpu"} -kernel "$elf" \
       -nographic -serial mon:stdio $accel "$@"
}

# ------------------------------------------------------------------- get --
get_os() {
  case "${1:-}" in
    "")
      echo "OS source:"
      echo "  - chip-emu demOS: bundled right here in src/  (build + boot in one step)"
      echo "  - FreeRTOS kernel: run '$0 get free-rtos' to clone it under extern/"
      echo "       (the kernel in src/ is a starting point to port FreeRTOS"
      echo "        for the A76 virt / R52 AN536 boards — same toolchain)"
      ;;
    free-rtos | FreeRTOS | freertos)
      mkdir -p "$HERE/extern"
      local dst="$HERE/extern/FreeRTOS-Kernel"
      if [ -d "$dst/.git" ]; then
        echo "FreeRTOS kernel already cloned in $dst"
      else
        git clone --depth 1 https://github.com/FreeRTOS/FreeRTOS-Kernel.git "$dst"
      fi
      ;;
    *) usage 2 ;;
  esac
}

# --------------------------------------------------------------- smoke ---
# boot headless for a few seconds, capture serial output, kill, then show it
smoke_one() {
  local p="$1"
  local q m ram elf out cpu pid
  shift
  q=$(pcfg qemu-$p); m=$(pcfg machine-$p); ram=$(pcfg ram-$p)
  elf="$BUILD/$p/os-$p.elf"
  out="$BUILD/$p/smoke.log"
  cpu=""
  [ "$p" = a76 ] && cpu="$(pcfg cpu-a76)"

  [ -f "$elf" ] || { echo "image missing — run: $0 build $p" >&2; exit 1; }
  rm -f "$out"

  local secs="${1:-6}"
  echo "== smoke [$p] ${secs}s: $q -M $m -kernel $elf =="
  "$q" -M "$m" -m "$ram" ${cpu:+-cpu "$cpu"} -kernel "$elf" \
       -display none -serial "file:$out" &
  pid=$!
  sleep "$secs"
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  echo "== -> serial output in $out =="
  if [ -s "$out" ]; then
    cat "$out"
  else
    echo "(no serial output captured)"
  fi
}

# ------------------------------------------------------------------- CLI --
case "${1:-}" in
  setup)
    "$HERE/toolchain/setup.sh" "${2:-}"
    ;;
  get)
    get_os "${2:-}"
    ;;
  build)
    case "${2:-}" in
      all) build_one a76; build_one r52 ;;
      a76 | r52) build_one "$2" ;;
      "") usage 1 ;;
      *) usage 2 ;;
    esac
    ;;
  run)
    valid_profile "${2:-}" || usage 2
    run_one "${2:-a76}" "${@:3}"
    ;;
  smoke)
    valid_profile "${2:-}" || usage 2
    smoke_one "${2:-a76}" "${3:-6}"
    ;;
  all)
    "$HERE/toolchain/setup.sh" --no-install || true
    case "${2:-}" in
      a76 | r52) build_one "$2"; run_one "$2" "${@:3}" ;;
      *) build_one a76; build_one r52; run_one a76 "${@:3}" ;;
    esac
    ;;
  help | -h | --help) usage 0 ;;
  *) usage 1 ;;
esac