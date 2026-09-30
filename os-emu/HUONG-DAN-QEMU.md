# Hướng dẫn vận hành QEMU trên macOS (cho repo `os-emu`)

> Tài liệu vận hành: **liệt kê simulator đang chạy → vào console/monitor →
> chạy lệnh kiểm tra → lấy logs → tắt máy**. Host là **macOS**
> (QEMU 11.1.1, accel `hvf`/`tcg`), guest là image bare-metal của repo
> (`build/<p>/os-<p>.elf` và `build/<p>/os-<p>-freertos.elf`).
> Muốn hiểu image từ đâu ra, đọc `IMAGE-OS-ELF.md` và
> `HUONG-DAN-BUILD-FREERTOS.md` trước.

## 1. Mô hình cần nắm: QEMU là 1 tiến trình macOS

- Mỗi simulator = **1 tiến trình** `qemu-system-aarch64` (profile `a76`) hoặc
  `qemu-system-arm` (profile `r52`) chạy trên macOS. Không có "QEMU daemon"
  nền — tắt terminal/kill tiến trình là tắt máy ảo.
- Guest của repo là **bare-metal** (không có Linux shell bên trong): "console"
  của nó = **UART serial** in chữ (`banner`, `got N`...), còn "lệnh kiểm tra"
  chạy trên máy ảo = **lệnh QEMU monitor** gõ từ terminal macOS (xem §3).
- Hai chế độ chạy của script repo:
  | Chế độ | Lệnh repo | Cờ QEMU | Dùng khi nào |
  |---|---|---|---|
  | Tương tác | `./run_os.sh run a76`, `./run_freertos_qemu.sh a76` | `-nographic -serial mon:stdio` | Ngồi xem serial + gõ lệnh monitor trực tiếp |
  | Headless | `./run_os.sh smoke a76 6`, `./run_freertos_qemu.sh a76 smoke 6` | `-display none -serial file:...` + chạy nền `&` | Lấy log tự động, máy tự tắt sau N giây |

## 2. Xem danh sách simulator đang chạy

### 2.1 Liệt kê tiến trình QEMU (cách chính)

```sh
pgrep -fl qemu-system
# ví dụ output:
# 66727 qemu-system-aarch64 -M virt -m 512 -cpu cortex-a76 \
#   -kernel /Users/hoadao/Documents/works/qemu/os-emu/build/a76/os-a76-freertos.elf \
#   -nographic -serial mon:stdio
```

Đọc dòng lệnh là biết ngay: machine (`-M virt`/`mps3-an536`), CPU
(`-cpu cortex-a76`), image đang nạp (`-kernel ...`), chế độ console
(`-serial mon:stdio` = tương tác, `-serial file:...` = headless).
Biến thể đầy đủ hơn (xem TTY, thời điểm start, tiến trình cha):

```sh
ps aux | grep -i qemu | grep -v grep
ps -o pid,ppid,tty,lstart,command -p <PID>
```

### 2.2 Trường hợp không thấy gì

- `pgrep` không in gì = **không có simulator nào chạy**.
- Script `smoke` tự `kill` sau N giây nên xong là hết tiến trình — muốn kiểm
  tra phải mở song song lúc nó đang chạy.
- QEMU của repo không mở cổng TCP nào (đã kiểm bằng `lsof -iTCP`), nên đừng
  tìm bằng "port" — chỉ có tiến trình + file log.
## 3. Vào console và chạy lệnh cần thiết

### 3.1 Hai loại "console" — đừng nhầm

| Loại | Là gì | Vào bằng cách nào | Gõ được gì |
|---|---|---|---|
| **Serial console** (guest → bạn) | Chữ OS in ra qua UART | Nhìn terminal đang chạy lệnh `run`, hoặc mở file `*.log` | Không gõ lệnh — chỉ đọc output (`banner`, `got N`) |
| **QEMU monitor** (bạn → QEMU) | Dòng lệnh điều khiển máy ảo | Đang ở chế độ `run` (`-serial mon:stdio`): nhấn `Ctrl-A C` để chuyển qua lại giữa serial và monitor | Lệnh `info ...`, `stop/cont`, `system_reset`, `quit`... (xem §3.3) |

### 3.2 Cách vào

**Cách A (khuyên dùng trên VS Code): monitor tách riêng — không cần Ctrl-A.**

