# Tạo image OS (file `.elf`): từ mã nguồn tới file chạy trên QEMU

> File này giải thích chi tiết **image OS là gì, được tạo ra từ những nguồn nào,
> và quá trình build/link tạo file `.elf` diễn ra thế nào** trong `os-emu`.
> Đọc cùng: `README.md` (chạy nhanh), `HUONG-DAN-CHI-TIET.md` (từng file).

**Tóm tắt:** mỗi profile (`a76`, `r52`) cho ra đúng **1 file ELF duy nhất**
(`build/a76/os-a76.elf`, `build/r52/os-r52.elf`). File này được **link tĩnh từ
đúng 3 file object**: `start.o` (boot glue) + `kernel.o` + `uart.o`.
Nguồn RTOS thật (FreeRTOS trong `extern/`) **hiện chưa được biên dịch hay link
vào ELF** — nó là mã tham khảo cho bước port RTOS sau này.
QEMU nạp file ELF bằng `-kernel` và nhảy vào symbol `_start`.

---

## 1. File `.elf` là gì, và vì sao QEMU cần nó?

**ELF (Executable and Linkable Format)** là định dạng thực thi chuẩn của
Linux/embedded. Trong dự án này nó có 3 đặc điểm quan trọng:

| Đặc điểm | Ý nghĩa thực tế |
|---|---|
| **Link tĩnh** (statically linked) | Mọi thứ nằm gọn trong 1 file, không cần libc. `file os-a76.elf` báo `statically linked`. |
| **Địa chỉ vật lý cố định** | Linker script "đóng đinh" code ở địa chỉ X, stack ở địa chỉ Y. QEMU chỉ copy từng đoạn vào đúng RAM giả lập. |
| **Có entry point** | Header ELF ghi `Entry point 0x40080000` (= `_start`). QEMU đặt PC vào đó khi boot. |

File ELF có 2 góc nhìn song song (xem bằng `llvm-readelf`):

- **Sections** (góc nhìn linker): `.text` (code), `.rodata` (chuỗi/hằng),
  `.bss` (biến toàn cục), `.debug_*` (debug), `.symtab` (symbol). Số liệu thật:

```text
# a76 (ELF 64-bit aarch64): .text @0x40080000 (0x5f4) | .rodata (0x220)
#                           .bss  @0x40200000 (0x10c: stack0/stack1/tick/cnt)
# r52 (ELF 32-bit ARM)    : .text @0x00000000 (0x4be) | .rodata (0x226)
#                           .bss  @0x10000000 (0x10c)
```

- **Program headers** (góc nhìn loader — QEMU đọc cái này): mỗi đoạn `LOAD`
  ghi `VirtAddr` (nạp vào đâu) + `FileSiz` (copy bao nhiêu byte) + `MemSiz`
  (chiếm bao nhiêu RAM). Điểm hay: `.bss` có `FileSiz = 0`, `MemSiz = 0x10c` —
  tức **`.bss` không chiếm chỗ trong file, QEMU chỉ zero một vùng RAM**.

> Kích thước: `start.o` ~0.7 KB, `kernel.o` ~7–11 KB, `uart.o` ~6–9 KB,
> còn `os-*.elf` ~135 KB — phần lớn là `.debug_*` + `.symtab` (cờ `-g`).
> Code thực chỉ ~1.5 KB (`.text` + `.rodata`).


## 2. Ba tầng: host — QEMU — image (ELF không "chạy trên" OS nào)

Sai lầm dễ mắc nhất khi đọc dự án này là tưởng file `.elf` là "chương trình chạy
trên một OS". Thực tế có 3 tầng riêng biệt, đừng lẫn:

```text
[Tầng 1] macOS (host) → chỉ dùng lúc BUILD: clang/ld.lld tạo ELF; QEMU là 1 app macOS.
[Tầng 2] QEMU         → giả lập PHẦN CỨNG (bo mạch virt / mps3-an536), KHÔNG phải OS.
                        `-kernel os-a76.elf` ≈ nạp firmware vào ROM.
[Tầng 3] os-a76.elf   → chạy TRỰC TIẾP trên CPU giả lập, vào `_start`, không có gì bên dưới.
                        Bên trong nó có demOS mini (scheduler 2 task) + driver UART.
```

