# Hướng dẫn build FreeRTOS bằng `build_freertos.sh` + chạy bằng `run_freertos_qemu.sh`

> Tài liệu thực hành riêng cho **cặp script FreeRTOS của repo này**.
> Tài liệu lý thuyết tổng quát nằm ở `FREERTOS-BUILD-RUN.md`;
> cấu trúc toàn repo nằm ở `HUONG-DAN-CHI-TIET.md`;
> bản chất file ELF nằm ở `IMAGE-OS-ELF.md`.

## 1. Tổng quan: 2 script làm gì, đứng ở đâu trong pipeline

```
./run_os.sh setup            # 1 lần duy nhất: qemu + clang + ld.lld
./run_os.sh get free-rtos    # 1 lần duy nhất: clone extern/FreeRTOS-Kernel (V11.3.x)
./build_freertos.sh a76      # build image FreeRTOS  <- FILE 1 (tài liệu này)
./run_freertos_qemu.sh a76   # chạy image trên QEMU  <- FILE 2 (tài liệu này)
```

| Script | Vai trò | Input | Output |
|---|---|---|---|
| `build_freertos.sh [a76\|r52\|all\|clean]` | **Sinh mã glue + biên dịch + link** ra ELF FreeRTOS | `src/kernel/uart.c`, `src/boot/start_a76.S`, `extern/FreeRTOS-Kernel/*` | `build/<p>/os-<p>-freertos.elf` (+ `.list`) và `src/freertos/*` (tự sinh) |
| `run_freertos_qemu.sh [a76\|r52] [smoke N\|-a]` | **Nạp ELF vào QEMU** (tương tác hoặc headless) | `build/<p>/os-<p>-freertos.elf` | Serial log trên terminal hoặc `build/<p>/freertos-smoke.log` |

Điểm khác với `run_os.sh build`: `run_os.sh` chỉ build **demOS** (3 file
`start/kernel/uart.o`); còn `build_freertos.sh` build **FreeRTOS thật**
(tasks/list/queue/heap/port + glue), tái dùng `uart.c` + `start_a76.S` làm
board-support, và đặt tên output riêng `os-<p>-freertos.elf` để chạy song song
với demOS cũ.

Điều kiện tiên quyết (script tự kiểm tra và báo lỗi rõ ràng nếu thiếu):

1. `extern/FreeRTOS-Kernel/.git` tồn tại (chưa có → `./run_os.sh get free-rtos`);
2. `CLANG` biên dịch được freestanding, `LLD` (`ld.lld`) thực thi được
   (chưa có → `./run_os.sh setup`).

## 2. `build_freertos.sh`: cách dùng

```sh
./build_freertos.sh a76      # mặc định cũng là a76 khi không truyền tham số
./build_freertos.sh r52
./build_freertos.sh all      # build cả 2 profile
./build_freertos.sh clean    # xóa artifact freertos (GIỮ demOS os-<p>.elf)
V=1 ./build_freertos.sh a76  # in từng lệnh clang/ld.lld (dùng khi debug)
```

Kết quả sau khi chạy (ví dụ `a76`):

```
build/a76/os-a76-freertos.elf   (~186K, gồm debug -g)
build/a76/os-a76-freertos.list  (disassembly llvm-objdump)
build/a76/f_*.o                 (object trung gian: f_tasks.o, f_port.o, ...)
build/a76/FreeRTOSConfig.h      (bản copy của FreeRTOSConfig-a76.h)
src/freertos/*                  (mã glue TỰ SINH — xem §3, commit được)
```
## 3. Bên trong `build_freertos.sh`: 2 giai đoạn (sinh mã → biên dịch/link)

### 3.1 Giai đoạn 1 — sinh mã glue vào `src/freertos/` (9 hàm `gen_*`)

Script **ghi đè toàn bộ** thư mục `src/freertos/` mỗi lần chạy (trừ `compat/`
do bạn viết tay — xem §4.4). Mỗi hàm `gen_*` sinh đúng 1 file:

| Hàm sinh | File ra | Nội dung 1 dòng | Vì sao phải sinh (không vendor sẵn) |
|---|---|---|---|
| `gen_config_a76` / `gen_config_r52` | `FreeRTOSConfig-{a76,r52}.h` | Toàn bộ `config*`/`INCLUDE_*` + hook tick + `configASSERT` | Mỗi profile khác tick/GIC/word-size/heap; để config cạnh code cho dễ review |
| `gen_vectors_a76` | `vectors_a76.S` | Bảng vector AArch64 16 ô × 128 B: ô 0 → `FreeRTOS_SWI_Handler` (SVC/yield), ô 1 → `FreeRTOS_IRQ_Handler`, còn lại → `hang_a76` | Port `ARM_AARCH64` cần VBAR_EL1 do app cung cấp; phải `.align 11` (2 KB) |
| `gen_vectors_r52` | `vectors_r52.S` | Bảng vector A32 8 entry ở địa chỉ 0 + `reset_r52` (hạ EL2→EL1, đặt SP_SVC/SP_IRQ, VBAR) + `hang_r52` | Thay `start_r52.S` của demOS: port chỉ chạy ở EL1, còn QEMU boot ở EL2/HYP |
| `gen_tick_a76` | `freertos_tick_a76.c` | GICv2 (`GICD 0x08000000`/`GICC 0x08010000`) + Generic Timer vật lý (`CNTP_TVAL/CNTP_CTL`, PPI30) | `configSETUP/CLEAR_TICK_INTERRUPT` là macro do port gọi — mỗi board 1 driver |
| `gen_tick_r52` | `freertos_tick_r52.c` | GICv3 (`GICD 0xF0000000`/`GICR 0xF0100000`, `ICC_IAR1/EOIR1_EL1`) + CNTP (PPI14 = INTID 30), tự đọc IAR + tự ghi EOI thật | Port viết kiểu VIC chỉ ghi scratch `configEOI_ADDRESS`; GICv3 không có EOI MMIO |
| `gen_hooks` | `hooks.c` | `vAssertCalled` + `vApplicationStackOverflowHook/MallocFailedHook` + `...GetIdleTaskMemory/...GetTimerTaskMemory` (in qua UART) | Linker báo thiếu nếu `configCHECK_FOR_STACK_OVERFLOW=2`/`MALLOC_FAILED_HOOK=1`/`SUPPORT_STATIC_ALLOCATION=1` mà không viết |
| `gen_libc` | `libc_mini.c` | `memset/memcpy/memcmp/strlen/strcpy/strcmp` viết tay | `-nostdlib`: kernel và clang (vd. `memset` cho TCB) đều cần, nhưng không có libc |
| `gen_libgcc` | `libgcc_r52.c` (chỉ r52) | `__aeabi_uidiv/uidivmod/idiv/idivmod` bằng thuật toán dịch+trừ 32 vòng | `armv7-a` không bắt buộc có lệnh chia; `tasks.c` chia cho biến → clang gọi helper |
| `gen_app` | `app_main.c` | `vPortEnableFPU()` → banner → `xQueueCreate(8)` → 2 task prod/cons → `vTaskStartScheduler()` | App mẫu bring-up: chứng minh scheduler + queue + tick đều sống |

### 3.2 Giai đoạn 2 — biên dịch + link trong `build_one_freertos()` (5 bước)

Điều khiển chung: `V=1` in từng lệnh; `run()` bọc mọi lệnh; `die()` dừng khi
thiếu công cụ. Profile lấy từ `config.sh` qua `pcfg` (triple/thumb/uart/
stacktop/ld — xem `HUONG-DAN-CHI-TIET.md` §4).

**Bước 1 — board support (tái dùng từ demOS):**

- Boot: `start_a76.S` cho a76; với r52 thì `vectors_r52.S` **đóng vai trò boot**
  (không dùng `src/boot/start_r52.S`), nhưng vẫn assemble ra `start.o`.
  Chú ý: file `.S` assemble bằng `$cflags` (**có `-x assembler-with-cpp`**)
  vì chứa `#if`, còn file `.c` dùng `$cflags_c` (không cần tiền xử lý asm).
- UART: `src/kernel/uart.c` với `-DUART_BASE/-DUART_TYPE/-DPLAT_*` — driver
  console dùng chung cho `k_puts/k_putdec` trong hooks và app.

