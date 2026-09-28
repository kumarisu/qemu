# os-emu — Hướng dẫn chi tiết: thư mục, source, ý nghĩa và cách dùng

> Tài liệu này giải thích **từng thư mục và từng file** trong dự án `os-emu`:
> để làm gì, chứa gì, liên kết với nhau ra sao, và dùng như thế nào.
> Đây là tài liệu chi tiết đi kèm `README.md` (hướng dẫn nhanh).

---

## 1. Tổng quan dự án trong một phút

`os-emu` làm 3 việc theo chuỗi **get → build → run**:

1. **Build** một hệ điều hành mini chạy **bare-metal**
   (không Linux, không libc, không syscall) cho chip ARM —
   source nằm ở `src/boot/` (assembly khởi động) và `src/kernel/` (C).
2. **Run** OS đó trên **QEMU** đã cài trên macOS.
3. OS khi boot sẽ **in banner ra UART** rồi chạy thử
   **bộ lập lịch round-robin với 2 task**, mỗi task có stack riêng,
   rồi in marker `DEMO-OS-OK`.

Dự án hỗ trợ **2 profile phần cứng** (cấu hình trong `config.sh`):

| Profile | Chip | Máy QEMU | Tập lệnh | UART |
|---|---|---|---|---|
| `a76` | Cortex-A76 (64-bit, có MMU) | `virt` | AArch64 | PL011 tại `0x09000000` |
| `r52` | Cortex-R52 (real-time) | `mps3-an536` (AN536) | AArch32 Thumb | CMSDK/APB tại `0xE7C00000` |

> **Bare-metal / freestanding:** code không dựa vào OS hay libc nào.
> Ta biên dịch "trần", nạp thẳng ELF vào RAM giả lập,
> điều khiển ngoại vi bằng đọc/ghi địa chỉ bộ nhớ
> (**MMIO — Memory-Mapped I/O**). Đúng cách làm firmware nhúng thật.

---

## 2. Sơ đồ thư mục

```text
os-emu/
├── run_os.sh             ← script chính (setup/get/build/run/smoke/all)
├── config.sh             ← profile phần cứng + tìm toolchain
├── README.md             ← hướng dẫn nhanh
├── HUONG-DAN-CHI-TIET.md ← file này (giải thích chi tiết)
├── DOCUMENTATIE.md       ← bản cũ tiếng Romania (tham khảo)
├── .gitignore            ← loại build/ và extern/ khỏi git
├── toolchain/
│   ├── setup.sh          ← kiểm tra / cài qemu, clang, ld.lld
│   ├── link-a76.ld       ← bản đồ bộ nhớ cho A76 (ELF 64-bit)
│   └── link-r52.ld       ← bản đồ bộ nhớ cho R52 (ELF 32-bit)
├── src/
│   ├── boot/
│   │   ├── start_a76.S   ← điểm vào khi boot A76 (AArch64)
│   │   └── start_r52.S   ← điểm vào khi boot R52 (Thumb + vector)
│   └── kernel/
│       ├── os.h          ← interface public của kernel
│       ├── kernel.c      ← banner, 2 task, scheduler round-robin
│       └── uart.c        ← driver console (PL011 và CMSDK)
├── build/                ← TỰ SINH: .o, .elf, .list, smoke.log
└── extern/               ← TỰ SINH: FreeRTOS-Kernel clone về
```

`build/` và `extern/` nằm trong `.gitignore` nên không commit —
luôn tái tạo được bằng lệnh. Xóa lúc nào cũng an toàn.
---

## 3. `run_os.sh` — script chính (cửa vào của mọi thao tác)

File bạn gõ lệnh vào nhiều nhất. Nó đọc cấu hình từ `config.sh`
(qua hàm `pcfg`) rồi gọi clang / ld.lld / QEMU tương ứng.

### 3.1. Các lệnh có sẵn