Phát biểu chính xác nhất: **"ELF là ảnh firmware bare-metal, không chạy trên OS
nào cả; OS (demOS mini) nằm BÊN TRONG cùng chính file ELF đó."** Host macOS chỉ
tham gia ở bước build và ở việc chạy tiến trình QEMU — code guest không bao giờ
gọi vào host (output bạn thấy trên terminal là QEMU chuyển tiếp byte UART giả lập).

### 2.1 Bằng chứng (tự kiểm lại trên ảnh build của bạn)

1. `llvm-readelf -d/-l build/a76/os-a76.elf` → chỉ còn `GNU_STACK`;
   **không có `INTERP`, không có `DYNAMIC`** = không cần dynamic loader,
   không cần OS nạp hay chạy nó.
2. `llvm-nm os-a76.elf | grep -icE 'vTask|xTask|malloc|printf|__libc| main$'`
   → **0** = không FreeRTOS, không libc, không `main()`.
3. Toàn bộ 16 symbol của ELF (chạy `llvm-nm os-a76.elf` để liệt kê đầy đủ):
   11 symbol code (`_start, k_stack_push, hang, k_os_entry, k_halt, k_putc,
   k_puts, k_crlf, k_puthex, k_putdec, k_yield`) + 5 biến `.bss`
   (`tick, stack0, stack1, cnt_a, cnt_b`).
4. Lệnh chạy QEMU (hàm `run_one()` trong `run_os.sh`): không `-bios`, không
   bootloader, không đĩa, không kernel Linux:
   `qemu-system-aarch64 -M virt -cpu cortex-a76 -m 512 -kernel build/a76/os-a76.elf
   -nographic -serial mon:stdio`.

### 2.2 demOS hiện tại còn thiếu gì so với một OS thực thụ?

| Một OS thực thụ có | demOS hiện tại |
|---|---|
| Preemption bằng ngắt timer (tick) | Không — `k_yield()` chỉ là no-op, task phải tự nhường CPU. |
| IPC: queue / semaphore / mutex | Không — chỉ 2 task cứng, chia sẻ `cnt_a`/`cnt_b`. |
| Cách ly tiến trình, MMU, user/kernel | Không — chạy hết ở chế độ đặc quyền, chung 1 không gian địa chỉ. |
| Syscall / trình nạp ứng dụng | Không — không có gì để "nạp app". |
| Heap, filesystem, driver phong phú | Không — chỉ có UART, stack là mảng tĩnh trong `.bss`. |
| Xử lý ngắt | R52 chỉ có 7 `.word hang` (mọi ngoại lệ đều treo); A76 chưa có vector. |

### 2.3 Lưu ý: port FreeRTOS vào cũng KHÔNG đổi bản chất này

Khi port FreeRTOS (checklist ở §3.3), FreeRTOS vẫn được **link vào cùng chính
file ELF** (`tasks.c`, `queue.c`, `port.c`... → thêm `.o` vào lệnh `ld.lld`),
chứ không phải ELF trở thành "ứng dụng chạy trên FreeRTOS". Khác biệt với desktop:

- **Trên Linux:** kernel là 1 file, app là file ELF khác → "app chạy trên OS"
  (OS cung cấp loader + syscall).
- **Ở đây:** chỉ có **1 file ELF duy nhất = kernel + board support + app đóng gói
  chung**, CPU nhảy vào `_start`, không có gì trung gian. Giống hệt cách nạp
  `.elf`/`.bin` lên STM32/ESP32 thật.


## 3. Nguồn RTOS (`extern/FreeRTOS-Kernel`): để làm gì, gồm những gì?

### 3.1 Vai trò: RTOS thật (đầy đủ) — hiện là mã tham khảo, CHƯA dùng để build

