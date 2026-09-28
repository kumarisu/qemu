# chip-emu — Detailed guide: folders, sources, meaning and usage

This document explains the complete structure of the `chip-emu` project: the role of
each folder and each file, what they contain, and how they link together. It is a
companion to `README.md` (quick guide): here you find the level of detail needed to
truly understand and modify the project.

---

## 1. The project in a few words

`chip-emu` is a project that:

1. **Compiles** a mini **bare-metal** operating system (no Linux, no libc) for
   an ARM chip board — the source lives in `src/kernel` and `src/boot`;
2. **Loads and runs** that OS in the **QEMU** emulator (installed on macOS);
3. The OS demonstrates it works: it prints a banner and runs a **round-robin
   scheduler with 2 tasks** on the emulated chip.

The system can target **two** hardware profiles (configured in `config.sh`):

| Profile | Chip (ARM CPU)              | QEMU machine         | Code ISA        | UART (console)            |
| ------- | --------------------------- | -------------------- | --------------- | ------------------------- |
| `a76`   | Cortex-A76 (with MMU)       | `virt`               | AArch64         | PL011 at `0x09000000`     |
| `r52`   | Cortex-R52 (real-time)      | `mps3-an536` (AN536) | AArch32 Thumb   | CMSDK/APB at `0xE7C00000` |

> **What "bare-metal" (freestanding) means:** our code depends on nothing — no
> libc, no system calls, no OS drivers. We compile it "bare", load it straight
> into emulated RAM, and access peripherals via MMIO (Memory-Mapped I/O).
> You can apply these same techniques to real embedded hardware.

---

## 2. Folder map

```
os-emu/
│── .gitignore
│── README.md                 ← quick guide (install, other commands)
│── DOCUMENTATIE.md           ← this file (detailed explanation)
│
│── run_os.sh                 ← main script (CLI: setup/build/run)
│── config.sh                 ← hardware profiles + toolchain discovery
│
│── toolchain/
│    │── setup.sh             ← check/install qemu, clang, lld
│    │── link-a76.ld          ← memory map for Cortex-A76 (ELF 64-bit)
│    └── link-r52.ld          ← memory map for Cortex-R52 (ELF 32-bit)
│
│── src/
│    │── boot/
│    │    │── start_a76.S     ← entry point for A76 (assembly, AArch64)
│    │    └── start_r52.S     ← entry point for R52 (Thumb, vector-base)
│    └── kernel/
│         │── os.h            ← public kernel interface
│         │── kernel.c        ← banner, scheduler, tasks
│         └── uart.c          ← console drivers (PL011 and CMSDK)
│
│── build/                    ← GENERATED: .o, .elf, .list, smoke.log (git-ignored)
└── extern/                   ← GENERATED: FreeRTOS-Kernel clone (git-ignored)
```

Each file is detailed below, in an easy-to-follow order.
---
## 3. `run_os.sh` — the main script (CLI)

This bash script is the project's "front door": it centralizes the whole
"get → build → run" chain. It reads values from `config.sh` (the `pcfg`
function) and invokes the tools (clang, lld, QEMU).

### 3.1 Available commands

| Command                                | What it does                                                |
| -------------------------------------- | ----------------------------------------------------------- |
| `./run_os.sh setup`                    | check/install qemu, clang, ld.lld (toolchain)               |
| `./run_os.sh get`                      | show OS source options                                      |
| `./run_os.sh get free-rtos`            | clone the FreeRTOS-Kernel repository into `extern/`         |
| `./run_os.sh build [a76\|r52\|all]`     | cross-compile the image (one profile or both)               |
| `./run_os.sh run [a76\|r52] [-a]`       | interactive boot in QEMU (console → terminal)               |
| `./run_os.sh smoke [a76\|r52] [secs]`   | headless boot, capture serial into `build/<p>/smoke.log`    |
| `./run_os.sh all [a76\|r52]`           | setup + build + run in a single command                     |
| `./run_os.sh help`                     | show this help                                              |

### 3.2 Key functions (for modifiers)

