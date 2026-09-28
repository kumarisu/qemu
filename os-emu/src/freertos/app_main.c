/* app_main.c -- app mau FreeRTOS: 2 task + 1 queue. */
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "os.h"
static QueueHandle_t xQ;
static void vProd( void *p ) { unsigned n = 0; ( void ) p; for( ;; ) { xQueueSend( xQ, &n, portMAX_DELAY ); n++; vTaskDelay( pdMS_TO_TICKS( 200 ) ); } }
static void vCons( void *p ) { unsigned v; ( void ) p; for( ;; ) if( xQueueReceive( xQ, &v, portMAX_DELAY ) == pdPASS ) { k_puts( "got " ); k_putdec( v ); k_puts( "\r\n" ); } }

/* Cho phep FP/SIMD truoc khi chay bat ky code C nao.
 *
 * Ly do (da debug tren QEMU): sau reset CPACR.FPEN = 0, moi lenh FP/SIMD deu
 * sinh exception. Clang -O2 tu vector hoa vong lap trong libc_mini.c
 * (memset -> "dup v0.16b, w1"), ma port ARM_AARCH64 lai bat
 * configUSE_TASK_FPU_SUPPORT = 2 (moi task co context FPU) => phai mo FP.
 *
 * A76 (AArch64) : FPEN la 1 field (bit 21:20) cho ca FP lan AdvSIMD.
 * r52 (AArch32) : CPACR co HAI field rieng -- CP10 (bit 21:20, D0-D15) va
 *                 CP11 (bit 23:22, D16-D31), phai bat CA HAI = 0b11.
 *                 Nhung rieng r52 thi build da dung "-mfpu=none" (config.sh)
 *                 de clang khong sinh VFP/NEON nua, vi:
 *                   - port ARM_CRx_No_GIC khong luu/trao FP-SIMD khi doi task;
 *                   - QEMU cortex-r52 tren mps3-an536 van tra Undefined
 *                     Instruction cho vdup/vst (ke ca khi CPACR.CP10=CP11=0b11,
 *                     CPTR_EL2=0 va -cpu cortex-r52,neon=on).
 *                 Doan duoi giu lai cho dung/mach lac: neu sau nay bo
 *                 -mfpu=none thi phan CPACR da san.
 */
static void vPortEnableFPU( void )
{
#if defined( __aarch64__ )
    __asm volatile ( "mrs x0, cpacr_el1 \n"
                     "orr x0, x0, #( 3 << 20 ) \n"   /* FPEN = 0b11: EL0/EL1 khong trap */
                     "msr cpacr_el1, x0 \n"
                     "isb \n" ::: "x0", "memory" );
#elif defined( __arm__ )
    /* AArch32: CPACR co HAI field rieng -- CP10 (bit 21:20, D0-D15) va
     * CP11 (bit 23:22, D16-D31). Phai bat CA HAI = 0b11, thieu mot
     * cai la moi lenh VFP/NEON thanh Undefined Instruction. Clang vector hoa
     * bang q8..q15 (= D16+) -- vi du "vdup.8 q8, r1" trong memset -- nen chi
     * bat CP10 la chet ngay sau khi in banner:
     *   Taking exception 1 [Undefined Instruction] ... ESR 0x0/0x2000000 */
    __asm volatile ( "mrc p15, 0, r0, c1, c0, 2 \n"
                     "orr r0, r0, #( 0xf << 20 ) \n"  /* CP10 = CP11 = 0b11 */
                     "mcr p15, 0, r0, c1, c0, 2 \n"
                     "isb \n" ::: "r0", "memory" );
#endif
}

void k_os_entry( void )
{
    vPortEnableFPU();       /* phai la viec dau tien (xem chu thich tren) */
    k_puts( "freertos bring-up\r\n" );
    xQ = xQueueCreate( 8, sizeof( unsigned ) );
    configASSERT( xQ != NULL );
    xTaskCreate( vProd, "prod", 256, NULL, 2, NULL );
    xTaskCreate( vCons, "cons", 256, NULL, 1, NULL );
    vTaskStartScheduler();
    configASSERT( 0 );
}