`./run_os.sh get free-rtos` clone repo chính thức FreeRTOS-Kernel vào
`extern/FreeRTOS-Kernel`. Đây là **RTOS đầy đủ cấp công nghiệp**: scheduler
**preemptive** (ưu tiên + ngắt tick), hàng đợi, semaphore, mutex, software
timer, event group, quản lý heap — thứ mà demOS mini trong `src/` (scheduler
hợp tác 2 task) không có.

> **Trả lời thẳng: lúc build, FreeRTOS có được đóng gói/link vào elf không?
> KHÔNG.** Bằng chứng: `build_one()` trong `run_os.sh` chỉ biên dịch đúng
> 3 file (`src/boot/start_<p>.S`, `src/kernel/kernel.c`, `src/kernel/uart.c`)
> rồi link — không có `-I extern/...` hay file `.c` nào từ `extern/`.
> `extern/` cũng nằm trong `.gitignore` (tái tạo bằng lệnh `get`).
> Nó là **điểm xuất phát để port FreeRTOS** lên 2 board này.

### 3.2 Chi tiết từng thành phần trong FreeRTOS-Kernel

**Nhân lõi (root, độc lập platform — dùng chung mọi chip):**

| File | Dòng code | Nhiệm vụ |
|---|---|---|
| `tasks.c` (~9.000 dòng) | Lớn nhất | Scheduler preemptive: `xTaskCreate`, `vTaskDelay/Delete/Suspend`, chuyển ngữ cảnh, tick. Sẽ **thay thế** `scheduler_roundrobin()` của demOS. |
| `queue.c` (~3.400 dòng) | | Hàng đợi + semaphore + mutex (`xQueueCreate/Send/Receive`). demOS hiện không có IPC. |
| `timers.c` (~1.300 dòng) | | Software timer (`xTimerCreate/Start`). |
| `event_groups.c` (~900 dòng) | | Event group: đồng bộ nhiều task bằng cờ bit. |
| `stream_buffer.c` (~1.800 dòng) | | Stream/message buffer: luồng byte giữa task và ISR. |
| `list.c` (~250 dòng) | | Danh sách liên kết nội bộ cho scheduler/queue. |
| `croutine.c` (~400 dòng) | | Co-routine (cơ chế legacy, ít dùng). |
| `include/` (`task.h` ~3.900 dòng, `queue.h` ~1.900 dòng, `FreeRTOS.h`, `portable.h`...) | | Header công khai: API cho ứng dụng gọi. |

**Lớp port (phụ thuộc chip — phần phải viết/thích ứng cho A76 và R52):**

| Thành phần | Nhiệm vụ | Liên quan tới dự án |
|---|---|---|
| `portable/GCC/ARM_CR5/` (`port.c`, `portASM.S`, `portmacro.h`) | Port cho Cortex-R5 (họ R, gần R52 nhất) | Mẫu để port **R52**: xử lý ngắt, `pxPortInitialiseStack`, tick timer. |
| `portable/GCC/ARM_CA53_64_BIT/` | Port cho Cortex-A53 64-bit (họ A, gần A76 nhất) | Mẫu để port **A76** (AArch64, EL1, GIC). |
| `portable/MemMang/heap_1..5.c` | 5 chính sách cấp phát heap (chọn 1 khi link) | FreeRTOS cần 1 `heap_*.c` trong link; demOS hiện không cần vì stack là mảng tĩnh. |
| `portable/Common/` (`mpu_wrappers.c`) | Wrapper đặc quyền MPU | Chỉ khi dùng MPU. |
| `examples/template_configuration/FreeRTOSConfig.h` | Cấu hình mẫu (`configCPU_CLOCK_HZ`, tick rate, heap size...) | Mỗi board cần 1 bản riêng — tương đương vai trò `config.sh` + các `-DPLAT_*` hiện nay. |

### 3.3 Muốn link FreeRTOS vào ELF thì cần thêm những gì?

1. Viết `FreeRTOSConfig.h` cho từng board (clock, tick rate, heap size).
2. Thêm vào lệnh build: `tasks.c`, `queue.c`, `list.c`, `timers.c`,
   `event_groups.c` (+ `stream_buffer.c` nếu dùng), 1 file `heap_*.c`,
   và `port.c` + `portASM.S` của port tương ứng.
