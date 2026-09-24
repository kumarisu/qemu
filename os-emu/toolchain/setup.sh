#!/usr/bin/env bash
# toolchain/setup.sh — check / install everything needed to build and boot
# the chip-emu OS image on QEMU (macOS).
#
#   ./setup.sh            # check + auto-install missing pieces (Homebrew)
#   ./setup.sh --no-install   # only report status
set -euo pipefail
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=config.sh
source "$SRC_DIR/config.sh"

say()  { printf '  \033[1;34m[setup]\033[0m %s\n' "$*"; }
step() { printf '\033[1;36m== %s ==\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[setup] ERROR: %s\033[0m\n' "$*"; exit 1; }

AUTO=1; [ "${1:-}" = --no-install ] && AUTO=0

step "QEMU"
for p in a76 r52; do
  q="$(pcfg qemu-$p)"
  if command -v "$q" >/dev/null 2>&1; then
    say "$q OK -> $("$q" --version | head -1)"
  else
    die "missing '$q'  (brew install qemu)"
  fi
done

step "C cross compiler (LLVM clang)"
if command -v "$CLANG" >/dev/null 2>&1 && "$CLANG" --target="$AARCH_TRIPLE" -print-target-triple >/dev/null 2>&1; then
  say "clang OK -> $(command -v "$CLANG")"
else
  if [ "$AUTO" = 1 ] && command -v brew >/dev/null 2>&1; then
    say "installing llvm via Homebrew (needed for aarch64 bare-metal ELF, one time ~1.5 GB) ..."
    brew install llvm
    say "llvm installed"
  else
    die "LLVM clang with --target=$AARCH_TRIPLE support required (brew install llvm)"
  fi
fi

step "ELF linker (ld.lld)"
if [ -n "$LLD" ] && [ -x "$LLD" ]; then
  say "ld.lld OK -> $LLD"
else
  if [ "$AUTO" = 1 ] && command -v brew >/dev/null 2>&1; then
    say "linking ld.lld: installing 'lld' via Homebrew (pulls llvm as dependency) ..."
    brew install lld
    LLD="$(brew --prefix lld 2>/dev/null)/bin/ld.lld"
    [ -n "$LLD" ] && [ -x "$LLD" ] || die "ld.lld still missing after 'brew install lld'"
    say "ld.lld OK -> $LLD"
  else
    die "linker ld.lld required  (brew install lld)"
  fi
fi

step "Result"
say "toolchain ready.  Build with:  $SRC_DIR/run_os.sh build"
say "Boot with:        $SRC_DIR/run_os.sh run a76   (Cortex-A76 / QEMU virt)"
say "                  $SRC_DIR/run_os.sh run r52   (Cortex-R52 / QEMU mps3-an536)"