```sh
# Terminal 1: chạy máy, monitor mở ở cổng 45454
cd /Users/hoadao/Documents/works/qemu/os-emu
./run_freertos_qemu.sh a76 mon 45454
# Serial (freertos bring-up, got 0...) hiện ngay trên terminal này.

# Terminal 2: gõ lệnh monitor (không cần tổ hợp phím nào)
nc 127.0.0.1 45454
# (qemu) info status
# (qemu) info registers
# (qemu) quit            <- tắt máy
```

> `nc` của macOS không hiểu `telnet` negotiation nên banner sẽ lẫn ký tự
> `\xff...`, nhưng lệnh vẫn chạy (`VM status: running` — đã kiểm chứng trên
> máy này). Muốn output sạch, dùng `python3` thay `nc` (xem §5).

**Cách B (chỉ ổn định trên Terminal.app / iTerm2): xoay `mon:stdio`.**

```sh
cd /Users/hoadao/Documents/works/qemu/os-emu
./run_freertos_qemu.sh a76        # hoặc: ./run_os.sh run a76
```

Serial hiện ra. Rồi nhấn **đúng nhịp**: giữ `Ctrl`, nhấn `A`, **thả cả hai**,
rồi nhấn `C` (chữ thường, không Shift). Prompt `(qemu)` hiện ra — đây là
monitor. Nhấn `Ctrl-A C` lần nữa để quay lại serial; `Ctrl-A X` hoặc `quit`
để tắt máy.

**Vì sao bạn bấm mà "không có tác dụng" (mục 2, 3, 4 ở §3.2 cũ):**

1. **VS Code integrated terminal chặn `Ctrl-A` trước QEMU.** Bạn đang dùng
   VS Code (`TERM_PROGRAM=vscode` — đã kiểm tra trên máy này): `Ctrl-A`
   là phím tắt "go-first / select-all" của editor, keypress không bao giờ
   tới tiến trình QEMU. Đây là nguyên nhân phổ biến nhất, không phải do
   QEMU hay image.