3. Viết/điều chỉnh lớp port: vector ngắt gọi `vTaskSwitchContext`, timer tick,
   `pxPortInitialiseStack` khởi tạo stack của task.
4. Thay `k_os_entry()` trong `kernel.c`: tạo task bằng `xTaskCreate()` rồi gọi
   `vTaskStartScheduler()` thay vì `scheduler_roundrobin()`.
5. Giữ nguyên `uart.c` + boot glue (là "board support" mà FreeRTOS không có).



## 4. Các file source hiện tại: tác dụng và nhiệm vụ từng file

Sơ đồ phụ thuộc giữa 3 file object tạo nên ELF:

```text
start.o (boot glue, assembly) ──bl──> k_os_entry() trong kernel.o
kernel.o ──gọi──> k_puts/k_putdec/k_puthex/k_yield/k_halt trong uart.o
                                      (+ k_stack_push trở lại start.o)
os.h là "hợp đồng" chung: kernel.c và uart.c đều #include nó.
```

### 4.1 `src/boot/start_a76.S` / `start_r52.S` — boot glue (điểm `_start`)

Nhiệm vụ duy nhất: **những lệnh đầu tiên CPU chạy** — dựng stack rồi gọi C.
Không có bootloader trong embedded: QEMU đặt PC = `_start`.

- **a76** (AArch64): `movz/movk x30` tạo hằng `0x40200000`, rồi
  `mov sp, x30` (bắt buộc qua `x30` vì ghi trực tiếp vào thanh ghi 31 bằng
  `movz` sẽ rơi vào XZR và bị bỏ lặng lẽ), `mov x29, sp`, `bl k_os_entry`.
  Disassembly thật trong ELF: `40080000: mov x30, #0x40200000 ... bl 0x40080020`.
- **r52** (Thumb): `ldr sp, =stacktop` (= `0x10020000`), `b reset`, tiếp theo là
  **bảng vector ngoại lệ ở địa chỉ 0** (7 `.word hang`), rồi `reset:` che ngắt
  (`cpsid if`) và `bl k_os_entry`.
- Cả hai đều cung cấp `k_stack_push(top)`: đổi SP sang stack riêng của task
  (a76: `mov sp, x0`; r52: `mov sp, r0`). Đây là "chuyển ngữ cảnh" thô sơ của
  scheduler hợp tác.

Bảng `llvm-nm start.o` chứng minh vai trò "cầu nối": `T _start`, `T hang`,
`T k_stack_push` (định nghĩa, `T` = text), và `U k_os_entry` (`U` = undefined —
chờ linker nối sang `kernel.o`).

### 4.2 `src/kernel/kernel.c` — demOS (scheduler + task + banner)

"Trái tim" OS demo, freestanding (không libc). Từng thành phần:

| Thành phần | Nhiệm vụ |
|---|---|
| `stack0[]/stack1[]` (mỗi mảng 32 `unsigned int` = 128 byte, trong `.bss`) | Stack riêng của 2 task. `llvm-nm` cho thấy `b stack0 @0x40200004`, `b stack1 @0x40200084` (`b` = bss). |
| `tick`, `cnt_a`, `cnt_b` | Đồng hồ scheduler + bộ đếm riêng mỗi task. |
| `area_top(s)` | Tính đỉnh stack: `s + 32` — nguồn địa chỉ cho `k_stack_push`. |
| `k_stack_push(top)` (khai báo `extern`) | "Hàm mượn" từ boot glue — nối ở bước link. |
| `task_a()` / `task_b()` | "2 tiến trình": in 1 dòng (số quantum, địa chỉ stack, từ khóa alpha/beta) rồi nhường CPU. |
| `scheduler_roundrobin()` | Vòng lặp `t = tick % 2`: đổi stack → `k_yield()` → chạy task → sau 16 quanta in `DEMO-OS-OK` và dừng. |
| `print_banner()` | In cpu/máy/UART/stack-top — các chuỗi này lấy từ macro `-DPLAT_*` lúc build, nên cùng 1 mã nguồn mà banner mỗi board khác nhau. |
| `k_os_entry()` | Điểm vào C: banner → scheduler → `k_halt()` (vòng lặp vô hạn). |