| Lệnh | Tác dụng |
|---|---|
| `./run_os.sh setup` | Kiểm tra qemu + clang + ld.lld, thiếu thì cài bằng Homebrew |
| `./run_os.sh get` | In các lựa chọn source OS (demo OS nằm sẵn ở `src/`) |
| `./run_os.sh get free-rtos` | Clone FreeRTOS-Kernel chính chủ về `extern/` |
| `./run_os.sh build [a76\|r52\|all]` | Biên dịch chéo ra ảnh ELF |
| `./run_os.sh run [a76\|r52] [-a]` | Boot ảnh trong QEMU, console gắn ra stdio |
| `./run_os.sh smoke [a76\|r52] [giây]` | Boot headless vài giây, chụp log serial rồi in ra |
| `./run_os.sh all [a76\|r52] [-a]` | Gộp setup + build + run trong một lệnh |

```sh
cd os-emu
./run_os.sh setup        # một lần duy nhất
./run_os.sh build all    # biên dịch cả 2 ảnh
./run_os.sh run a76      # boot A76, thoát bằng Ctrl-A x
./run_os.sh smoke a76 6  # boot ngầm 6 giây rồi in log
./run_os.sh all r52      # setup + build + run R52
```

### 3.2. Bên trong từng hàm (đọc code thế nào)

- **`build_one(p)`** — build 1 profile, 4 bước:
  1. Dịch assembly: `clang --target=<triple> <thumb-flags>
     -c src/boot/start_<p>.S -o build/<p>/start.o`
  2. Dịch 2 file C freestanding
     (`-O2 -Wall -Wextra -g -ffreestanding -fno-builtin`)
     kèm macro `-DUART_BASE=... -DUART_TYPE=... -DPLAT_CPU=...`
     `-DPLAT_MACHINE=... -DPLAT_STACKTOP=...` và `-I src/kernel`
     → `kernel.o`, `uart.o`.
  3. Link: `ld.lld -o build/<p>/os-<p>.elf -e _start
     -T toolchain/link-<p>.ld start.o kernel.o uart.o`
     (điểm vào là symbol `_start` trong file assembly).
  4. Nếu có `llvm-objdump` thì disassembly ra `os-<p>.list` để soi.
- **`run_one(p)`** — dựng lệnh QEMU:
  `qemu-system-... -M <machine> -m <RAM> [-cpu ...] -kernel <elf>
  -nographic -serial mon:stdio`; cờ `-a` thêm `-accel hvf` (chỉ a76).
- **`smoke_one(p, secs)`** — giống run nhưng
  `-display none -serial file:build/<p>/smoke.log`,
  chạy nền `secs` giây rồi kill QEMU và in log. Tiện kiểm tra tự động.
- **`get_os(...)`** — `git clone --depth 1
  https://github.com/FreeRTOS/FreeRTOS-Kernel.git extern/`.
- **`usage()`** — in 16 dòng comment đầu file làm help text.

---

## 4. `config.sh` — profile phần cứng + toolchain

Mọi script đều `source config.sh` để lấy cùng một bộ giá trị.
Muốn đổi UART, RAM, triple... thì **chỉ sửa file này**.

### 4.1. Tìm toolchain (linker `ld.lld`)

`config.sh` tìm `ld.lld` theo thứ tự:

1. `/opt/homebrew/opt/lld/bin/ld.lld` (keg `lld` hiện đại, LLVM 23+),
2. `/opt/homebrew/opt/llvm/bin/ld.lld` (kiểu cài cũ),
3. `ld.lld` trong `PATH`.

> **Vì sao cần lld?** Linker của Apple (`/usr/bin/ld`) chỉ tạo Mach-O
> (định dạng macOS), không tạo được ELF ARM mà QEMU cần nạp.
> `ld.lld` của LLVM mới link được ELF cho cả hai kiến trúc.

Biến dùng chung: `CLANG` (mặc định `clang`),
`AARCH_TRIPLE=aarch64-none-elf`.

### 4.2. Bảng field–profile (hàm `pcfg <field>-<profile>`)