* **`build_one(p)`** — compiles one profile, in steps:
  1. `clang --target=<triple> <thumbopts> -c src/boot/start_<p>.S` → `start.o`;
  2. `clang ... -c src/kernel/kernel.c` and `uart.c` with the platform macros
     `-DUART_BASE=... -DUART_TYPE=... -DPLAT_CPU=... -DPLAT_MACHINE=... -DPLAT_STACKTOP=...`;
  3. `ld.lld -e _start -T toolchain/link-<p>.ld start.o kernel.o uart.o` → `os-<p>.elf`;
  4. optionally, disassembly into `os-<p>.list` (via `llvm-objdump`).
* **`run_one(p)`** — builds the QEMU command:
  `qemu-system-... -M <machine> -m <RAM> [-cpu ...] -kernel <elf> -nographic -serial mon:stdio`;
  the `-a` flag adds `-accel hvf` (HVF acceleration — a76 only).
* **`smoke_one(p, secs)`** — same QEMU, but `-display none -serial file:build/<p>/smoke.log`,
  runs for `secs` seconds, then stops QEMU and shows the log.
* **`get_os(...)`** — `git clone --depth 1 https://github.com/FreeRTOS/FreeRTOS-Kernel.git extern/`.
* **`usage()`** — extracts lines 2–17 from the file header.

---

## 4. `config.sh` — profiles and toolchain (single source of truth)

This file is the **single source** for all scripts: every hardware detail and
the toolchain are defined here. Values are read via the `pcfg` function.

### 4.1 Toolchain discovery (linker `ld.lld`)

`config.sh` searches for `ld.lld` in order:
1. `/opt/homebrew/opt/lld/bin/ld.lld` (modern `lld` keg, LLVM 23+);
2. `/opt/homebrew/opt/llvm/bin/ld.lld` (for installs with lld inside the `llvm` keg);
3. `ld.lld` from `PATH`.

> **Why do we need lld?** Apple `/usr/bin/ld` only produces Mach-O (macOS format) —
> it cannot generate the ELF images (ARM32/ARM64) QEMU needs. `ld.lld` is the
> LLVM linker, supporting ELF for both architectures.

### 4.2 Field–profile table (the `pcfg <field>-<profile>` function)

| Field       | `a76` (virt, aarch64)     | `r52` (mps3-an536, thumb) | Meaning                              |
| ----------- | ------------------------- | ------------------------- | ------------------------------------ |
| `qemu-`     | `qemu-system-aarch64`     | `qemu-system-arm`         | QEMU binary for the profile          |
| `machine-`  | `virt`                    | `mps3-an536`              | QEMU machine ("board")               |
| `cpu-`      | `cortex-a76`              | `cortex-r52`              | emulated CPU model                   |
| `ld-`       | `link-a76.ld`             | `link-r52.ld`             | profile linker script                |
| `uart-`     | `0x09000000`              | `0xE7C00000`              | UART base address (MMIO console)     |
| `uarttype-` | `1` (pl011)               | `2` (cmsdk)               | UART driver in `uart.c`              |
| `stacktop-` | `0x40200000`              | `0x10020000`              | initial stack address (SP)           |
| `ram-`      | `512`                     | `256`                     | RAM passed to `-m` (in MB)           |
| `triple-`   | `aarch64-none-elf`        | `arm-none-eabi`           | LLVM target (64-bit / 32-bit)        |
| `thumb-`    | _(empty)_                 | `-mthumb -march=armv7-a`  | extra ISA flags for clang            |

Usage examples:
```bash
pcfg qemu-a76   # → qemu-system-aarch64
pcfg uart-r52   # → 0xE7C00000
pcfg thumb-r52  # → -mthumb -march=armv7-a
```

---

## 5. `toolchain/` — helpers and linker scripts

### 5.1 `toolchain/setup.sh`

The toolchain install/check script. It walks through in order:

| Step  | What it checks                                         | What it installs if missing |
| ----- | ------------------------------------------------------ | --------------------------- |
| QEMU  | `qemu-system-aarch64` and `qemu-system-arm`            | `brew install qemu`         |
| clang | `clang --target=aarch64-none-elf -print-target-triple` | `brew install llvm`         |
| lld   | `ld.lld` (paths from §4.1)                             | `brew install lld`          |

