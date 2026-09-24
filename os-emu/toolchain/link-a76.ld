/* linker script — Cortex-A76 profile (QEMU machine "virt")
 *
 *   .text/.rodata  -> 0x40080000   (inside the virt machine RAM @0x40000000;
 *                                   matches QEMU's aarch64 -kernel load base)
 *   .bss           -> 0x40200000   (task stacks, zeroed by QEMU)
 */
OUTPUT_FORMAT("elf64-littleaarch64")

SECTIONS
{
  . = 0x40080000;
  .text   : { *(.text*) }
  .rodata : { *(.rodata*) }

  . = 0x40200000;
  .bss    : { *(.bss*) }
}