| Field | `a76` (virt) | `r52` (an536) | Ý nghĩa |
|---|---|---|---|
| `qemu-` | `qemu-system-aarch64` | `qemu-system-arm` | binary QEMU |
| `machine-` | `virt` | `mps3-an536` | "board" QEMU giả lập |
| `cpu-` | `cortex-a76` | `cortex-r52` | model CPU giả lập |
| `ld-` | `link-a76.ld` | `link-r52.ld` | linker script |
| `uart-` | `0x09000000` | `0xE7C00000` | địa chỉ base UART (MMIO) |
| `uarttype-` | `1` (pl011) | `2` (cmsdk) | chọn driver trong `uart.c` |
| `stacktop-` | `0x40200000` | `0x10020000` | giá trị khởi tạo SP |
| `ram-` | `512` | `256` | RAM cho `-m` (MB) |
| `triple-` | `aarch64-none-elf` | `arm-none-eabi` | target LLVM |
| `thumb-` | *(rỗng)* | `-mthumb -march=armv7-a` | cờ ISA thêm cho clang |

```sh
source config.sh
pcfg qemu-a76    # → qemu-system-aarch64
pcfg uart-r52    # → 0xE7C00000
pcfg thumb-r52   # → -mthumb -march=armv7-a
```

> Tương thích bash 3.2 của macOS: `pcfg` dùng `case`
> thay vì associative array (bash 3.2 không có).

---

## 5. `toolchain/` — script cài đặt và linker script

### 5.1. `toolchain/setup.sh` — kiểm tra / cài toolchain

Chạy qua `./run_os.sh setup`. Ba bước, mỗi bước "thiếu thì cài":

| Bước | Kiểm tra gì | Cài gì nếu thiếu |
|---|---|---|
| QEMU | `qemu-system-aarch64` và `qemu-system-arm` trong PATH | `brew install qemu` |
| clang | `clang --target=aarch64-none-elf -print-target-triple` chạy được | `brew install llvm` |
| ld.lld | các đường dẫn ở mục 4.1 có file thực thi | `brew install lld` |

Cờ `--no-install` chỉ kiểm tra, không cài.
Cuối cùng script gợi ý lệnh build/run tiếp theo.

### 5.2. Linker script — "bản đồ bộ nhớ" của ảnh ELF

Linker script bảo linker **đặt từng section ELF vào địa chỉ vật lý nào**
trong không gian địa chỉ của guest. Hai board nạp ảnh ở hai chỗ khác
nhau nên cần hai file khác nhau.

**`link-a76.ld`** (board `virt`, ELF 64-bit):

```ld
. = 0x40080000;     /* RAM máy virt bắt đầu ở 0x40000000; */
  .text             /* QEMU aarch64 -kernel nạp ảnh quanh 0x40080000 */
  .rodata           /* (code + hằng số) */
. = 0x40200000;     /* stack các task (.bss), tách khỏi code */
  .bss
```

`OUTPUT_FORMAT("elf64-littleaarch64")` — ELF 64-bit little-endian.

**`link-r52.ld`** (board AN536, ELF Thumb 32-bit):

```ld
. = 0x00000000;     /* R52 boot từ TCM; bảng vector ngắt ở địa chỉ 0 */
  .text
  .rodata
. = 0x10000000;     /* RAM của AN536 (section .bss = các stack) */
  .bss
```

`OUTPUT_FORMAT("elf32-littlearm")` — ELF 32-bit little-endian (Thumb).

---

## 6. `src/boot/` — boot glue (lệnh đầu tiên khi bật máy)

Trên embedded không có bootloader: QEMU nạp ELF rồi cho CPU chạy từ
địa chỉ "entry" (symbol `_start`). Hai file assembly này là
vài chục lệnh đầu tiên được thực thi.

### 6.1. `src/boot/start_a76.S` (AArch64, máy virt)

```asm
_start:
    movz x30, #0x4020, lsl #16   ; x30 = 0x40200000 (nạp 16 bit + dịch)
    movk x30, #0x0000            ; → x30 = 0x40200000 hoàn chỉnh
    mov  sp, x30                 ; SP := 0x40200000 (xem ghi chú XZR)
    mov  x29, sp                 ; FP := SP (frame pointer)
    bl   k_os_entry              ; gọi kernel viết bằng C

k_stack_push:                    ; helper cho scheduler đổi stack
    mov  sp, x0                  ; MOV sp,x0 là alias của ADD (ghi SP thật)
    ret

hang:  b  hang                   ; vòng lặp an toàn nếu kernel return
```

