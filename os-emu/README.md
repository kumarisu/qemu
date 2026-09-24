# chip-emu — "get + build + run" script for OS emulation on ARM chips

The script **gets, builds, and boots** a bare-metal OS (`src/kernel`) for **two ARM chip
 targets**, running it in **QEMU** on macOS.

| Profile | Chip                                          | QEMU Machine              | ISA / state    | UART                      |
| ------- | --------------------------------------------- | ------------------------- | -------------- | ------------------------- |
| `a76`   | Cortex-A76 (MMU, 64-bit, application profile) | `virt`                    | AArch64        | PL011 @ `0x09000000`      |
| `r52`   | Cortex-R52 (RT, real-time)                    | `mps3-an536` (FPGA AN536) | AArch32 Thumb  | CMSDK/APB @ `0xE7C00000`  |

The two profiles are cross-compiled with the **same Apple/Homebrew LLVM clang**, but with
different targets/flags (see `config.sh`/`run_os.sh`):

* `a76` -> `--target=aarch64-none-elf` — 64-bit AArch64. Note: register 31 is `xzr` (zero
  register); writing it with `movz`/`movk` is architecturally discarded, so the boot glue
  uses *SP-semantics* `mov sp, xN` (the ADD alias) to set the stack pointer.
* `r52` -> `--target=arm-none-eabi -mthumb -march=armv7-a` — the AN536 FPGA image boots the
  Cortex-R52 in **Thumb (AArch32)** state, exactly like the official AN536 bare-metal demo.

## Dependencies (macOS)

| Tool     | How to install                                | Used for                                          |
| -------- | --------------------------------------------- | ------------------------------------------------- |
| QEMU     | `brew install qemu` (already installed 11.1.1) | the emulator                                      |
| `clang`  | Apple CommandLineTools / `brew install llvm`   | cross-compiling bare-metal ELF objects            |
| `ld.lld` | `brew install lld`                             | ELF linker (Apple `ld` produces only Mach-O)      |

`./run_os.sh setup` checks everything and installs what is missing (one time).

## How to use

```sh
cd os-emu

./run_os.sh setup                 # check qemu + clang + ld.lld (install if needed)
./run_os.sh build all             # cross-compile both images (build/a76, build/r52)
./run_os.sh run a76               # boot Cortex-A76 (qemu-system-aarch64 -M virt -cpu cortex-a76)
./run_os.sh run r52               # boot Cortex-R52 (qemu-system-arm -M mps3-an536)
./run_os.sh smoke a76 [secs]      # headless boot; capture + print serial output
./run_os.sh all r52               # setup + build + run in one command
./run_os.sh get free-rtos         # (optional) clone FreeRTOS-Kernel into extern/
```

`run` attaches the console to stdio: exit with `Ctrl-A x`, or `Ctrl-A C` to open the QEMU
monitor. Use `run <profile> -a` to try HVF acceleration (a76 only).

**Verification (a76)** — output should end with:

```text
[chip-emu] DEMO-OS-OK  16 quanta scheduled by cooperative round-robin on cortex-a76 / virt.
```

## What the script does (get / build / run)

1. **get** — the demo OS lives in `src/`. `./run_os.sh get free-rtos` clones the official
   FreeRTOS-Kernel into `extern/` as a starting point for porting FreeRTOS (same toolchain).
2. **build** — Apple `clang` (freestanding, `-ffreestanding -fno-builtin`), then `ld.lld`
   with the profile link script and `-e _start`.
3. **run** — `qemu-system-aarch64 -M virt -cpu cortex-a76 -kernel build/a76/os-a76.elf`
   or `qemu-system-arm -M mps3-an536 -cpu cortex-r52 -kernel build/r52/os-r52.elf`.

## Memory layout (linker scripts in toolchain/)

| Section          | a76 / virt            | r52 / mps3-an536  |
| ---------------- | --------------------- | ----------------- |
| `.text/.rodata`  | `0x40080000`          | `0x0`             |
| `.bss` (stacks)  | `0x40200000`          | `0x10000000`      |
| initial `sp`     | `0x40200000`          | `0x10020000`      |

The Cortex-R52 boots from TCM with the interrupt vector base at `0x0` (AN536), so the image
text sits there. The `virt` machine has RAM at `0x40000000` and QEMU's aarch64 `-kernel`
loader expects the image around `0x40080000`.

## Status / notes

* **Cortex-A76 (a76)** — fully working: banner + 2-task round-robin scheduler with per-task
  stacks + `DEMO-OS-OK` marker, verified on QEMU 11.1.1.
* **Cortex-R52 (r52)** — built exactly per the official AN536 bare-metal layout (Thumb,
  vectors at 0). QEMU **boots it and prints the platform banner**. The AN536 machine in
  current QEMU (11.x) powers-up the R52 in its hypervisor (EL2/AArch32) state whose own
  vector base is a fixed, *unmapped* address (`0x40000`) that this machine model does not
  let the guest configure (a documented AN536 limitation in QEMU). A generic bare-metal
  image therefore gets re-vectored by QEMU at the first exception. Doing a full R52 low-level
  EL2 setup (like Zephyr's `mps3/an536` board does) is the next step if you need the R52
  scheduler to finish — this demo keeps the minimal hooks (`cpsid if`, tables in `.text`)
  so the guest runs until such an event. The A76 path is unaffected.

## Structure

```text
os-emu/
├── run_os.sh              # CLI: setup | get | build | run | smoke | all
├── config.sh              # profiles (per chip: qemu, machine, cpu, uart, layout, ISA)
├── toolchain/
│   ├── setup.sh           # check/install qemu + clang + ld.lld
│   ├── link-a76.ld        # AArch64 image layout (virt)
│   └── link-r52.ld        # Thumb image layout (mps3-an536)
├── src/
│   ├── boot/start_a76.S   # A-profile boot (mov sp,x -> ADD alias; k_os_entry)
│   ├── boot/start_r52.S   # R52 boot (Thumb, vector base @ 0, k_stack_push)
│   └── kernel/            # demOS: kernel.c (RR scheduler), uart.c (PL011/CMSDK), os.h
└── extern/                # (get free-rtos) FreeRTOS-Kernel
```


# Dual kernel boot
Power On

  → BootROM chạy trên CR52 (SCP role)

  → ICUMX IPL / SPL trên CR52: init DRAM, RT-VRAM

  → CR52 dùng APMU bật nguồn + set start address cho CA76

  |-------------------------------┬-----------------------------------┐
  │  NHÁNH CA76 (song song)       │  NHÁNH CR52 (song song)         │
  │  SPL(A76) → U-Boot            │  Tiếp tục chạy firmware riêng   │
  │  → TF-A BL31 → Linux kernel   │  → nạp Classic AUTOSAR OS       │
  │  → systemd → EM               │     (MCAL + OS task/alarm...)   │
  │  → Adaptive Platform stack    │  → chạy các task real-time      │
  │     (như mô tả boot trước)    │     ASIL D độc lập              │
  └───────────────────────────────┴─────────────────────────────────┘
       
       Giao tiếp giữa 2 domain qua IPC nội bộ (Mailbox/shared memory),
       không qua ara::com — đây thường là kênh riêng do vendor cung cấp