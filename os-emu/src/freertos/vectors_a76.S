/* vectors_a76.S -- 16 o x 128 byte (VBAR_EL1 = bang nay, dat trong xPortStartScheduler).
 *
 *   o 0 (offset 0x00) -> sync  : FreeRTOS_SWI_Handler (portYIELD dung "SVC 0";
 *                                port kiem tra ESR.EC == SVC, khac thi abort)
 *   o 1 (offset 0x80) -> IRQ   : FreeRTOS_IRQ_Handler (tick / nguon khac)
 *   o 2 (offset 0x100)-> FIQ   : khong dung  -> hang_a76
 *   o 3 (offset 0x180)-> SError: loi nghiem trong -> hang_a76
 * (rept 4 = 4 nhom theo EL/SP cua nguon gay exception.)
 */
    .section .text
    .global _freertos_vector_table
    .align 11
_freertos_vector_table:
    .rept 4
    b FreeRTOS_SWI_Handler
    .align 7
    b FreeRTOS_IRQ_Handler
    .align 7
    b hang_a76
    .align 7
    b hang_a76
    .endr
    .global hang_a76
hang_a76:
    b hang_a76