> **Ghi chú quan trọng — thanh ghi số 31 (XZR/SP):**
> Ở AArch64, trường thanh ghi `31` có 2 nghĩa tùy lệnh:
> `movz`/`movk` hiểu nó là **XZR (zero register)** — ghi vào sẽ bị CPU
> lặng lẽ vứt đi! Muốn đặt SP phải dùng **`mov sp, xN`**
> (thực chất là alias của `add`, mang ngữ nghĩa SP thật —
> đã kiểm chứng trên QEMU). Làm sai thì SP vẫn bằng 0
> và lần push đầu tiên gây abort.

Giá trị `0x40200000` phải **khớp** với `stacktop-a76` trong `config.sh`
và vị trí `.bss` trong `link-a76.ld`. Đổi một nơi phải đổi cả ba.

### 6.2. `src/boot/start_r52.S` (Thumb/AArch32, máy mps3-an536)

R52 boot ở chế độ **Thumb (AArch32)** và đòi ảnh có **bảng vector
ngoại lệ ngay tại địa chỉ 0** (vùng TCM), giống demo AN536 chính chủ:

```asm
_start:
    ldr sp, =stacktop            ; SP := 0x10020000 (từ literal pool)
    b    reset

    .word hang                   ; +0x08 Undefined instruction
    .word hang                   ; +0x0C Software interrupt (SWI/SVC)
    .word hang                   ; +0x10 Prefetch abort
    .word hang                   ; +0x14 Data abort
    .word hang                   ; +0x18 Reserved
    .word hang                   ; +0x1C IRQ
    .word hang                   ; +0x20 FIQ

reset:
    cpsid if                     ; che IRQ+FIQ (xem ghi chú AN536)
    bl   k_os_entry              ; gọi kernel C

k_stack_push:
    mov  sp, r0                  ; ở Thumb SP là r13, thanh ghi thường
    bx   lr                      ; trở về

stacktop: .word 0x10020000       ; literal pool chứa giá trị stack-top
```

> **Ghi chú board AN536:** model QEMU đưa R52 lên ở trạng thái
> **hypervisor EL2 (AArch32)** mà vector base riêng của EL2 là địa chỉ
> cố định **không được map (`0x40000`)**, guest không cấu hình lại được
> (giới hạn đã ghi nhận của model AN536 trong QEMU).
> Demo giữ tối thiểu: `cpsid if` tắt ngắt + bảng vector trỏ về `hang`
> để guest chạy ổn định cho tới khi cần setup EL2 đầy đủ
> (tham khảo board `mps3/an536` của Zephyr). Đường A76 không ảnh hưởng.

---

## 7. `src/kernel/` — kernel demo (C freestanding, không libc)

### 7.1. `src/kernel/os.h` — interface public

Khai báo những gì boot glue và các file C dùng chung:

- `k_os_entry()` — điểm vào kernel (boot glue gọi tới),
- `k_putc / k_puts / k_crlf / k_puthex / k_putdec` — họ in ra UART,
- `k_yield()` — nhường CPU tự nguyện (cooperative, hiện return ngay),
- `k_halt()` — vòng lặp treo máy sau khi xong demo.

Dòng `#error` bắt `UART_BASE` phải được truyền bằng `-D` lúc build —
quên là compiler báo lỗi ngay thay vì chạy với địa chỉ rác.

### 7.2. `src/kernel/kernel.c` — banner + scheduler + 2 task

| Thành phần | Vai trò |
|---|---|
| `stack0[32]`, `stack1[32]` | 2 stack riêng trong `.bss` (QEMU khởi tạo RAM = 0) |
| `tick`, `cnt_a`, `cnt_b` | đếm quanta dùng chung và đếm riêng từng task |
| `area_top(s)` | đỉnh stack = `s + 32` (stack ARM mọc từ cao xuống thấp) |
| `task_stack_push(t)` | gọi `k_stack_push` (assembly) trỏ SP sang stack task `t` |
| `task_a()` / `task_b()` | mỗi "tiến trình" in 1 dòng rồi nhường lại |
| `scheduler_roundrobin()` | vòng lặp: `tick % 2` chọn task, đổi stack, yield, chạy task |
| `print_banner()` | in cpu / machine / UART base / stack top (từ macro `-DPLAT_*`) |
| `k_os_entry()` | banner → scheduler → `k_halt()` |
| `k_halt()` | vòng lặp vô hạn cuối demo |

