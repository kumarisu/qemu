/* freertos_tick_a76.c -- GICv2 + Generic Timer (PPI30) cho QEMU virt.
 *
 * Luong 1 lan tick:
 *   IRQ -> FreeRTOS_IRQ_Handler (portASM.S: save context, doc GICC_IAR,
 *          goi vApplicationIRQHandler(IAR)) -> FreeRTOS_Tick_Handler()
 *          (port.c: goi configCLEAR_TICK_INTERRUPT() = vClearTickInterruptA76)
 *          -> portASM ghi GICC_EOIR bang chinh gia tri IAR da ack.
 *
 * Vi vay vApplicationIRQHandler KHONG duoc doc lai GICC_IAR (IAR chi doc duoc
 * 1 lan: lan doc thu 2 tra ve 1023 = spurious) va KHONG duoc tu ghi EOIR.
 */
#include "FreeRTOS.h"
#include "task.h"

#define GICD_BASE   ( 0x08000000UL )
#define GICC_BASE   ( 0x08010000UL )
#define GICD_CTLR   ( *( volatile unsigned * )( GICD_BASE + 0x000 ) )
#define GICD_ISEN0  ( *( volatile unsigned * )( GICD_BASE + 0x100 ) )
#define GICD_IPR30  ( *( volatile unsigned * )( GICD_BASE + 0x478 ) )
#define GICC_CTLR   ( *( volatile unsigned * )( GICC_BASE + 0x000 ) )
#define GICC_PMR    ( *( volatile unsigned * )( GICC_BASE + 0x004 ) )
#define TICK_PPI    ( 30 )
/* Uu tien GIC cua tick: thap nhat trong 32 muc = 30 << 3 (portPRIORITY_SHIFT) */
#define TICK_PRIORITY   ( 0xF0u )

static unsigned tick_reload;

void vSetupTickInterruptA76( void )
{
    unsigned long freq;

    __asm volatile ( "mrs %0, cntfrq_el0" : "=r" ( freq ) );
    if( freq == 0 ) freq = configCPU_CLOCK_HZ;
    tick_reload = ( unsigned )( freq / ( unsigned long ) configTICK_RATE_HZ );

    /* GICv2 (QEMU virt): GICD @0x08000000, GICC @0x08010000.
     *   GICD_CTLR = 3: view secure -> Grp0|Grp1; view non-secure -> Grp1.
     *   GICC_CTLR = 1: Grp0 (secure) / Grp1 (non-secure) - tick la Grp1.
     *   PMR = 0xFF = portUNMASK_VALUE (port.c) - khong mask gi. */
    GICD_CTLR = 3;
    GICC_CTLR = 1;
    GICC_PMR = 0xFF;
    GICD_IPR30 = ( GICD_IPR30 & ~( 0xFFu << 24 ) ) | ( TICK_PRIORITY << 24 );
    GICD_ISEN0 = ( 1u << TICK_PPI );

    /* Generic Timer vat ly: TVAL = 1 chu ky tick, bat timer (ENABLE=1, IMASK=0). */
    __asm volatile (
        "msr cntp_tval_el0, %0\n"
        "mov x0, #1\n"
        "msr cntp_ctl_el0, x0\n"
        "isb\n" :: "r" ( ( unsigned long ) tick_reload ) : "x0", "memory" );
}

/* Duoc port.c goi (configCLEAR_TICK_INTERRUPT) trong FreeRTOS_Tick_Handler:
 * nap lai TVAL -> ha ISTATUS (xoa nguon ngat) va hen tick ke tiep. */
void vClearTickInterruptA76( void )
{
    __asm volatile ( "msr cntp_tval_el0, %0\n"
                     "isb\n" :: "r" ( ( unsigned long ) tick_reload ) : "memory" );
}

void vApplicationIRQHandler( unsigned long ulICCIAR )
{
    unsigned id = ( unsigned ) ( ulICCIAR & 0x3FFu );

    if( id == TICK_PPI )
    {
        /* FreeRTOS_Tick_Handler() goi configCLEAR_TICK_INTERRUPT() roi
         * xTaskIncrementTick(); portASM.S se ghi EOIR sau khi ham nay tra ve. */
        FreeRTOS_Tick_Handler();
    }
}
