#!/usr/bin/env bash
# chip-emu common configuration.
#
# Platform profiles (which chip the "OS" image is built for and emulated on):
#   a76 -> ARM Cortex-A76  (64-bit, MMU)   emulated on QEMU machine "virt"
#   r52 -> ARM Cortex-R52  (real-time)     emulated on QEMU machine "mps3-an536"
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------ toolchain (bare-metal ELF)
# Cross compile with the LLVM toolchain shipped with Apple CommandLineTools
# (clang); the ELF *linker* is ld.lld — Homebrew formula "lld" (LLVM 23+
# ships the linker in a separate keg) — because Apple's /usr/bin/ld only
# produces Mach-O.
: "${CLANG:=clang}"
: "${LLD:=}"
# prefer the modern "lld" keg, then the older "llvm" keg, then PATH
for cand in "$(brew --prefix lld 2>/dev/null)/bin/ld.lld" \
            "$(brew --prefix llvm 2>/dev/null)/bin/ld.lld" \
            "$(command -v ld.lld 2>/dev/null)"; do
  if [ -n "$cand" ] && [ -x "$cand" ]; then
    LLD="$cand"
    break
  fi
done
: "${LLVM_PREFIX:=$(brew --prefix llvm 2>/dev/null || true)}"

AARCH_TRIPLE=aarch64-none-elf

# ------------------------------------------------------ profile accessor ---
# pcfg <field>-<profile> -> value   (bash 3.2 compatible; no associative arrays)
pcfg() {
  case "$1" in
    qemu-a76)     echo qemu-system-aarch64 ;;  qemu-r52)  echo qemu-system-arm ;;
    machine-a76)  echo virt ;;                 machine-r52) echo mps3-an536 ;;
    cpu-a76)      echo cortex-a76 ;;           cpu-r52)    echo cortex-r52 ;;
    ld-a76)       echo link-a76.ld ;;          ld-r52)     echo link-r52.ld ;;
    uart-a76)     echo 0x09000000 ;;           uart-r52)   echo 0xE7C00000 ;;
    uarttype-a76) echo 1 ;;                 uarttype-r52) echo 2 ;;
    stacktop-a76) echo 0x40200000 ;;           stacktop-r52) echo 0x10020000 ;;
    ram-a76)      echo 512 ;;                  ram-r52)    echo 256 ;;
    # cross-compile triple + ISA switch per profile:
    #   a76 -> AArch64 (64-bit);  r52 -> AArch32 Thumb (R52 boots in Thumb state)
    #   r52 + "-mfpu=none": clang KHONG sinh VFP/NEON. Ly do: (1) port
    #   ARM_CRx_No_GIC khong luu FP-SIMD khi doi task, (2) QEMU cortex-r52
    #   tren mps3-an536 tra Undefined Instruction cho vdup/vst (xem app_main.c).
    #   Neu bo -mfpu=none thi phai bat CPACR.CP10|CP11 (app_main.c da lam).
    triple-a76)   echo aarch64-none-elf ;;     triple-r52) echo arm-none-eabi ;;
    thumb-a76)    echo "" ;;                   thumb-r52)  echo -mthumb -march=armv7-a -mfpu=none ;;
    *) echo "pcfg: unknown key '$1'" >&2; return 2 ;;
  esac
}

valid_profile() { [ "$1" = a76 ] || [ "$1" = r52 ]; }