**Bước 2 — nhân FreeRTOS (chung 2 profile):** `tasks.c + list.c + queue.c`
(`timers/event/stream/croutine` tắt ở config nên **không biên dịch**) và đúng
**1 file heap**: `heap_1.c` (`HEAP_A76`), `heap_4.c` (`HEAP_R52`).
Include gồm 4 `-I`: `extern/FreeRTOS-Kernel/include`,
`portable/GCC/<PORT>`, `src/freertos` (cho `FreeRTOSConfig.h` copy),
`src/freertos/compat` (stdio/stdlib/string.h tối thiểu) + `src/kernel`
(cho `os.h`).

**Bước 3 — port (riêng từng profile):** `port.c` biên dịch như C thường;
`portASM.S` biên dịch bằng `$cflags` (assembler-with-cpp). Riêng a76 thêm
`-DGUEST -DQEMU` (port chạy ở EL1/SVC thay vì EL3/SVC).

**Bước 4 — glue:** a76 biên dịch `freertos_tick_a76.c + vectors_a76.S`;
r52 biên dịch `freertos_tick_r52.c + libgcc_r52.c` (không có `vectors*.o`
riêng vì vector nằm chung trong `start.o`); cả 2 đều biên dịch
`hooks.c + app_main.c`.

**Bước 5 — link:** kiểm tra `$LLD` thực thi được, rồi:

```sh
"$LLD" -o build/<p>/os-<p>-freertos.elf -e _start \
    -T toolchain/link-<p>.ld  <toàn bộ .o 5 nhóm trên>
llvm-objdump -d ... > build/<p>/os-<p>-freertos.list
```

Vị trí bộ nhớ giữ nguyên demOS (`.ld` không đổi): a76 `.text @0x40080000`,
`.bss @0x40200000`; r52 `.text @0x0`, `.data/.bss @0x10000000`,
`.eoi_scratch @0x1001C000`. R52 in thêm NOTE nhắc EOI thật do
`vApplicationIRQHandler` ghi `ICC_EOIR1_EL1`.

## 4. Từng file glue trong `src/freertos/`: nhiệm vụ và điểm cần nhớ

### 4.1 `FreeRTOSConfig-{a76,r52}.h` — cấu hình (đọc kỹ nhất)

Nhóm chung 2 profile: `TICK_RATE_HZ=100`, `MAX_PRIORITIES=5`,
`MINIMAL_STACK_SIZE` (a76: 256 word-64 / r52: 128 word-32),
`TOTAL_HEAP_SIZE` (64 KB / 32 KB), `MUTEXES=1`, `COUNTING_SEMAPHORES=1`,
`TASK_NOTIFICATIONS=1`, timer/event/stream/co-routine = 0,
`CHECK_FOR_STACK_OVERFLOW=2` + `MALLOC_FAILED_HOOK=1` + `configASSERT`
(in file:dòng qua UART rồi treo — bring-up bật hết).
Nhóm riêng a76 (`ARM_AARCH64`, `TICK_TYPE 64-bit`): 4 macro GIC
(`BASE 0x08000000`, `CPU_OFFSET 0x10000`, `UNIQUE_PRIO 32`,
`MAX_API_CALL 18`) + `SETUP/CLEAR_TICK` → `vSetup/ClearTickInterruptA76` +
`TASK_FPU_SUPPORT=2` + `GUEST/QEMU`.
Nhóm riêng r52 (`ARM_CRx_No_GIC`, `TICK_TYPE 32-bit`): chỉ 2 macro tick
(`SETUP/CLEAR` → `...R52`) + `configEOI_ADDRESS=0x1001C000` (phải khớp
`.eoi_scratch` trong `link-r52.ld`).
`configCPU_CLOCK_HZ=62.5 MHz` chỉ là dự phòng (tick driver đọc `CNTFRQ`
thật, QEMU R52 = 62.5 MHz theo `target/arm/cpu.c`).

### 4.2 `app_main.c` — app mẫu và `k_os_entry()` (điểm vào C)

Luồng: `vPortEnableFPU()` **đầu tiên** (mở `CPACR.FPEN` a76 /
`CP10+CP11` r52 — clang `-O2` vector hóa `memset` thành `dup v0.16b`,
sau reset FP tắt nên không mở là Undefined Instruction) → in
`freertos bring-up` → `xQueueCreate(8, sizeof(unsigned))` + `configASSERT`
→ `xTaskCreate(vProd, prio 2)` + `xTaskCreate(vCons, prio 1)`, stack 256 →
`vTaskStartScheduler()` (không bao giờ trở về; dòng `configASSERT(0)` sau
nó chỉ bắt lỗi bring-up). Prod gửi số tăng dần mỗi 200 ms
(`xQueueSend` + `vTaskDelay(pdMS_TO_TICKS(200))` — cần `INCLUDE_vTaskDelay=1`),
cons nhận và in `got N` (`xQueueReceive` + `k_putdec` — cần queue).

