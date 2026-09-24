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

  . = 0x10000000;
  .bss    : { *(.bss*) }
}