Bảng `llvm-nm kernel.o`: `T k_os_entry`, `T k_halt` (tự định nghĩa) và hàng loạt
`U k_putc/k_puts/k_putdec/k_puthex/k_yield/k_stack_push` — **toàn bộ đều là
"lời hứa" chờ linker nối sang `uart.o` và `start.o`**.

### 4.3 `src/kernel/uart.c` — driver console (mắt/miệng của OS)

Không có UART thì OS chạy "mù" — không ai thấy output. File này có 2 bản cài
trong 1 file, chọn lúc build bằng `-DUART_TYPE=1|2`:

| `UART_TYPE` | Chip/bản build | Thanh ghi (offset từ base) |
|---|---|---|
| `1` = PL011 | a76 @ `0x09000000` | DR+0x00, FR+0x18 (bit5 TX-full), CR+0x30, LCRH+0x2c |
| `2` = CMSDK/APB | r52 @ `0xE7C00000` | DATA+0x00, STATE+0x04, CTRL+0x08, BAUD+0x10 |

Cả hai `uart_write(c)`: khởi tạo UART → chờ TX rỗng **có chặn tối đa 64 vòng**
(tránh treo) → ghi ký tự. Trên nó là các hàm tiện ích `k_putc/k_puts/k_crlf/
k_puthex/k_putdec` (in chuỗi, số hex/dec) và `k_yield()` (no-op: điểm nhường
CPU mang tính biểu tượng trong demo hợp tác).

### 4.4 `src/kernel/os.h` — "hợp đồng" giữa các file

Header nhỏ (~20 dòng): khai báo `k_os_entry`, họ `k_put*`, `k_yield`, `k_halt`,
và `#error` bắt buộc `UART_BASE` phải được truyền bằng `-D` lúc build.
Nhờ nó mà `kernel.c` gọi `k_puts()` dù hàm nằm ở file khác — trình biên dịch
tin "sẽ có người định nghĩa", linker sẽ thực hiện lời hứa đó (§5.2).

## 5. Quá trình build và link tạo file `.elf` (đọc `build_one()` trong `run_os.sh`)

Toàn bộ nằm trong hàm `build_one(p)`, 4 bước cho mỗi profile:

```text
start_<p>.S ──clang -c──> start.o ──┐
kernel.c    ──clang -c──> kernel.o ─┼── ld.lld -e _start -T link-<p>.ld ──> os-<p>.elf
uart.c      ──clang -c──> uart.o  ──┘                              └──> os-<p>.list (disasm)
```

### 5.1 Bước 1+2 — compile: 3 file nguồn thành 3 file `.o` độc lập

```sh
clang --target=<triple> <thumbopts> -c src/boot/start_<p>.S -o build/<p>/start.o
clang --target=<triple> <thumbopts> -c -O2 -Wall -Wextra -g -ffreestanding -fno-builtin \
  -DUART_BASE=... -DUART_TYPE=... -DPLAT_CPU=... -DPLAT_MACHINE=... -DPLAT_STACKTOP=... \
  -I src/kernel src/kernel/kernel.c -o build/<p>/kernel.o
# (lặp lại cho uart.c)
```

Ý nghĩa từng mảnh ghép:

- `--target`: chọn CPU đích — a76 = `aarch64-none-elf` (64-bit),
  r52 = `arm-none-eabi` + `-mthumb -march=armv7-a` (32-bit Thumb, vì R52 boot ở
  trạng thái Thumb).
- `-c`: chỉ dịch, không link — mỗi file `.o` còn chứa symbol `U` (undefined).
- `-ffreestanding -fno-builtin` (C): cấm dùng libc/startup của máy Mac —
  đúng chất bare-metal, không `main()`, không syscall.
- `-D...`: "tiêm" thông tin board vào code — cùng 1 mã nguồn mà ra 2 binary
  khác nhau (UART base, tên cpu/máy in banner, đỉnh stack).