### 4.3 `freertos_tick_{a76,r52}.c` — driver tick (1 ngắt/10 ms)

A76 (GICv2 + Generic Timer vật lý): `vSetupTickInterruptA76` đọc `CNTFRQ_EL0`
(tự dự phòng `configCPU_CLOCK_HZ`), tính `reload = freq/100`, dựng
`GICD_CTLR=3/GICC_CTLR=1/PMR=0xFF`, ưu tiên tick `0xF0` cho PPI30,
enable PPI30, nạp `CNTP_TVAL` + bật timer; `vClearTickInterruptA76` nạp lại
`TVAL` (hạ ISTATUS, hẹn tick kế); `vApplicationIRQHandler(IAR)` lọc
`id == 30` rồi gọi `FreeRTOS_Tick_Handler()` — **không đọc lại IAR**
(lần 2 trả 1023 = spurious), **không tự ghi EOIR** (portASM.S làm).
R52 (GICv3 + CNTP, PPI14 = INTID 30): thêm bước `WAKER` (đánh thức
redistributor), `IGROUPR0` (tick → Group1 vì AN536 non-secure-only),
`ISENABLER0`, `IPRIORITYR` (`0x00` = cao nhất — **ngược chiều GICv2**);
CP15 inline (`c14` timer, `c4/c12` GIC CPU interface);
`vApplicationIRQHandler()` **tự đọc `ICC_IAR1_EL1` + tự ghi `ICC_EOIR1_EL1`**
vì portASM.S kiểu VIC chỉ ghi scratch (lọc `1023`, clear tick trước EOI).

### 4.4 `vectors_{a76,r52}.S`, `hooks.c`, `libc_mini.c`, `libgcc_r52.c`, `compat/`

- `vectors_a76.S` (16 ô × 128 B, `.align 11`): các ô SVC/IRQ trỏ vào
  `FreeRTOS_SWI_Handler`/`FreeRTOS_IRQ_Handler` của port, ô còn lại lặp 4 nhóm
  EL/SP → `hang_a76`; `VBAR_EL1` được `xPortStartScheduler` trỏ vào bảng này.
- `vectors_r52.S` (A32, `.arm`, `.arch_extension virt`): 8 entry ở địa chỉ 0
  (`SVC → FreeRTOS_SVC_Handler`, `IRQ → FreeRTOS_IRQ_Handler`, còn lại
  `hang_r52`); `reset_r52` phát hiện HYP qua CPSR, `ERET` về EL1/SVC (kèm
  `CPTR_EL2=0`, `CNTHCTL_EL2=3` mở FP+timer cho EL1), rồi đặt `SP_SVC`
  (`0x10020000`), `VBAR`, `SP_IRQ` (`0x1001F000`) vì port vào IRQ mode và PUSH.
- `hooks.c`: 3 hook in qua UART rồi `taskDISABLE_INTERRUPTS` + treo
  (`STACK-OVF` kèm tên task, `MALLOC-FAIL`, `ASSERT` kèm file:dòng) và 2 hàm
  cấp phát tĩnh cho idle/timer task (bắt buộc khi `STATIC_ALLOCATION=1`).
- `libc_mini.c`: 6 hàm C thuần vòng lặp byte (không gọi lại chính mình —
  tránh đệ quy qua `memset` của compiler).
- `libgcc_r52.c` (chỉ r52): phép chia `__aeabi_*` bằng restoring-division
  32 vòng, chia 0 trả 0, bản có dấu theo C99 (quotient tròn về 0).
- `compat/{stdio,stdlib,string}.h` (viết tay, **không bị ghi đè**): khai báo
  tối thiểu cho `tasks.c` (`NULL/size_t`, `memset/memcpy...`, `sprintf`
  khi bật stats) — thiếu là lỗi `implicit declaration`.

## 5. `run_freertos_qemu.sh`: cách chạy image trên QEMU

