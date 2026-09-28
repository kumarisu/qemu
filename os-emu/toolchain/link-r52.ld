/* linker script — Cortex-R52 profile (QEMU machine "mps3-an536", AN536 image)
 *
 * The AN536 FPGA image boots the Cortex-R52 in Thumb (AArch32) state
 * with the code in TCM starting at 0 (interrupt vector base at 0).
 * RAM is at 0x10000000..0x10020000 (QEMU starts it zeroed).
 */
OUTPUT_FORMAT("elf32-littlearm")

SECTIONS
{
  . = 0x00000000;
  .text   : { *(.text*) }
  .rodata : { *(.rodata*) }

  /* Vung RW (data + bss) phai nam CUNG mot vung nho:
   * lld gop moi section RW thanh MOT PT_LOAD lien tuc. Neu .data con o dia
   * chi thap (~0x441c, ngay sau .rodata) thi segment do trai tu 0x441c den
   * het .eoi_scratch (~0x1001C004) va QEMU tu choi nap:
   *   hw/arm/boot.c: kernel_size = TONG(p_memsz) cua cac PT_LOAD, phai
   *   <= -m (ram_size), neu khong: "kernel ... is too large to fit in RAM".
   * Voi .data o 0x10000000 thi RW segment chi con ~0x1C004 byte. */
  . = 0x10000000;
  .data   : { *(.data*) }
  .bss    : { *(.bss*) *(COMMON) }

  /* Vung nho cho EOI kieu VIC cua portASM.S: sau khi IRQ xong, port ghi 1
   * word vao configEOI_ADDRESS (FreeRTOSConfig-r52.h) -- tren GICv3 day chi
   * la ghi vao bien nho vo hai (EOI thuc do vApplicationIRQHandler lam).
   * Dat '_eoi_scratch' o day de: (a) dia chi nay chac chan thuoc BRAM
   * (AN536: 0x10000000..0x10080000, 512KB) va nam tren vung stack
   * (0x1001F000..0x10020000) nen khong dam vao du lieu nao;
   * (b) neu .bss lon qua muc (>= 0x1C000) linker se bao loi.
   * Khi doi gia tri nay phai doi ca configEOI_ADDRESS trong build_freertos.sh. */
  . = 0x1001C000;
  .eoi_scratch (NOLOAD) : { _eoi_scratch = .; . += 4; }
}