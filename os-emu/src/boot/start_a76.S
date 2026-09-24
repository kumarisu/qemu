/* start_a76.S — Cortex-A76 profile (QEMU machine "virt")
 *
 * Plain A-profile boot: QEMU loads the ELF and starts at the "entry"
 * address (symbol _start).  We set up the stack pointer (x31 = sp in the
 * ARM64 calling convention) and call the OS entry point.
 *
 *   stack top = 0x40200000  (kept in sync with config.sh stacktop-a76)
 */
    .section .text
    .global  _start
    .global  hang

_start:
    movz x30, #0x4020, lsl #16    /* scratch := 0x40200000             */
    movk x30, #0x0000
    mov  sp, x30                  /* sp := 0x40200000 (SP semantics)   */
    mov  x29, sp                  /* fp := sp                          */
    bl   k_os_entry

/* k_stack_push(new_sp) — switch the stack pointer (SP)                */
    .global k_stack_push
k_stack_push:
    mov  sp, x0                   /* MOV sp,x0 = ADD alias (SP writes)  */
    ret

hang:
    b    hang                       /* k_halt() lands here on qemu     */