Giả mã scheduler:

```text
loop:
    t = tick % 2
    tick++
    task_stack_push(t)      ; chuyển SP sang stack của task t
    k_yield()               ; điểm hợp tác
    nếu t == 0: task_a() else task_b()
    lặp đến khi tick == 16  ; đủ 16 quanta → in "DEMO-OS-OK" → k_halt()
```

`16` (số quanta) và `STACK_WORDS 32` là hằng demo —
đổi tùy ý rồi build lại là thấy khác ngay.

### 7.3. `src/kernel/uart.c` — driver console (2 loại trong 1 file)

Hai board dùng UART khác nhau nên driver có 2 nhánh, chọn lúc biên dịch
bằng macro số nguyên **`-DUART_TYPE=1|2`** (lấy từ `uarttype-`):

| `UART_TYPE` | UART | Board | Thanh ghi (offset từ base) |
|---|---|---|---|
| `1` (pl011) | PrimeCell PL011 | A76 / `virt` @ `0x09000000` | DR@+0x00, FR@+0x18, CR@+0x30, LCRH@+0x2c |
| `2` (cmsdk) | CMSDK/APB | R52 / AN536 @ `0xE7C00000` | DATA@+0x00, STATE@+0x04, CTRL@+0x08, BAUD@+0x10 |

Cả hai đều qua `uart_write(c)`: khởi tạo UART, chờ FIFO rỗng với
**vòng chờ có chặn trên** (tối đa 64 vòng để không treo), rồi ghi ký tự.
Các hàm tiện ích (`k_puts`, `k_puthex`, `k_putdec`, `k_crlf`) chung file.

> **Bẫy preprocessor đã sửa:** code cũ so `#if UART_TYPE == pl011`
> (identifier). Trong C preprocessor, hai identifier chưa định nghĩa
> đều bằng 0 nên `0 == 0` luôn đúng — nhánh sai vẫn biên dịch!
> Vì vậy `UART_TYPE` giờ là **số 1/2**.

---

## 8. `build/` và `extern/` — thư mục sinh ra (không commit)

- **`build/<profile>/`** — kết quả build:

  | File | Nội dung |
  |---|---|
  | `start.o`, `kernel.o`, `uart.o` | object trung gian (ELF) |
  | `os-<p>.elf` | ảnh cuối cùng QEMU nạp (`-kernel`) |
  | `os-<p>.list` | disassembly để soi lệnh |
  | `smoke.log` | log serial từ lệnh `smoke` |

- **`extern/FreeRTOS-Kernel/`** — bản clone chính chủ kernel FreeRTOS
  (bằng `./run_os.sh get free-rtos`); điểm xuất phát để port FreeRTOS
  lên 2 board này với cùng toolchain clang+lld.

- **`.gitignore`** — chỉ 2 dòng (`build/`, `extern/`), đúng 2 thư mục
  tái tạo được thì bỏ khỏi git.

---

## 9. Luồng dữ liệu — chuyện gì xảy ra ở mỗi bước

```text
./run_os.sh build all
   ├─ [config.sh] → triple, thumb-flags, uart, stacktop, linker script ...
   ├─ clang -c src/boot/start_a76.S              → build/a76/start.o
   ├─ clang -c src/kernel/kernel.c (+ -DUART_*)  → kernel.o
   ├─ clang -c src/kernel/uart.c (+ -DUART_TYPE) → uart.o
   ├─ ld.lld -e _start -T link-a76.ld *.o        → build/a76/os-a76.elf
   └─ (tương tự r52: triple=arm-none-eabi, -mthumb, uarttype=2)

./run_os.sh run a76
   └─ qemu-system-aarch64 -M virt -cpu cortex-a76 -m 512 \
        -kernel build/a76/os-a76.elf -nographic -serial mon:stdio
```