```sh
./run_freertos_qemu.sh a76            # tương tác: serial → terminal (Ctrl-A X thoát)
./run_freertos_qemu.sh a76 smoke 6    # headless 6 s → build/a76/freertos-smoke.log
./run_freertos_qemu.sh r52 smoke 6    # tương tự cho R52
./run_freertos_qemu.sh a76 -a         # thử HVF accel (chỉ a76; smoke không dùng -a)
./run_freertos_qemu.sh help           # in trợ giúp
```

Mặc định profile là `a76` khi không truyền tham số. Script đọc `qemu/machine/
ram/cpu` từ `config.sh` (`a76: qemu-system-aarch64 -M virt -cpu cortex-a76
-m 512`; `r52: qemu-system-arm -M mps3-an536 -m 256`), kiểm tra
`build/<p>/os-<p>-freertos.elf` tồn tại (thiếu → báo chạy `build_freertos.sh`),
rồi `exec QEMU -kernel <elf> -nographic -serial mon:stdio` (tương tác) hoặc
chạy nền `-display none -serial file:...`, `sleep N`, `kill`, in log (smoke).

Output thành công (a76, đã kiểm chứng): banner `freertos bring-up` rồi
`got 0 ... got 24` đều nhịp 200 ms — chứng minh tick (100 Hz) + scheduler +
queue đều sống. R52 hiện chỉ tới `freertos bring-up` (tick/GICv3 trên AN536
vẫn đang bring-up — xem `FREERTOS-BUILD-RUN.md` §4.3/§6).

## 6. Sơ đồ luồng tổng + ví dụ log + sự cố thường gặp

```
build_freertos.sh a76
  └─ gen_* → src/freertos/ (config, vectors, tick, hooks, libc, app)
  └─ build_one_freertos a76
       ├─ clang -c (board: start_a76.S, uart.c)
       ├─ clang -c (nhân: tasks/list/queue/heap_1 + port/portASM -DGUEST -DQEMU)
       ├─ clang -c (glue: tick_a76, vectors_a76, hooks, app)
       └─ ld.lld -e _start -T link-a76.ld → build/a76/os-a76-freertos.elf
run_freertos_qemu.sh a76 smoke
  └─ qemu-system-aarch64 -M virt -cpu cortex-a76 -kernel os-a76-freertos.elf
       └─ _start → k_os_entry → prod/cons → "got N" (UART 0x09000000)
```

Ví dụ log thật (`./run_freertos_qemu.sh a76 smoke 6 | tail -5`):

```text
got 20
got 21
got 22
got 23
got 24
```

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| `FreeRTOS-Kernel chua co` | Chưa clone `extern/` | `./run_os.sh get free-rtos` |
| `thieu ld.lld` / `clang ... failed` | Thiếu toolchain | `./run_os.sh setup` |
| `image missing` (run) | Chưa build profile đó | `./build_freertos.sh <p>` |
| `undefined: __aeabi_uidiv` (r52) | Thiếu helper chia | `libgcc_r52.c` đã có trong build — không xóa bước 4 |
| `undefined: memset/...` | Thiếu libc tối thiểu | `libc_mini.c` + `compat/*.h` đã có trong build |
| `undefined: vApplication...` | Thiếu hook | `hooks.c` đã có trong build; bật config nào thì viết hook đó |
| Treo sau `freertos bring-up` (a76) | Tick/GIC sai (IAR đọc 2 lần, PMR mask, TVAL chưa nạp) | So `freertos_tick_a76.c` với §4.3; `V=1` + GDB break `FreeRTOS_Tick_Handler` |
| R52 chỉ tới banner | GICv3/AN536 bring-up | Xem `FREERTOS-BUILD-RUN.md` §4.3; a76 không bị ảnh hưởng |

Quy tắc sửa đổi an toàn: **không sửa file trong `extern/`** (upstream);
mọi tùy biến nằm ở `build_freertos.sh` (hàm `gen_*`, `HEAP_*`, `PORTDIR_*`,
`cflags`) + `compat/*.h` + `config.sh` (`pcfg`). Đổi `configEOI_ADDRESS`
phải đổi cả `.eoi_scratch` trong `link-r52.ld`; đổi base UART/stack phải đổi
cả `config.sh` + `.ld` + boot asm.

