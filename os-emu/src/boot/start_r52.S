/* start_r52.S — Cortex-R52 profile (QEMU machine "mps3-an536")
 *
 * The AN536 FPGA image boots the Cortex-R52 in **Thumb (AArch32)** state
 * (the R52 runs A32 at exception level 0).  The image therefore is a
 * 32-bit ARM ELF, laid out like the official AN536 demo:
 *
 *   @+0x00  LDR sp,=stacktop   (runs first, then branches to reset)
 *   @+0x08  .word Undefined instruction handler
 *   @+0x0c  .word Software interrupt handler
 *   @+0x10  .word Prefetch abort handler
 *   @+0x14  .word Data abort handler
 *   @+0x18  .word Reserved
 *   @+0x1c  .word IRQ handler
 *   @+0x20  .word FIQ handler
 *
 *   stack top = 0x10020000  (kept in sync with config.sh stacktop-r52)
 *   (0x10020000 sits just above the .bss block at 0x10000000)
 */
    .section .text
    .global  _start
    .global  reset
    .global  hang

_start:
    ldr sp, =stacktop               /* sp := 0x10020000 (literal pool)  */
    b    reset

    .word hang                      /* 0x08 Undefined instruction        */
    .word hang                      /* 0x0c Software interrupt           */
    .word hang                      /* 0x10 Prefetch abort               */
    .word hang                      /* 0x14 Data abort                   */
    .word hang                      /* 0x18 Reserved                     */
    .word hang                      /* 0x1c IRQ                          */
    .word hang                      /* 0x20 FIQ                          */

reset:
    cpsid if                        /* mask IRQ+FIQ (R52/EL2): the AN536  */
                                    /* EL2 vector base is unmapped; keep */
                                    /* interrupts off for the bare-metal */
                                    /* demo                             */
    bl   k_os_entry

/* k_stack_push(new_sp) — switch the stack pointer (r13 = sp)          */
    .global k_stack_push
k_stack_push:
    mov  sp, r0
    bx   lr

hang:
    b    hang

    .section .text
stacktop:
    .word 0x10020000
    .align