2. **Nhấn sai nhịp.** QEMU mux (`-serial mon:stdio`, xem tài liệu
   [Keys in the character backend multiplexer](https://www.qemu.org/docs/master/system/mux-chardev.html))
   đòi escape `Ctrl-A` rồi **thả ra** mới nhấn `C`. Nhấn giữ `Ctrl-A-C`
   cùng lúc, hoặc `Ctrl-Shift-A`, QEMU sẽ không nhận.
3. **Nhầm terminal.** QEMU gắn với TTY của terminal đã chạy nó — phải bấm
   phím **trên đúng terminal đang chạy lệnh `run`**. Bấm ở terminal khác
   (kể cả trước mặt) thì không có gì xảy ra.
4. **`smoke` không có monitor tương tác.** Chế độ `smoke` chạy
   `-display none -serial file:...` ở nền rồi tự kill — không có chỗ để bấm
   `Ctrl-A`. Muốn gõ lệnh thì phải dùng chế độ `run` (Cách A/B trên).

### 3.3 Lệnh monitor hay dùng để kiểm tra OS

```text
info status        # trạng thái máy: running / paused?
info cpus          # danh sách vCPU (kiểm tra thread)
info registers     # thanh ghi CPU hiện tại (PC/SP... — đối chiếu .list)
info mtree         # cây memory map (RAM/UART/GIC ở địa chỉ nào)
info qtree         # cây thiết bị (machine virt / mps3-an536 gồm gì)
x /10i $pc         # disassemble 10 lệnh tại PC (so với os-*.list)
xp /16x 0x09000000 # đọc 16 word tại UART PL011 (a76) — kiểm tra MMIO
stop               # dừng vCPU (đóng băng máy để soi registers/mtree)
cont               # chạy tiếp sau stop
system_reset       # reset máy, boot lại từ _start (test boot nhiều lần)
quit               # tắt QEMU
```

Mẹo debug treo: `stop` → `info registers` (xem PC kẹt ở `hang` nào trong
`.list`) → `x /10i $pc` → `cont`/`system_reset`. Với r52, PC kẹt ở
`hang_r52` + không serial = đúng bệnh bring-up GICv3 đã ghi trong
`HUONG-DAN-BUILD-FREERTOS.md` §5.

## 4. Lấy logs

### 4.1 Log serial có sẵn của script `smoke` (dùng trước)

```sh
./run_os.sh smoke a76 6                    # → build/a76/smoke.log (demOS)
./run_freertos_qemu.sh a76 smoke 6         # → build/a76/freertos-smoke.log
./run_freertos_qemu.sh r52 smoke 6         # → build/r52/freertos-smoke.log
cat build/a76/freertos-smoke.log | tail -20
```

Thành công thì thấy `freertos bring-up` + `got 0...got N` đều nhịp 200 ms;
thất bại thì file trống hoặc dừng sau banner — đối chiếu §6
`HUONG-DAN-BUILD-FREERTOS.md`.

### 4.2 Tự hứng serial ra file khi chạy tương tác

Thêm `-serial file:` (giữ `-nographic` để vẫn nhìn trực tiếp):

```sh
qemu-system-aarch64 -M virt -m 512 -cpu cortex-a76 \
  -kernel build/a76/os-a76-freertos.elf \
  -nographic -serial mon:stdio -serial file:/tmp/uart-a76.log
# UART thứ 2 (file) hứng song song; xem bằng: tail -f /tmp/uart-a76.log
```

### 4.3 Log nội bộ QEMU (debug sâu, không phải log guest)

```sh
qemu-system-aarch64 -M virt -m 512 -cpu cortex-a76 \
  -kernel build/a76/os-a76-freertos.elf -nographic -serial mon:stdio \
  -d int,guest_errors -D /tmp/qemu-debug.log
# -d int: ghi mọi exception/interrupt; guest_errors: truy cập MMIO sai
# xem: grep -iE 'exception|undef|abort|mmio' /tmp/qemu-debug.log | head
```

## 5. Nâng cao (tùy chọn): python3 thay `nc` + GDB

Chế độ `mon [port]` của script (§3.2 Cách A) đã là monitor-tách-riêng, không
cần tự ráp lệnh QEMU. Hai mảnh còn lại:

```sh
# Monitor sạch (không lẫn ký tự telnet \xff... như khi dùng nc):
python3 -c "import socket,time
s = socket.create_connection(('127.0.0.1',45454), timeout=5)
time.sleep(2); s.recv(4096)              # bỏ banner
s.sendall(b'info registers\n'); time.sleep(2)
print(s.recv(8192).decode(errors='replace'))"
# Muốn tắt máy từ xa: s.sendall(b'quit\n')

# GDB: dừng CPU từ đầu, chờ debugger
qemu-system-aarch64 -M virt -m 512 -cpu cortex-a76 \
  -kernel build/a76/os-a76-freertos.elf -nographic -serial mon:stdio \
  -S -s
# terminal B: gdb-multiarch build/a76/os-a76-freertos.elf \
#   -ex 'target remote :1234' -ex 'break FreeRTOS_Tick_Handler' -ex continue
```

## 6. Tắt máy + sự cố thường gặp

```sh
quit                 # trong monitor (sạch nhất)
# hoặc từ shell khác:
kill <PID>           # SIGTERM — QEMU tự dọn (smoke dùng cách này)
kill -9 <PID>        # khi treo cứng; xong kiểm tra pgrep lại
pkill -f mps3-an536  # tắt hết simulator r52 (cẩn thận khi chạy nhiều máy)
```

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| `pgrep` không thấy QEMU | Chưa chạy, hoặc `smoke` đã tự kill sau N giây | Chạy lại `run`/`smoke`; kiểm tra ngay khi đang chạy |
| Nhấn `Ctrl-A C` không ra `(qemu)` | 1 trong 4 nguyên nhân ở §3.2 (thường nhất: VS Code chặn `Ctrl-A`) | Dùng `./run_freertos_qemu.sh a76 mon 45454` + `nc` (§3.2 Cách A); hoặc sang Terminal.app/iTerm2 |
| Màn hình đứng, không serial | Guest treo trước khi in (tick/GIC sai, PC ở `hang`) | Vào monitor (Cách A/B §3.2) → `info registers` + `x /10i $pc`, đối chiếu `os-*.list` |
| `smoke.log` trống | Image treo trước UART, hoặc QEMU bị kill quá sớm | Tăng secs (`smoke a76 10`); chạy tương tác để xem trực tiếp |
| `(no serial output captured)` (r52) | Đúng bệnh bring-up AN536 (banner rồi dừng) | Xem `HUONG-DAN-BUILD-FREERTOS.md` §5; a76 không ảnh hưởng |
| `address already in use` (mon §3.2) | Cổng 45454 còn tiến trình cũ giữ | `pgrep -fl qemu-system` → `kill <PID>`, hoặc đổi cổng khác |
| Muốn chạy HVF cho nhanh | macOS hỗ trợ `hvf` | `./run_os.sh run a76 -a` (chỉ a76; r52/mps3 không dùng `-a`) |

