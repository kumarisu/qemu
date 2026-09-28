# FreeRTOS-Kernel: chức năng, cấu hình, build image và chạy trên QEMU/phần cứng

> Tài liệu end-to-end cho dự án `os-emu`: **FreeRTOS-Kernel làm được gì →
> cấu hình chung (không phụ thuộc phần cứng) → cấu hình riêng theo chip →
> build image `.elf` → nạp và chạy trên QEMU và trên board thật.**
> Đọc trước: `IMAGE-OS-ELF.md` (§3: vì sao FreeRTOS hiện chưa nằm trong ELF;
> §5: pipeline `build_one()` mà tài liệu này sẽ mở rộng).

**Phạm vi và quy ước:** repo bạn đang vendor FreeRTOS-Kernel **V11.3.x**
(xem `extern/FreeRTOS-Kernel/History.txt`). Mọi đường dẫn dưới đây tính từ gốc
`os-emu/`, trừ khi ghi rõ `extern/FreeRTOS-Kernel/...` (viết tắt là `FR/`).
"demOS" = OS mini hiện tại trong `src/`; "image FreeRTOS" = ELF tương lai sau
khi link FreeRTOS vào (thay demOS, giữ driver UART + boot glue).

---

## 0. Mục lục

1. [Chức năng từng thành phần FreeRTOS-Kernel](#1-chức-năng-từng-thành-phần-freertos-kernel)
2. [Chuẩn bị: toolchain, thư mục, lấy source](#2-chuẩn-bị-toolchain-thư-mục-lấy-source)
3. [Cấu hình chung (không phụ thuộc phần cứng)](#3-cấu-hình-chung-không-phụ-thuộc-phần-cứng)
4. [Cấu hình riêng theo phần cứng (A76 và R52)](#4-cấu-hình-riêng-theo-phần-cứng-a76-và-r52)
5. [Build image: thêm file nào, sửa build ra sao, ví dụ app tối thiểu](#5-build-image-thêm-file-nào-sửa-build-ra-sao-ví-dụ-app-tối-thiểu)
6. [Nạp và chạy trên QEMU](#6-nạp-và-chạy-trên-qemu)
7. [Nạp và chạy trên phần cứng thật](#7-nạp-và-chạy-trên-phần-cứng-thật)
8. [Checklist tổng + thuật ngữ](#8-checklist-tổng--thuật-ngữ)

---

## 1. Chức năng từng thành phần FreeRTOS-Kernel

### 1.1 Nhân lõi (7 file C ở gốc `FR/`, ~17.000 dòng, độc lập CPU)

| File (dòng) | Chức năng | API chính cho app | Có cần trong build? |
|---|---|---|---|
| `tasks.c` (~9.000) | Scheduler preemptive: tạo/xóa/suspend task, ưu tiên 0..MAX-1, time-slicing, tick count, task notification, idle task | `xTaskCreate`, `vTaskDelete/Delay/Suspend/Resume`, `vTaskStartScheduler`, `xTaskGetTickCount` | **Bắt buộc** |
| `list.c` (~250) | Danh sách liên kết nội bộ (ready/delayed/event lists) mà scheduler và queue dùng | (nội bộ, app không gọi trực tiếp) | **Bắt buộc** |
| `queue.c` (~3.400) | Hàng đợi + toàn bộ semaphore/mutex (binary, counting, recursive, mutex priority-inheritance) + queue set | `xQueueCreate/Send/Receive`, `xSemaphoreCreateBinary/Mutex/Take/Give`, `xQueueCreateSet` | Nên có; bỏ được nếu app không dùng IPC (tiết kiệm ~vài KB flash) |
| `timers.c` (~1.300) | Software timer chạy trong "timer daemon task" | `xTimerCreate/Start/Stop/ChangePeriod`, `xTimerPendFunctionCall` | Chỉ khi `configUSE_TIMERS=1` |
| `event_groups.c` (~900) | Đồng bộ nhiều task bằng 24 cờ bit + rendezvous (`xEventGroupSync`) | `xEventGroupCreate/WaitBits/SetBits/Sync` | Chỉ khi `configUSE_EVENT_GROUPS=1` |
| `stream_buffer.c` (~1.800) | Luồng byte task↔task/task↔ISR + message buffer (mỗi message kèm độ dài) | `xStreamBufferCreate/Send/Receive`, `xMessageBufferCreate/...` | Chỉ khi `configUSE_STREAM_BUFFERS=1` |
| `croutine.c` (~400) | Co-routine (cơ chế legacy, stack chung, đã lỗi thời) | `xCoRoutineCreate` | **Không dùng** (`configUSE_CO_ROUTINES=0`) |

> Quan hệ phụ thuộc: `queue.c`, `timers.c`, `event_groups.c`, `stream_buffer.c`
> đều gọi sang `tasks.c`/`list.c`. Vì vậy **tập tối thiểu luôn là
> `tasks.c + list.c + 1 file heap + port`**; thêm file nào thì bật config
> tương ứng (§3).


### 1.2 Header công khai (`FR/include/`, app chỉ `#include` 2–3 file)

| Header | Chức năng |
|---|---|
| `FreeRTOS.h` | Cổng vào: include `FreeRTOSConfig.h` + `portable.h`, định nghĩa kiểu `BaseType_t/TickType_t`, macro `pdTRUE/pdFALSE/pdMS_TO_TICKS`. **Mọi file C dùng FreeRTOS đều include file này đầu tiên.** |
| `task.h` | Toàn bộ API task + scheduler + notification. |
| `queue.h` | API queue (app thường không include trực tiếp mà qua `semphr.h`). |
| `semphr.h` | Macro tiện ích semaphore/mutex dựng trên queue (`vSemaphoreCreateBinary`, `xSemaphoreTake/Give`...). |
| `timers.h` / `event_groups.h` / `stream_buffer.h` / `message_buffer.h` | API từng module §1.1. |
| `portable.h` | Cầu nối kernel→port: khai báo `pxPortInitialiseStack`, `vPortStartScheduler`, `vPortEnter/ExitCritical`... mà mỗi port phải cài. |
| `mpu_wrappers.h`, `mpu_prototypes.h` | Chỉ khi dùng MPU (`ARM_CM*_MPU`, `ARM_CRx_MPU`). |

### 1.3 Quản lý bộ nhớ (`FR/portable/MemMang/heap_*.c` — chọn ĐÚNG 1 file khi link)

FreeRTOS không gọi `malloc()` của libc; toàn bộ TCB/stack/queue lấy từ 1 mảng
heap tĩnh (`ucHeap[]` nằm trong `.bss`, kích thước `configTOTAL_HEAP_SIZE`).

| File | Thuật toán | free()? | Gợi ý dùng |
|---|---|---|---|
| `heap_1.c` | Cấp phát tuyến tính, con trỏ chỉ tiến | Không | Demo đơn giản nhất: tạo mọi object lúc khởi động rồi thôi. **Gợi ý cho bring-up đầu tiên.** |
| `heap_2.c` | Best-fit, có thu hồi nhưng không gộp khối kề | Có | Legacy, tránh dùng mới. |
| `heap_3.c` | Bọc `malloc/free` của libc (`newlib-freertos.h`) | Có | Chỉ khi đã có libc đầy đủ (không phải trường hợp bare-metal này). |
| `heap_4.c` | First-fit + gộp khối kề (coalescence), chống phân mảnh | Có | **Lựa chọn mặc định cho sản phẩm.** Cần `configTOTAL_HEAP_SIZE` vừa RAM. |
| `heap_5.c` | Như heap_4 + heap nằm rải rác nhiều vùng (`HeapRegion_t` qua `vPortDefineHeapRegions`) | Có | Khi RAM chia nhiều bank (ví dụ TCM + SRAM ngoài). |

### 1.4 Lớp port — phần duy nhất phụ thuộc CPU/board (chi tiết ở §4)

Mỗi port gồm đúng 3 file: `port.c` (C: khởi tạo stack task, tick handler,
quản lý ngắt), `portASM.S` (assembly: save/restore ngữ cảnh, `vPortYield`,
handler SVC/IRQ), `portmacro.h` (định nghĩa kiểu `StackType_t`, critical
section, `portYIELD`). Xem `FR/portable/GCC/`: `ARM_AARCH64` (AArch64 chung,
dùng cho **A76**), `ARM_CRx_No_GIC` (Cortex-R không GIC, dùng cho **R52**),
`ARM_CR5`/`ARM_CA53_64_BIT` (bản có GIC — chỉ tham khảo).

### 1.5 Hook/callback do ứng dụng cung cấp (linker sẽ báo thiếu nếu bật mà không viết)

`vApplicationStackOverflowHook` (`configCHECK_FOR_STACK_OVERFLOW=1`),
`vApplicationMallocFailedHook` (`configUSE_MALLOC_FAILED_HOOK=1`),
`vApplicationIdleHook` / `vApplicationTickHook`,
`vApplicationGetIdleTaskMemory` + `vApplicationGetTimerTaskMemory`
(bắt buộc khi `configSUPPORT_STATIC_ALLOCATION=1` và tắt dynamic).
`configASSERT(x)` nên định nghĩa thành: tắt ngắt + in file/dòng qua UART rồi
treo — đây là công cụ debug số 1 khi bring-up.

### 1.6 Kiến trúc ứng dụng: `main()` kiểu FreeRTOS trông thế nào

```c
#include "FreeRTOS.h"   /* luôn đầu tiên */
#include "task.h"
#include "queue.h"

static void vBlinkTask( void *pv ) {   /* thân task: vòng lặp vô hạn */
    for( ;; ) {
        uart_puts( "tick\r\n" );
        vTaskDelay( pdMS_TO_TICKS( 500 ) );  /* ngủ 500 ms, nhường CPU */
    }
}
int main( void ) {                     /* điểm vào C do boot glue gọi */
    uart_init();                       /* 1. khởi tạo phần cứng tối thiểu */
    xTaskCreate( vBlinkTask, "blink", 256, NULL, 1, NULL );  /* 2. tạo task */
    vTaskStartScheduler();             /* 3. BẮT ĐẦU scheduler — không bao giờ trở về */
    for( ;; );                         /* tới đây = hết heap (xem §5.4) */
}
```

Khác demOS ở 3 điểm: task **ngủ thật** (`vTaskDelay`) thay vì yield biểu tượng;
scheduler **preemptive** (ngắt tick cướp CPU, code chạy trong
`FreeRTOS_Tick_Handler` của port); IPC/đồng bộ có sẵn thay vì biến toàn cục.



## 2. Chuẩn bị: toolchain, thư mục, lấy source

### 2.1 Công cụ theo hệ điều hành máy build (host)

| Thành phần | macOS (repo hiện tại) | Linux (Ubuntu/Debian) | Windows |
|---|---|---|---|
| Trình biên dịch C/ASM | `clang` (Apple CLT) + `brew install llvm` (lấy triple `aarch64-none-elf`/`arm-none-eabi`) | `clang` + `llvm`, hoặc `gcc-arm-none-eabi` + `gcc-aarch64-linux-gnu` (chú ý flag khác `run_os.sh` một chút) | WSL2 Ubuntu rồi làm như cột Linux (khuyên dùng); hoặc LLVM/ARM-GCC native + QEMU Windows |
| Linker ELF | `brew install lld` → `ld.lld` (Apple `/usr/bin/ld` chỉ ra Mach-O, **không dùng được**) | `ld.lld` (gói `lld`) hoặc `arm-none-eabi-ld`/`aarch64-elf-ld` | theo toolchain đã chọn |
| Giả lập | `brew install qemu` (`qemu-system-aarch64`, `qemu-system-arm`) | `apt install qemu-system-arm qemu-system-aarch64` | `qemu` Windows hoặc trong WSL2 |
| Kiểm tra 1 lệnh | `./toolchain/setup.sh --no-install` | tương tự (cần sửa `config.sh` nếu dùng GNU ld) | trong WSL2 |

Cài tự động trên macOS: `./toolchain/setup.sh` (thiếu gì `brew install` nấy).

### 2.2 Lấy source FreeRTOS và dựng khung thư mục

```sh
./run_os.sh get free-rtos        # clone FreeRTOS-Kernel V11.3.x vào extern/ (đã .gitignore)
```

Khung thư mục đề xuất cho image FreeRTOS (giữ nguyên mọi thứ hiện có, chỉ thêm):

```text
os-emu/
├── src/boot/start_a76.S, start_r52.S   # GIỮ NGUYÊN (boot glue, _start)
├── src/kernel/uart.c, os.h             # GIỮ NGUYÊN (driver UART 2 loại)
├── src/kernel/kernel.c                 # THAY: demOS -> main() FreeRTOS (§5.3)
├── src/freertos/                      # MỚI: FreeRTOSConfig-a76.h, FreeRTOSConfig-r52.h,
│                                       #       freertos_tick_a76.c/.h (setup tick), hooks.c
├── toolchain/link-a76.ld, link-r52.ld  # MỞ RỘNG: thêm PROVIDE(__stack...), giữ địa chỉ cũ
├── run_os.sh, config.sh                # MỞ RỘNG: thêm danh sách file FreeRTOS vào build_one()
└── extern/FreeRTOS-Kernel/             # vendor, không sửa (nâng cấp bằng git pull)
```

> Quy tắc vàng: **không sửa file trong `extern/`** — mọi cái riêng của board
> nằm ở `src/freertos/` và `config.sh`. Nâng cấp FreeRTOS = `git pull` trong

## 3. Cấu hình chung (không phụ thuộc phần cứng)

Đây là các macro trong `FreeRTOSConfig.h` có **ý nghĩa giống nhau trên mọi chip**;
đặt giá trị theo nhu cầu ứng dụng, rồi 2 board dùng chung (§4 chỉ override phần cứng).

### 3.1 Nhóm bắt buộc phải hiểu (sai là không chạy)

| Macro (giá trị gợi ý bring-up) | Ý nghĩa, cách chọn |
|---|---|
| `configCPU_CLOCK_HZ` (A76/QEMU virt: `62500000`; R52/mps3: `20000000`) | Tần số CPU mà driver tick dùng để tính số đếm. Trên QEMU virt timer chạy 62.5 MHz; AN536 chạy 20 MHz. Sai số này → tick nhanh/chậm sai tỉ lệ, `vTaskDelay(500ms)` thành dài/ngắn bất thường. |
| `configTICK_RATE_HZ` (`100`) | Tần số ngắt tick: 100 Hz = mỗi 10 ms scheduler xét lại 1 lần. 100–1000 phổ biến; tick càng nhanh càng mượt nhưng tốn CPU vào ngắt. `pdMS_TO_TICKS(ms)` đổi ms→tick từ số này. |
| `configMAX_PRIORITIES` (`5`) | Số mức ưu tiên (0 = thấp nhất). Task chỉ cần 0..4. Càng nhiều càng tốn RAM cho mỗi TCB? Không — tốn ở bảng ready (mảng con trỏ), nhưng vẫn nên để nhỏ (5–8). `configUSE_PORT_OPTIMISED_TASK_SELECTION=1` đòi `<= 32`. |
| `configMINIMAL_STACK_SIZE` (`128`) | Stack idle task, **đơn vị WORD** (128 = 512 byte AArch64). Dùng làm mẫu cho task mới; task có `printf`/đệ quy cần 256–512. Stack overflow là lỗi bring-up số 1 → bật `configCHECK_FOR_STACK_OVERFLOW=2`. |
| `configTOTAL_HEAP_SIZE` (`8192` bring-up; `16384+` sản phẩm) | Tổng heap cho TCB/stack/queue/timer, **byte**, nằm trong `.bss`. Công thức ước lượng: `số_task × (TCB ~200B + stack×4) + queue/timer + dự phòng 30%`. Hết heap → `xTaskCreate` trả `pdFAIL`, `vTaskStartScheduler` treo ở `configASSERT`. |
| `configUSE_PREEMPTION` (`1`) | `1` = preemptive (tick cướp CPU theo ưu tiên — chuẩn RTOS); `0` = cooperative (giống demOS, chỉ đổi task khi task tự nhường). Luôn để `1` trừ khi debug. |
| `configUSE_TIME_SLICING` (`1`) | `1` = các task cùng ưu tiên chia lát CPU mỗi tick (công bằng). Tắt (`0`) chỉ khi muốn task chạy tới khi chặn/nhường. |
| `configSUPPORT_DYNAMIC_ALLOCATION` (`1`) / `configSUPPORT_STATIC_ALLOCATION` (`1`) | Bật cả hai khi bring-up (dễ viết `xTaskCreate` động + vẫn có idle/timer tĩnh). Chỉ dùng static (`0/1`) cho sản phẩm an toàn (không `pvPortMalloc` runtime) — nhưng phải viết `vApplicationGetIdleTaskMemory` (+ timer). |

### 3.2 Nhóm bật/tắt module (1 = biên dịch file .c tương ứng vào image)

| Macro | Bật thì nhớ thêm file | Gợi ý |
|---|---|---|
| `configUSE_TIMERS` (`1`) | `timers.c` (+ task daemon tốn `configTIMER_TASK_STACK_DEPTH` word heap) | Bật nếu dùng `xTimerCreate`; timer chạy ở `configTIMER_TASK_PRIORITY` (thường cao nhất). |
| `configUSE_EVENT_GROUPS` (`1`) | `event_groups.c` | Bật khi đồng bộ "đợi nhiều cờ" (`xEventGroupSync` rendezvous). |
| `configUSE_STREAM_BUFFERS` (`1`) | `stream_buffer.c` | Bật cho luồng byte task↔ISR (thay queue khi cần throughput). |
| `configUSE_CO_ROUTINES` (`0`) | `croutine.c` | **Luôn 0** (legacy). |
| `configUSE_MUTEXES` (`1`), `configUSE_RECURSIVE_MUTEXES` (`0`), `configUSE_COUNTING_SEMAPHORES` (`1`) | nằm sẵn trong `queue.c` | Bật mutex/counting; recursive chỉ khi library đệ quy cần. |
| `configUSE_QUEUE_SETS` (`0`), `configUSE_TASK_NOTIFICATIONS` (`1`) | queue/tasks sẵn có | Queue-set hiếm dùng → 0. Task notification (nhẹ hơn semaphore ~45%) → 1. |
| `configUSE_TRACE_FACILITY`, `configGENERATE_RUN_TIME_STATS`, `configUSE_STATS_FORMATTING_FUNCTIONS` | kéo `stdio`-like format | Bring-up để `0` (nhẹ); bật khi cần `vTaskList()` debug (nhớ cung cấp clock + `utoa`-like). |

### 3.3 Nhóm debug/phòng thủ (bring-up bật hết, sản phẩm cân nhắc)

`configCHECK_FOR_STACK_OVERFLOW=2` + `vApplicationStackOverflowHook` (in tên task
qua UART rồi treo); `configUSE_MALLOC_FAILED_HOOK=1`; `configASSERT(x)` →
`tắt ngắt + uart_puts(__FILE__ + dòng) + vòng lặp vô hạn` (đừng để trống!);
`configQUEUE_REGISTRY_SIZE=0` (chỉ cho debugger kernel-aware).
`configIDLE_SHOULD_YIELD=1`, `configUSE_TICKLESS_IDLE=0` (tickless chỉ khi đã đo
được dòng ngủ trên board thật), `configUSE_TICK_HOOK=0`/`configUSE_IDLE_HOOK=0`
(trừ khi cần đặt CPU vào WFI trong idle).


> `extern/FreeRTOS-Kernel`, build lại, không mất cấu hình.



## 4. Cấu hình riêng theo phần cứng (A76 và R52)

Phần này là "học phí" của porting: cùng 1 kernel, mỗi chip cần 1 port + 1 bản
`FreeRTOSConfig*.h` + 1 hàm dựng ngắt tick + địa chỉ GIC/timer/UART riêng.

### 4.1 Chọn port nào cho từng profile (kết quả khảo sát repo V11.3.x)

| Profile | Port dùng được ngay | Vì sao chọn nó |
|---|---|---|
| **a76** (AArch64, QEMU `virt` có GIC) | `FR/portable/GCC/ARM_AARCH64/` (`port.c` ~22 KB, `portASM.S` có `FreeRTOS_IRQ_Handler`, `FreeRTOS_SWI_Handler`, `vPortRestoreTaskContext`) | Port AArch64 generic; `README.md` ghi "dùng làm điểm xuất phát cho application processor Armv8-A". |
| **r52** (AArch32 Thumb, `mps3-an536` không GIC) | `FR/portable/GCC/ARM_CRx_No_GIC/` (`portASM.S` có `FreeRTOS_IRQ_Handler`, `FreeRTOS_SVC_Handler`, `vPortRestoreTaskContext`, `vPortYield`...) | Dòng duy nhất cho họ Cortex-R không GIC — đúng kiến trúc AN536 (vector ở 0, TCM). |

Không dùng: `ARM_CA53_64_BIT/` chỉ còn `README.md` (đã rút code, trỏ sang
`ARM_AARCH64`); `ARM_CR5` đòi GIC (`configINTERRUPT_CONTROLLER_BASE_ADDRESS`)
mà AN536 không có; `ARM_CRx_MPU` chỉ khi cần MPU.

> Cách tự kiểm tra port nào hợp lệ: đọc `#error` ở đầu `port.c` — trình biên dịch
> sẽ mách đúng macro còn thiếu.

### 4.2 Nhóm macro GIC cho A76 (port `ARM_AARCH64`)

| Macro | Giá trị trên QEMU `virt` | Ghi chú |
|---|---|---|
| `configINTERRUPT_CONTROLLER_BASE_ADDRESS` | `0x08000000` (GIC Distributor) | Chuẩn `virt`: GICD `0x0800_0000`, GICC `0x0801_0000`. QEMU tự dựng GIC theo `-M virt`. |
| `configINTERRUPT_CONTROLLER_CPU_INTERFACE_OFFSET` | `0x10000` (= GICC − GICD) | Offset từ base tới CPU interface. |
| `configUNIQUE_INTERRUPT_PRIORITIES` | `32` (GICv2) | `portmacro.h` `#error` nếu sai. |
| `configMAX_API_CALL_INTERRUPT_PRIORITY` | `18` (phải `> 32/2` và `< 32`, khác 0 — port `#error` nếu vi phạm) | Ngắt ưu tiên logic cao hơn ngưỡng này được gọi API `...FromISR`. |
| `configSETUP_TICK_INTERRUPT()` | Gọi `vPortSetupTickA76()` do bạn viết trong `src/freertos/` (lập Generic Timer: `CNTFRQ` → `CNTP_TVAL` = `CPU_HZ/TICK_HZ`, bật `CNTP_CTL`, route IRQ qua GIC tới `FreeRTOS_IRQ_Handler` → `FreeRTOS_Tick_Handler` → `xTaskIncrementTick`) | Macro chạy trong `xPortStartScheduler` (dòng ~367 `port.c`); `configCLEAR_TICK_INTERRUPT()` để trống (port đã `#define` trống nếu thiếu). |
| `configUSE_TASK_FPU_SUPPORT` | `1` (có NEON/FP) | Port `#error` nếu `__ARM_FP` có mà macro thiếu (dòng ~289). |

### 4.3 Nhóm macro tick cho R52 (port `ARM_CRx_No_GIC` — chỉ 2 macro)

| Macro | Cách viết trên `mps3-an536` |
|---|---|
| `configSETUP_TICK_INTERRUPT()` | Gọi hàm bạn viết: chọn 1 timer SP804 của AN536, nạp reload = `TIMER_HZ/configTICK_RATE_HZ`, cho phép ngắt, trỏ vector IRQ tới `FreeRTOS_IRQ_Handler` trong `portASM.S`. |
| `configCLEAR_TICK_INTERRUPT` | Ghi bit clear vào `TimerIntClr` của SP804 (quên là tick bắn liên tục, treo trong ngắt). |

So với A76: không GIC = không 5 macro base/offset/priority; đổi lại bạn tự chịu
vector + clear ngắt bằng tay. Các điểm treo driver: `vApplicationSVCHandler`,
`vApplicationIRQHandler`, `vApplicationFPUSafeIRQHandler` (`portASM.S` dòng ~235+).

### 4.4 Địa chỉ phần cứng còn lại

UART giữ nguyên `config.sh` (`a76: 0x09000000/PL011`, `r52: 0xE7C00000/CMSDK`);
stack boot giữ `0x40200000`/`0x10020000` trong `.ld`; RAM khả dụng
(`virt: 0x40000000 + 512 MB`, `mps3: 0x10000000 + 256 KB`) quyết
`configTOTAL_HEAP_SIZE` (§3.1) và vị trí heap nếu dùng `heap_5.c`.
`configMINIMAL_STACK_SIZE` tính bằng word của port (AArch64: 8 byte/word,

## 5. Build image: thêm file nào, sửa build ra sao, ví dụ app tối thiểu

### 5.1 Danh sách file biên dịch cho từng profile

Giữ nguyên 3 file hiện tại (`start_<p>.S`, `uart.c`, `kernel.c` viết lại), thêm
nhóm FreeRTOS. Thứ tự biên dịch không quan trọng (linker nối symbol sau).

```text
# NHÓM 1 — giữ nguyên (board support của repo):
src/boot/start_<p>.S          -> start.o        (_start, k_stack_push; R52 giữ vector ở 0)
src/kernel/uart.c             -> uart.o         (k_putc/k_puts/k_puthex/k_putdec, k_yield)

# NHÓM 2 — nhân FreeRTOS (chung 2 profile, thêm -I extern/FreeRTOS-Kernel/include):
extern/FreeRTOS-Kernel/tasks.c
extern/FreeRTOS-Kernel/list.c
extern/FreeRTOS-Kernel/queue.c                      (nếu dùng queue/semaphore/mutex)
extern/FreeRTOS-Kernel/timers.c                     (nếu configUSE_TIMERS=1)
extern/FreeRTOS-Kernel/event_groups.c               (nếu configUSE_EVENT_GROUPS=1)
extern/FreeRTOS-Kernel/stream_buffer.c              (nếu configUSE_STREAM_BUFFERS=1)
extern/FreeRTOS-Kernel/portable/MemMang/heap_4.c    (bring-up có thể dùng heap_1.c)

# NHÓM 3 — port riêng từng profile:
a76: extern/FreeRTOS-Kernel/portable/GCC/ARM_AARCH64/port.c
a76: extern/FreeRTOS-Kernel/portable/GCC/ARM_AARCH64/portASM.S
r52: extern/FreeRTOS-Kernel/portable/GCC/ARM_CRx_No_GIC/port.c
r52: extern/FreeRTOS-Kernel/portable/GCC/ARM_CRx_No_GIC/portASM.S

# NHÓM 4 — glue do bạn viết (mới, trong src/freertos/):
src/freertos/FreeRTOSConfig-<p>.h    (copy từ template rồi điền §3 + §4)
src/freertos/freertos_tick_<p>.c     (configSETUP_TICK_INTERRUPT / CLEAR)
src/freertos/hooks.c                 (5 hook §1.5 + configASSERT qua UART)
src/kernel/kernel.c                   (VIẾT LẠI: main() FreeRTOS như §1.6)
```

Cờ biên dịch: giữ y nguyên `-O2 -Wall -Wextra -g -ffreestanding -fno-builtin`
+ `-DUART_BASE/... -DPLAT_*` hiện tại, cộng thêm 3 `-I`:

```sh
-I extern/FreeRTOS-Kernel/include \
-I extern/FreeRTOS-Kernel/portable/GCC/ARM_AARCH64 \   # (hoặc ARM_CRx_No_GIC)
-I src/freertos                                            # (tìm FreeRTOSConfig.h)
```

Lưu ý R52: file `portASM.S` của R là ARM/Thumb — biên dịch với đúng
`-mthumb -march=armv7-a` như `start_r52.S` (không là lỗi interworking giống
warning `R_ARM_THM_CALL ... k_stack_push` từng gặp ở demOS).

### 5.2 Mở rộng linker script (giữ địa chỉ cũ, thêm ký hiệu port cần)


### 5.3 Ví dụ app tối thiểu (thay `kernel.c`, chạy được cả 2 profile)

```c
/* src/kernel/kernel.c — bản FreeRTOS: 2 task + 1 queue, thay demOS. */
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "os.h"                       /* uart: k_puts/k_putdec (giữ nguyên uart.c) */

static QueueHandle_t xQ;

static void vProducer( void *pv ) {   /* task ưu tiên 2: gửi số tăng dần */
    unsigned n = 0;
    ( void ) pv;
    for( ;; ) { xQueueSend( xQ, &n, portMAX_DELAY ); n++; vTaskDelay( pdMS_TO_TICKS( 200 ) ); }
}
static void vConsumer( void *pv ) {   /* task ưu tiên 1: nhận và in qua UART */
    unsigned v;
    ( void ) pv;
    for( ;; ) { if( xQueueReceive( xQ, &v, portMAX_DELAY ) == pdPASS ) { k_puts( "got " ); k_putdec( v ); k_puts( "\r\n" ); } }
}
void k_os_entry( void ) {             /* boot glue gọi vào đây (thay scheduler_roundrobin) */
    k_puts( "freertos bring-up\r\n" );
    xQ = xQueueCreate( 8, sizeof( unsigned ) );
    configASSERT( xQ != NULL );
    xTaskCreate( vProducer, "prod", 256, NULL, 2, NULL );
    xTaskCreate( vConsumer, "cons", 256, NULL, 1, NULL );
    vTaskStartScheduler();            /* không bao giờ trở về */
    configASSERT( 0 );                /* tới đây = hết heap (§5.4) */
}
```

### 5.4 Debug bring-up theo tầng (lỗi nào → nhìn đâu)

| Triệu chứng | Nguyên nhân hay gặp | Sửa |
|---|---|---|
| Treo ngay sau banner, không tick | `configSETUP_TICK_INTERRUPT` sai (timer không đếm / IRQ không tới `FreeRTOS_Tick_Handler`) | Soi `os-<p>.list`: breakpoint `FreeRTOS_Tick_Handler`, đếm `xTaskGetTickCount` tăng không |
| `configASSERT` nổ trong `vTaskStartScheduler` | Hết heap (`xTaskCreate`/`xTimerCreateTimerTask` trả NULL) | Tăng `configTOTAL_HEAP_SIZE`; `heap_1.c` mà tạo object sau start cũng fail |
| Treo trong ngắt (không ra task) | R52 quên `configCLEAR_TICK_INTERRUPT`; A76 sai GIC base/offset | R52: ghi `TimerIntClr`; A76: kiểm tra `0x08000000/0x10000` bằng `xp` trong gdb |
| Lỗi link `undefined: vApplication...` | Bật config static/hook mà chưa viết hàm §1.5 | Viết `hooks.c` đủ 5 hàm hoặc tắt config tương ứng |

## 6. Nạp và chạy trên QEMU

### 6.1 Câu lệnh (mở rộng `run_one()`, không đổi bản chất `-kernel`)

```sh
./run_os.sh build a76 && ./run_os.sh run a76     # Cortex-A76 / virt
./run_os.sh build r52 && ./run_os.sh run r52     # Cortex-R52 / mps3-an536
# (bản FreeRTOS: build ra os-<p>-freertos.elf rồi chạy cùng lệnh, chỉ đổi tên file)
```

QEMU đọc program headers, copy `.text/.rodata` vào RAM giả lập, zero `.bss`
(heap `ucHeap[]` nằm đây nên khởi động sạch), đặt PC = `_start`. Thoát QEMU:
`Ctrl-A X`. Kỳ vọng với app §5.3: banner `freertos bring-up`, rồi dòng
`got 0 / got 1 / ...` mỗi ~200 ms (tick 100 Hz đếm đúng khi `configCPU_CLOCK_HZ`
khớp §4).

### 6.2 Debug bằng GDB khi tick/scheduler không chạy (công thức 5 lệnh)

```sh
# cửa sổ 1: qemu-system-aarch64 -M virt -cpu cortex-a76 -m 512 \
#   -kernel build/a76/os-a76-freertos.elf -nographic -serial mon:stdio -S -s
# cửa sổ 2:
aarch64-none-elf-gdb build/a76/os-a76-freertos.elf \
  -ex 'target remote :1234' -ex 'break FreeRTOS_Tick_Handler' -ex 'continue'
# tick không tới  -> sai GIC/timer (§4.2/4.3); tới nhưng task không đổi ->
# xem pxCurrentTCB, xTaskGetTickCount; crash ngẫu nhiên -> watch stack hook §5.4.
```

Thay `aarch64-none-elf-gdb` bằng `arm-none-eabi-gdb` cho R52 (break tại
`FreeRTOS_IRQ_Handler` của `ARM_CRx_No_GIC`).

## 7. Nạp và chạy trên phần cứng thật

### 7.1 Khác QEMU ở 4 điểm (và cách xử lý từng điểm)

| Điểm khác | QEMU (hiện tại) | Board thật | Việc phải làm khi ra board |
|---|---|---|---|
| Nạp image | `-kernel elf` (QEMU tự copy + zero `.bss`) | Boot ROM chạy từ flash/SD; cần file `.bin` + địa chỉ flash | `llvm-objcopy -O binary os.elf os.bin`; sửa `.ld` cho base = địa chỉ flash/board (không còn `0x40080000` của virt) |
| Clock/timer | Tần số "đẹp" cố định (62.5/20 MHz) | Thạch anh + PLL riêng từng board | Đo/lấy đúng `configCPU_CLOCK_HZ`, viết lại `freertos_tick_<p>.c` cho timer thật, đo lại `vTaskDelay(1000)` = 1 s thật |
| UART/debug | `-serial mon:stdio` ra thẳng terminal | Cáp USB-UART + baudrate (115200...) | Sửa `uart.c` thêm init baudrate/clock của SoC thật; `configASSERT` in ra UART này |
| GIC/ngắt (A76) | QEMU dựng sẵn GICv2 | GIC của SoC thật (base khác, có thể GICv3, secure/non-secure) | Đổi 5 macro §4.2 theo datasheet; R52 thật: cấu hình MPU/TCM + watchdog tắt |

### 7.2 Quy trình ra board (từng bước, dừng lại kiểm tra mỗi bước)

1. `llvm-objcopy -O binary` → `os.bin`; nạp bằng OpenOCD/J-Link/UART-boot của
   board vào đúng base trong `.ld` đã sửa.
2. Bare-metal trước: chạy demOS cũ (`uart` + banner) trên board — UART lên là
   thắng 50% (clock + linker base đúng).
3. FreeRTOS sau: nạp `os-freertos.elf/.bin` bản §5.3; tick 100 Hz đúng
   (`got N` đều 200 ms) là thắng 90%.
4. Mới bật tiếp: heap_4, timer/event/stream, nhiều task, tickless, MPU
   (`ARM_CRx_MPU` cho R52 nếu cần cách ly).

## 8. Checklist tổng + thuật ngữ

**Checklist từ số 0 tới `got N` trên cả QEMU lẫn board:**

```text
[ ] toolchain/setup.sh xanh (clang + ld.lld + qemu) ................ §2.1
[ ] get free-rtos (V11.3.x), KHÔNG sửa file trong extern/ ........... §2.2
[ ] FreeRTOSConfig-<p>.h: điền nhóm chung (§3) + nhóm HW (§4) ........
[ ] freertos_tick_<p>.c + hooks.c + kernel.c bản FreeRTOS ............ §5.1/§5.3
[ ] build_one() mở rộng: 3 -I, heap_*.c đúng 1 file, port đúng ....... §5.1/§5.2
[ ] os-<p>-freertos.elf link OK (-e _start, .ld giữ base) ............ §5.2
[ ] QEMU ra banner + got 0/1/... đều nhịp ............................ §6.1
[ ] (board thật) .bin + base flash + UART + tick đo đúng 1 s ......... §7
```

| Thuật ngữ | Nghĩa một dòng |
|---|---|
| Port | 3 file (`port.c`/`portASM.S`/`portmacro.h`) nối kernel chung với 1 CPU cụ thể. |
| Tick | Ngắt định kỳ (`configTICK_RATE_HZ`) cho scheduler đếm thời gian và preempt. |
| TCB | Khối điều khiển task (ưu tiên, stack pointer, state) — nằm trong heap. |
| Heap FreeRTOS | Mảng tĩnh `ucHeap[configTOTAL_HEAP_SIZE]` trong `.bss`, không phải `malloc` libc. |
| Hook | Hàm callback app viết, kernel gọi (overflow/malloc-fail/idle/tick). |
| GIC | Bộ điều khiển ngắt ARM (chỉ A-profile như A76; R52/AN536 không có). |
| `pdMS_TO_TICKS` | Macro đổi mili-giây → số tick theo `configTICK_RATE_HZ`. |
| Bring-up | Giai đoạn "làm cho chạy lần đầu" trên 1 board mới: UART → tick → task → IPC. |

| Lỗi link `undefined: pxPortInitialiseStack...` | Thiếu `port.c`/`portASM.S` trong lệnh link, hoặc sai port | Kiểm tra nhóm 3 §5.1 đúng profile |
| Chạy một lúc rồi crash ngẫu nhiên | Stack task quá nhỏ / overflow | `configCHECK_FOR_STACK_OVERFLOW=2`, tăng stack 256→512, xem hook in tên task nào |

Công thức bring-up an toàn: **heap_1 + static+dynamic + ASSERT đầy đủ + 2 task +
1 queue (§5.3)** → chạy ổn trên QEMU rồi mới đổi sang heap_4, bật timer/event,
tăng task, rồi mới ra board thật (§7).


Hai `.ld` hiện tại giữ nguyên (`.text/.rodata` ở base cũ, `.bss` ở vùng stack).
Chỉ thêm 2 thứ nếu port đòi: `PROVIDE(__stack = PLAT_STACKTOP)` cho port nào
lấy đỉnh stack qua symbol, và section `.heap` riêng nếu dùng `heap_5.c` nhiều
vùng (đặt sau `.bss`, trong RAM khả dụng §4.4). Lệnh link giữ `-e _start`, thêm
toàn bộ `.o` nhóm 2+3+4 vào sau 3 file cũ:

```sh
"$LLD" -o "$w/os-$p-freertos.elf" -e _start -T toolchain/link-<p>.ld \
    start.o kernel.o uart.o tasks.o list.o queue.o timers.o \
    event_groups.o stream_buffer.o heap_4.o port.o portASM.o \
    freertos_tick_<p>.o hooks.o
```

Đặt tên output mới (`os-<p>-freertos.elf`) để song song với demOS cũ khi bring-up.

AArch32: 4 byte/word — cùng số 128 nhưng ra byte khác nhau).