- `-g`: giữ thông tin debug (nên `.elf` ~135 KB); bỏ `-g` + `strip` nếu cần gọn.

### 5.2 Bước 3 — link: nối 3 `.o` + xếp địa chỉ thành 1 `.elf`

```sh
ld.lld -o build/<p>/os-<p>.elf -e _start \
  -T toolchain/link-<p>.ld build/<p>/start.o build/<p>/kernel.o build/<p>/uart.o
```

Ba việc linker làm:

1. **Giải symbol `U`**: `k_os_entry` (start.o hứa) ↔ `kernel.o` định nghĩa;
   `k_puts/...` (kernel.o hứa) ↔ `uart.o` định nghĩa;
   `k_stack_push` (kernel.o hứa) ↔ `start.o` định nghĩa. Thiếu 1 `.o` là lỗi
   `undefined symbol` ngay.
2. **Xếp địa chỉ theo linker script** (`-T`): gom mọi `.text*` về
   `0x40080000` (a76) hoặc `0x00000000` (r52), `.rodata` nối sau, `.bss` nhảy
   tới vùng stack (`0x40200000` / `0x10000000`). Bảng `llvm-nm` ở §1 (ví dụ
   `_start @0x40080000`, `stack0 @0x40200004`) chính là kết quả bước này.
3. **Đóng entry point** (`-e _start`): ghi địa chỉ `_start` vào header ELF để
   QEMU biết đặt PC vào đâu. Vì sao không dùng Apple `/usr/bin/ld`? Nó chỉ tạo
   Mach-O (macOS), không tạo được ELF ARM — nên `config.sh` tìm `ld.lld` của
   Homebrew (`lld`, rồi `llvm`, rồi `PATH`).

### 5.3 Bước 4 — kiểm tra: `os-<p>.list` và nạp lên QEMU

`llvm-objdump -d os-<p>.elf > os-<p>.list` cho file disassembly để soi
(`_start` có đúng 5 lệnh dựng SP + `bl k_os_entry` không). Sau đó:

```sh
qemu-system-aarch64 -M virt -cpu cortex-a76 -m 512 \
  -kernel build/a76/os-a76.elf -nographic -serial mon:stdio
```

QEMU đọc program headers, copy `.text`/`.rodata` vào RAM giả lập, zero vùng
`.bss`, đặt PC = entry point → `_start` dựng SP → `k_os_entry()` in banner →
scheduler chạy 16 quanta → `DEMO-OS-OK` → `k_halt()`.



## 6. Tự kiểm chứng + thuật ngữ (5 phút)

```sh
file build/a76/os-a76.elf        # ELF 64-bit ... statically linked
file build/r52/os-r52.elf        # ELF 32-bit ... statically linked
/opt/homebrew/opt/llvm/bin/llvm-readelf -S build/a76/os-a76.elf | grep -E 'text|rodata|bss'
/opt/homebrew/opt/llvm/bin/llvm-nm --print-size build/a76/os-a76.elf | grep -E '_start|k_os_entry|stack0|stack1'
/opt/homebrew/opt/llvm/bin/llvm-objdump -d --disassemble-symbols=_start build/a76/os-a76.elf | head -12
```

| Thuật ngữ | Nghĩa một dòng |
|---|---|
| Compile (`-c`) | Dịch 1 file nguồn thành 1 file object (`.o`), chưa chạy được. |
| Symbol `T` / `U` (trong `llvm-nm`) | `T` = tự định nghĩa (text); `U` = undefined, chờ linker nối. |
| Link | Nối nhiều `.o` + xếp địa chỉ theo linker script → 1 file `.elf`. |
| Linker script (`.ld`) | "Bản đồ bộ nhớ": section nào nằm ở địa chỉ nào. |
| freestanding / `-nostdlib` | Không dùng libc/startup của hệ host — đúng chất bare-metal. |
| Entry point (`-e _start`) | Symbol mà QEMU nhảy vào đầu tiên khi boot. |
| `.bss` (`NOBITS`, `FileSiz=0`) | Vùng RAM zero, không chiếm chỗ trong file. |