Bên trong guest giả lập:

```text
_start  (SP := stacktop, FP := SP)
  └─ k_os_entry()
       ├─ print_banner()         → UART: banner cpu / board / địa chỉ
       ├─ scheduler_roundrobin() → 16 lần (đổi SP, task_a / task_b → UART)
       └─ "DEMO-OS-OK ..."       → marker thành công → k_halt()
```

---

## 10. Output thành công (nhận biết chạy đúng)

**Cortex-A76** (`./run_os.sh smoke a76` hay `run a76`):

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

**Cortex-R52** (`./run_os.sh smoke r52`): boot được và in banner;
setup EL2 đầy đủ để scheduler R52 chạy hết 16 quanta là bước tiếp theo
(xem mục 6.2 và `README.md`).

---

## 11. Thêm profile / chip mới vào dự án

1. Trong `config.sh`, thêm đủ field `pcfg` cho profile mới:
   `qemu-`, `machine-`, `cpu-`, `uart-`, `uarttype-`, `stacktop-`,
   `ram-`, `triple-`, `thumb-`, `ld-`.
2. Tạo `src/boot/start_<p>.S` — assembly dựng SP rồi gọi `k_os_entry`
   (dòng R-core nhớ đặt bảng vector đúng địa chỉ).
3. Tạo `toolchain/link-<p>.ld` — bản đồ bộ nhớ cho board mới.
4. Nếu UART khác loại: thêm nhánh trong `uart.c` + giá trị `uarttype-`.
5. Kiểm tra: `./run_os.sh build <p> && ./run_os.sh smoke <p>`.

---

## 12. Xử lý sự cố (troubleshooting)

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| `ERROR: linker ld.lld not found` | chưa cài linker | `./run_os.sh setup` (sẽ `brew install lld`) |
| `Couldn't load elf ... incompatible architecture` | nạp ảnh ARM64 vào máy 32-bit (hoặc ngược lại) | build đúng profile (`build r52` cho Thumb) |
| Không thấy banner (a76) | sai UART_BASE hoặc ảnh chưa nạp | kiểm tra `UART_BASE=0x09000000` (QEMU 11); xem `build/a76/smoke.log` |
| R52 dừng sau banner | vector EL2 của AN536 (`0x40000` không map) | xem mục 6.2; port EL2 đầy đủ là việc riêng |
| `...: unbound variable` trong script | bash 3.2 không cho `local a=.. b=..` gộp | tách khai báo (đã sửa sẵn) |
| Cảnh báo `interworking not performed` (r52) | symbol `k_stack_push` thiếu STT_FUNC | lành tính Thumb→Thumb; bỏ qua được |

---

## 13. Bảng thuật ngữ nhanh

| Thuật ngữ | Nghĩa |
|---|---|
| **bare-metal / freestanding** | code không OS, không libc; build với `-ffreestanding -fno-builtin -nostdlib` |
| **ELF** | định dạng thực thi của Linux/embedded (clang + lld tạo ra) |
| **cross-compile** | biên dịch trên Mac ra binary cho chip ARM (`--target=...`) |
| **linker script** | file cố định địa chỉ các section trong ảnh |
| **UART** | cổng nối tiếp (console phát triển trong embedded) |
| **MMIO** | điều khiển ngoại vi bằng đọc/ghi địa chỉ bộ nhớ |
| **bảng vector ngoại lệ** | bảng handler ở địa chỉ cố định (R-core boot từ đó) |
| **PL011 / CMSDK UART** | hai loại UART QEMU giả lập (thanh ghi khác nhau) |
| **XZR / SP (thanh ghi 31, AArch64)** | trường 31 = zero register (ghi bị vứt) hoặc SP, tùy lệnh |
| **EL2 / hypervisor (R52)** | R52 khởi động ở EL2; vector base `0x40000` trong model AN536 |
| **smoke test** | boot ngầm vài giây, chụp log serial để kiểm tra nhanh |
| **HVF** | Hypervisor.framework của macOS (tăng tốc QEMU, cờ `-a`) |