The `--no-install` flag only checks without installing. At the end it suggests
build/run commands.

### 5.2 Linker scripts — "memory maps"

A linker script tells the linker **where** to place ELF sections in the guest
address space. That is why the 2 profiles differ: QEMU boards load the image at
their own physical addresses.

**`link-a76.ld`** (`virt` profile, AArch64 ELF):

```
.  = 0x40080000;      ← virt machine RAM starts at 0x40000000;
  .text                QEMU aarch64 `-kernel` loads the image around 0x40080000
  .rodata              (executable code and constants)
.  = 0x40200000;      ← task stacks (.bss), separate from code
  .bss
```

`OUTPUT_FORMAT("elf64-littleaarch64")` — 64-bit little-endian ELF format.

**`link-r52.ld`** (AN536 profile, Thumb ELF):

```
.  = 0x00000000;      ← R52 boots from TCM; exception vectors at 0
  .text
  .rodata
.  = 0x10000000;      ← AN536 RAM (the .bss section = stacks)
  .bss
```

`OUTPUT_FORMAT("elf32-littlearm")` — 32-bit ELF format (Thumb).

---

## 6. `src/boot/` — boot glue (the entry point, in assembly)

On embedded there is no bootloader: QEMU loads the ELF and lets the CPU start
from the "entry" address. These assembly files contain the first instructions
that execute.

### 6.1 `src/boot/start_a76.S` (AArch64, virt machine)

```asm
_start:
    movz x30, #0x4020, lsl #16   ; x30 = 0x40200000 (16 bits + shift)
    movk x30, #0x0000            ;  → x30 = 0x40200000
    mov  sp, x30                 ; SP := 0x40200000  (see XZR note)
    mov  x29, sp                 ; FP := SP
    bl   k_os_entry              ; call the C kernel

k_stack_push:                    ; scheduler helper (switch stack)
    mov  sp, x0
    ret

hang:  b  hang                   ; basic safety loop
```

> **Essential note — register 31 (XZR/SP):** in AArch64, register field `31` is
> ambiguous: `movz`/`movk` instructions treat it as **XZR (zero register)** —
> writing it is silently discarded! That is why we set SP via **`mov sp, xN`**,
> which is an `add` alias (with true SP semantics, confirmed empirically).
> Without it, SP would stay 0 and the first push would cause an abort.

### 6.2 `src/boot/start_r52.S` (Thumb/AArch32, mps3-an536 machine)

The R52 boots in **Thumb (AArch32)** mode and expects the image with the
**exception vectors at address 0** (TCM). So the first words in `.text` are
exactly these vectors, just like in the official AN536 demo:

```asm
_start:
    ldr sp, =stacktop            ; SP := 0x10020000 (literal from pool)
    b    reset

    .word hang                   ; Undefined instruction
    .word hang                   ; Software interrupt
    .word hang                   ; Prefetch abort
    .word hang                   ; Data abort
    .word hang                   ; Reserved
    .word hang                   ; IRQ
    .word hang                   ; FIQ

reset:
    cpsid if                     ; mask IRQ+FIQ (see AN536 note)
    bl   k_os_entry

k_stack_push:
    mov  sp, r0                  ; in Thumb SP = r13, an ordinary register
    bx   lr                      ; return

stacktop: .word 0x10020000       ; pool holding the stack-top value
```

> **AN536 machine note:** QEMU models the R52 as booting in **EL2 (hypervisor)**;
> its vector base is 0x40000, an **unmapped** address in this model (a documented
> limitation). The first exceptions re-vector the guest. Hence we mask with
> `cpsid if` and keep tables in `.text` — the image boots and prints the banner,
> but a "full" R52 (e.g. Zephyr) needs EL2 setup. The a76 profile is unaffected.

---

## 7. `src/kernel/` — the mini-OS source (in C)

### 7.1 `src/kernel/os.h` — public interface

A small header defining the "contract" between the boot glue, the kernel, and the
console driver. Each public function is documented in the interface:

| Function                                           | Meaning                                    |
| -------------------------------------------------- | ------------------------------------------ |
| `k_os_entry()`                                     | kernel entry point (called by `start_*.S`) |
| `k_putc / k_puts / k_crlf / k_puthex / k_putdec`   | serial output (dev console)                |
| `k_yield()`                                        | cooperative yield (no-op in the demo)      |
| `k_halt()`                                         | infinite loop (end of demo)                |

### 7.2 `src/kernel/kernel.c` — the "heart" of the OS

The file holds the demo OS (freestanding, depends on nothing):

| Element                 | What it does                                              |
| ----------------------- | --------------------------------------------------------- |
| `stack0[] / stack1[]`   | the 2 private task stacks (in `.bss` at link time)        |
| `area_top(stack)`       | stack-top address (source for `k_stack_push`)             |
| `k_stack_push(top)`     | "extern" function — implemented in `start_*.S` (changes SP)|
| `task_a() / task_b()`   | "the 2 processes": print a line and yield control         |
| `scheduler_roundrobin()`| loop: `tick % 2`, switch stack, `k_yield`, run task       |
| `print_banner()`        | prints cpu, machine, UART base, stack top (from `-DPLAT_*`)|
| `k_os_entry()`          | banner → scheduler → `k_halt()`                           |

The demo scheduler, in pseudocode:

```
loop:
    t = tick % 2
    tick++
    task_stack_push(t)      ; switch SP to task t's stack
    k_yield()               ; cooperation point
    if t == 0: task_a() else task_b()
    until tick == 16        ; after 16 quanta → "DEMO-OS-OK" → k_halt()
```

### 7.3 `src/kernel/uart.c` — console drivers (two in one file)

Platforms use different UARTs, so the driver has two implementations, selected
at compile time via the **`-DUART_TYPE=1|2`** macro:

| `UART_TYPE` | UART          | Chip / machine             | Registers (offset from base)              |
| ----------- | ------------- | -------------------------- | ----------------------------------------- |
| `1` (pl011) | PrimeCell PL011 | A76 / `virt` @ `0x09000000` | DR@+0x00, FR@+0x18, CR@+0x30, LCRH@+0x2c |
| `2` (cmsdk) | CMSDK/APB     | R52 / an536 @ `0xE7C00000`  | DATA@+0x00, STATE@+0x04, CTRL@+0x08, BAUD@+0x10 |

Both call `uart_write(c)`: initialize the UART, wait with a **bounded wait**
(at most 64 iterations, so it never deadlocks) and send the character. The public
functions (`k_puts`, `k_puthex`, etc.) live in the same file.

> **Pitfall fixed during development:** testing `#if UART_TYPE == pl011` directly
> was wrong: in the C preprocessor, two undefined identifiers (e.g. `cmsdk` and
> `pl011`) both have value 0, so the comparison always yields `0 == 0` (always
> true). Hence `UART_TYPE` is now 1/2 (integers).

---

## 8. `build/` and `extern/` — generated folders (git-ignored)

* **`build/<profile>/`** — build results:
  | File                          | Contents                                |
  | ----------------------------- | --------------------------------------- |
  | `start.o, kernel.o, uart.o`   | intermediate object files (ELF)         |
  | `os-<p>.elf`                  | final image QEMU loads (`-kernel`)      |
  | `os-<p>.list`                 | disassembly (for inspection)            |
  | `smoke.log`                   | serial log (from the `smoke` command)   |
* **`extern/FreeRTOS-Kernel/`** — official clone of the FreeRTOS kernel (via
  `run_os.sh get free-rtos`); starting point for porting FreeRTOS to these
  boards with the same toolchain.
---

## 9. Data flow — what happens at each step

```
./run_os.sh build all
   ├─[config.sh]                     → triple, thumbopts, uart, stacktop, linker script ...
   ├─ clang --target=<triple> -c src/boot/start_a76.S         → build/a76/start.o
   ├─ clang --target=<triple> ... -c src/kernel/kernel.c (+ -DUART_*)  → kernel.o
   ├─ clang --target=<triple> ... -c src/kernel/uart.c  (+ -DUART_TYPE=1) → uart.o
   ├─ ld.lld -e _start -T toolchain/link-a76.ld start.o kernel.o uart.o
   │                                                          → build/a76/os-a76.elf
   └─ (same for r52: triple=arm-none-eabi, -mthumb, uarttype=2, link-r52.ld)

./run_os.sh run a76
   └─ qemu-system-aarch64 -M virt -cpu cortex-a76 -m 512 \
        -kernel build/a76/os-a76.elf -nographic -serial mon:stdio
```

Inside the emulated guest:

```
_start  (SP := 0x40200000, FP := SP)
  └─ k_os_entry()
       ├─ print_banner()          → UART: banner with cpu / machine / addresses
       ├─ scheduler_roundrobin()  → 16x (switch SP, task_a / task_b → UART)
       └─ "DEMO-OS-OK ..."        → success marker
```

---

## 10. Success output (how to recognize it works)

**Cortex-A76** (`./run_os.sh smoke a76` or `run a76`):

```text
  +-------------------------------------------------------+
  |  chip-emu demOS v0.1   (bare-metal, no libc)          |
  +-------------------------------------------------------+
  cpu        : cortex-a76
  machine    : virt
  uart       : 0x09000000
  ...
[chip-emu] scheduler starts
  [taskA] quantum 0  -> private stack @0x40200004 alpha
  [taskB] quantum 0  -> private stack @0x40200084 beta
  ...
[chip-emu] DEMO-OS-OK 16 quanta scheduled by cooperative round-robin on cortex-a76 / virt.
```

**Cortex-R52** (`./run_os.sh smoke r52`) — boots and prints the banner; full EL2
setup is only in the "full" R52 (see §6.2 and `README.md`).

---

## 11. How to add a new profile / chip to the project

1. In `config.sh` add the `pcfg` fields for the new profile: `qemu-`, `machine-`,
   `cpu-`, `uart-`, `uarttype-`, `stacktop-`, `ram-`, `triple-`, `thumb-`, `ld-`.
2. Create `src/boot/start_<p>.S` — assembly initializing SP and calling
   `k_os_entry` (for R-cores also the vectors at the right addresses).
3. Create `toolchain/link-<p>.ld` — memory map for the new machine.
4. If the UART differs: add the implementation in `uart.c` and the `uarttype-` value.
5. Verify: `./run_os.sh build <p> && ./run_os.sh smoke <p>`.

---

## 12. Troubleshooting (problems and fixes)

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `ERROR: linker ld.lld not found` | linker not installed | `./run_os.sh setup` (installs `brew install lld`) |
| `Couldn't load elf ... incompatible architecture` | loaded an ARM64 image into a 32-bit machine | `./run_os.sh build r52` (correct triple for Thumb) |
| No banner (a76) | wrong UART_BASE or image not loaded | value `UART_BASE=0x09000000` (QEMU 11); `smoke` → `build/a76/smoke.log` |
| R52 stops after banner | EL2 vectors / an536 (0x40000 unmapped) | see §6.2; full EL2 port = separate work |
| `...: unbound variable` in script | bash 3.2 + `local p="$1" w=...` | split declarations (already fixed in script) |
| Warning `interworking not performed` (lld, r52) | symbol `k_stack_push` non-STT_FUNC | benign Thumb→Thumb; non-blocking |

---

## 13. Quick glossary

| Term | Meaning |
| ---- | ------- |
| **bare-metal / freestanding** | code with no OS and no libc; compile with `-ffreestanding -fno-builtin -nostdlib` |
| **ELF** | Linux/embedded executable format (produced by clang + lld) |
| **cross-compile** | compile on Mac for an ARM CPU (`--target=...`) |
| **linker script** | file fixing section addresses in the image |
| **UART** | serial port (embedded dev console) |
| **MMIO** | peripheral access directly via memory addresses |
| **exception vectors** | handler table at a fixed address (R-core boot) |
| **PL011 / CMSDK UART** | two QEMU-emulated UART types (different registers) |
| **XZR / SP (register 31, AArch64)** | field 31 = zero register (write discarded) or stack pointer |
| **EL2 / hypervisor (R52)** | R52 boots in EL2; fixed vector base 0x40000 in the MPS3 AN536 model |

